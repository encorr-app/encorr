import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show routeObserver;
import '../mpv/models.dart';
import '../mpv/player/player.dart';
import '../mpv/video.dart';
import '../providers/seerr_provider.dart';
import '../services/device_performance.dart';
import '../services/seerr/seerr_models.dart';
import '../services/settings_service.dart';
import '../services/trailer_service.dart';
import '../utils/app_logger.dart';

/// Handle into an [InlineTrailerPlayer] for the host page's unmute/replay
/// affordance. Notifies listeners whenever playback state changes so the
/// host can show/hide its controls.
class InlineTrailerPlayerController extends ChangeNotifier {
  _InlineTrailerPlayerState? _state;

  /// A trailer is decoded and visibly playing over the static backdrop.
  bool get isActive => _state?._videoVisible ?? false;

  bool get isMuted => _state?._muted ?? true;

  /// Whether the resolved stream carries audio (muxed). Video-only streams
  /// cannot be unmuted; hide the unmute affordance when this is false.
  bool get canUnmute => _state?._hasAudio ?? false;

  Future<void> toggleMute() async => _state?._toggleMute();

  /// Restart the trailer from the beginning.
  Future<void> replay() async => _state?._replay();

  void pause() => _state?._pausePlayback();

  void resume() => _state?._resumePlayback();

  void _attach(_InlineTrailerPlayerState state) {
    _state = state;
  }

  void _detach(_InlineTrailerPlayerState state) {
    if (_state == state) _state = null;
  }

  void _changed() => notifyListeners();
}

/// Background trailer layer for detail pages: renders [child] (the static
/// backdrop) and, after [SettingsService.trailerDelaySeconds], fades a
/// muted looping trailer in above it. The page's scrims/foreground stack
/// above this widget so legibility is unaffected.
///
/// The trailer source is either a direct [streamUrl] or a [tmdbId] +
/// [mediaType] pair resolved through [TrailerService] (Seerr
/// `relatedVideos` → youtube_explode_dart). Every failure path silently
/// leaves the static backdrop in place.
///
/// Gating: [SettingsService.autoPlayTrailers], the reduced performance tier
/// ([DevicePerformance.isReduced]), [enabled], and
/// [supportsEmbeddedPlayback] (see below) must all allow playback.
///
/// ## Native embedding status
///
/// True inline playback needs the native player to (a) render into a
/// Flutter `Texture` so it composites between the static art and the
/// foreground UI, and (b) support a second instance alongside the
/// full-screen player. Today neither holds on the shipping platforms:
///
/// * **Android (ExoPlayer + MPV fallback)** — video renders into a
///   full-window `SurfaceView` hole-punched *behind* the Flutter view
///   (`MpvPlayerCore`/`FlutterOverlayHelper`), so an inline trailer would
///   be invisible behind the opaque detail UI. Both plugins are also
///   single-core singletons on their method channels
///   (`com.plezy/exo_player`, `com.plezy/mpv_player`): a trailer instance
///   would steal the core from any active `VideoPlayerScreen`.
/// * **Windows** — `PlayerWindows` embeds a native window behind the
///   Flutter window (`textureId == null`, `VideoRectSupport`), same
///   visibility problem, same singleton channel.
/// * **macOS/iOS** — MPVKit renders to a full-window Metal layer.
/// * **Linux** — mpv does return a Flutter texture id, but shares the
///   singleton `com.plezy/mpv_player` channel with the full player.
///
/// [supportsEmbeddedPlayback] is therefore `false` until the native
/// plugins grow texture-backed multi-instance playback; the widget then
/// works without further Dart changes. Everything else (gating, delayed
/// start, stream resolution, mute/loop/fade, route-aware pause, the
/// controller surface) is fully implemented and exercised the moment the
/// flag flips.
class InlineTrailerPlayer extends StatefulWidget {
  /// Direct stream URL. Takes precedence over [tmdbId]/[mediaType].
  final String? streamUrl;

  /// Whether [streamUrl] has an audio track. Ignored when resolving via
  /// [tmdbId] (the resolution carries its own flag).
  final bool streamUrlHasAudio;

  /// TMDB id to resolve a trailer for via Seerr + YouTube.
  final int? tmdbId;
  final SeerrMediaType? mediaType;

  /// Static backdrop rendered beneath the trailer and shown whenever the
  /// trailer is not playing.
  final Widget child;

  final InlineTrailerPlayerController? controller;

  /// Extra host-side gate (e.g. "page is revealed").
  final bool enabled;

  /// Called when the trailer fades in (true) or stops/fades out (false).
  final ValueChanged<bool>? onActiveChanged;

  const InlineTrailerPlayer({
    super.key,
    required this.child,
    this.streamUrl,
    this.streamUrlHasAudio = true,
    this.tmdbId,
    this.mediaType,
    this.controller,
    this.enabled = true,
    this.onActiveChanged,
  });

  /// Whether this build can composite a second native player instance as a
  /// Flutter texture. See the class docs for the per-platform analysis.
  static bool get supportsEmbeddedPlayback => false;

  @override
  State<InlineTrailerPlayer> createState() => _InlineTrailerPlayerState();
}

class _InlineTrailerPlayerState extends State<InlineTrailerPlayer> with RouteAware, WidgetsBindingObserver {
  Timer? _delayTimer;
  Player? _player;
  StreamSubscription<void>? _firstFrameSubscription;
  StreamSubscription<bool>? _completedSubscription;
  PageRoute<dynamic>? _route;

  bool _videoVisible = false;
  bool _muted = true;
  bool _hasAudio = false;
  bool _pausedByNavigation = false;
  bool _startRequested = false;
  bool _disposed = false;

  bool get _gatesAllowPlayback {
    if (!widget.enabled) return false;
    if (!InlineTrailerPlayer.supportsEmbeddedPlayback) return false;
    if (DevicePerformance.isReduced) return false;
    final settings = SettingsService.instanceOrNull;
    if (settings == null || !settings.read(SettingsService.autoPlayTrailers)) return false;
    return widget.streamUrl != null || (widget.tmdbId != null && widget.mediaType != null);
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    WidgetsBinding.instance.addObserver(this);
    _scheduleStart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || route == _route) return;
    if (_route != null) routeObserver.unsubscribe(this);
    _route = route;
    routeObserver.subscribe(this, route);
  }

  @override
  void didUpdateWidget(InlineTrailerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    final sourceChanged =
        oldWidget.streamUrl != widget.streamUrl ||
        oldWidget.tmdbId != widget.tmdbId ||
        oldWidget.mediaType != widget.mediaType;
    if (sourceChanged) {
      _teardownPlayback();
      _startRequested = false;
      _scheduleStart();
    } else if (!oldWidget.enabled && widget.enabled && !_startRequested) {
      _scheduleStart();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.controller?._detach(this);
    WidgetsBinding.instance.removeObserver(this);
    if (_route != null) routeObserver.unsubscribe(this);
    _teardownPlayback(notify: false);
    super.dispose();
  }

  // ─── Lifecycle pauses ───────────────────────────────────────────────────

  @override
  void didPushNext() {
    // Another route (e.g. the full video player) covers this page: pause
    // immediately so the trailer never competes with real playback.
    _pausedByNavigation = true;
    _pausePlayback();
  }

  @override
  void didPopNext() {
    if (_pausedByNavigation) {
      _pausedByNavigation = false;
      _resumePlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pausePlayback();
    } else if (state == AppLifecycleState.resumed && !_pausedByNavigation) {
      _resumePlayback();
    }
  }

  // ─── Playback ───────────────────────────────────────────────────────────

  void _scheduleStart() {
    if (!_gatesAllowPlayback) return;
    _startRequested = true;
    final delaySeconds = SettingsService.instanceOrNull?.read(SettingsService.trailerDelaySeconds) ?? 2;
    _delayTimer?.cancel();
    _delayTimer = Timer(Duration(seconds: delaySeconds), () => unawaited(_start()));
  }

  Future<void> _start() async {
    if (_disposed || !mounted || _player != null) return;
    if (!_gatesAllowPlayback) return;

    String? url;
    var hasAudio = widget.streamUrlHasAudio;
    if (widget.streamUrl != null) {
      url = widget.streamUrl;
    } else {
      SeerrProvider? seerr;
      try {
        seerr = context.read<SeerrProvider>();
      } catch (_) {
        seerr = null; // No provider in this subtree: trailer stays off.
      }
      if (seerr == null) return;
      final resolution = await TrailerService.instance.resolveForMedia(
        tmdbId: widget.tmdbId!,
        mediaType: widget.mediaType!,
        seerr: seerr,
      );
      url = resolution?.streamUrl;
      hasAudio = resolution?.hasAudio ?? false;
    }
    if (url == null || _disposed || !mounted || _pausedByNavigation) return;

    try {
      final useExoPlayer = SettingsService.instanceOrNull?.read(SettingsService.useExoPlayer) ?? true;
      final player = Player(useExoPlayer: useExoPlayer);
      _player = player;
      _hasAudio = hasAudio;
      _muted = true;

      _firstFrameSubscription = player.streams.playbackRestart.listen((_) => _onFirstFrame());
      // Loop fallback for backends that ignore the mpv loop property.
      _completedSubscription = player.streams.completed.listen((completed) {
        if (completed) unawaited(_loopRestart());
      });

      await player.setVolume(0);
      try {
        await player.setProperty('loop-file', 'inf');
      } catch (_) {
        // Non-mpv backend: the completed-stream listener handles looping.
      }
      await player.open(Media(url));
      // Background cover scaling; no-op on mpv backends.
      try {
        await player.setBoxFitMode(1);
      } catch (_) {}
    } catch (e) {
      appLogger.d('Trailer: inline playback start failed', error: e);
      _teardownPlayback();
    }
  }

  void _onFirstFrame() {
    if (_disposed || !mounted) return;
    final player = _player;
    if (player == null) return;
    if (player.textureId == null) {
      // No Flutter texture on this backend: inline compositing is
      // impossible, keep the static backdrop instead.
      appLogger.d('Trailer: backend has no Flutter texture, falling back to static art');
      _teardownPlayback();
      return;
    }
    setState(() => _videoVisible = true);
    widget.onActiveChanged?.call(true);
    widget.controller?._changed();
  }

  Future<void> _loopRestart() async {
    final player = _player;
    if (player == null || _disposed) return;
    try {
      await player.seek(Duration.zero);
      await player.play();
    } catch (_) {}
  }

  void _pausePlayback() {
    final player = _player;
    if (player == null) return;
    unawaited(player.pause().catchError((Object _) {}));
  }

  void _resumePlayback() {
    final player = _player;
    if (player == null || !_videoVisible) return;
    unawaited(player.play().catchError((Object _) {}));
  }

  Future<void> _toggleMute() async {
    final player = _player;
    if (player == null || !_hasAudio) return;
    _muted = !_muted;
    try {
      await player.setVolume(_muted ? 0 : 100);
    } catch (_) {}
    if (mounted) setState(() {});
    widget.controller?._changed();
  }

  Future<void> _replay() async {
    final player = _player;
    if (player == null) {
      // Trailer never started (or was torn down): try again immediately.
      _delayTimer?.cancel();
      await _start();
      return;
    }
    await _loopRestart();
  }

  void _teardownPlayback({bool notify = true}) {
    _delayTimer?.cancel();
    _delayTimer = null;
    _firstFrameSubscription?.cancel();
    _firstFrameSubscription = null;
    _completedSubscription?.cancel();
    _completedSubscription = null;
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
    final wasVisible = _videoVisible;
    _videoVisible = false;
    _muted = true;
    _hasAudio = false;
    if (notify) {
      if (mounted && !_disposed) setState(() {});
      if (wasVisible) widget.onActiveChanged?.call(false);
      widget.controller?._changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (player != null)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _videoVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              // Trailers are effectively always 16:9; FittedBox covers the
              // layer without needing the decoded video dimensions.
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: 1920,
                    height: 1080,
                    child: Video(player: player, backgroundColor: Colors.transparent),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
