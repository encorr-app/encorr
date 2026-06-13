import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../models.dart';
import '../player_base.dart';

/// Android inline/background trailer player. Renders into a Flutter [Texture]
/// via a dedicated native MPV instance on `com.plezy/inline_player`, separate
/// from the singleton full-screen ExoPlayer/MPV cores.
class PlayerInlineAndroid extends PlayerBase {
  int? _textureIdValue;

  @override
  int? get textureId => _textureIdValue;

  static const _methodChannel = MethodChannel('com.plezy/inline_player');
  static const _eventChannel = EventChannel('com.plezy/inline_player/events');

  @override
  MethodChannel get methodChannel => _methodChannel;

  @override
  EventChannel get eventChannel => _eventChannel;

  @override
  String get logPrefix => 'InlineMPV';

  @override
  String get playerType => 'inline-mpv';

  @override
  bool get supportsSecondarySubtitles => false;

  @override
  bool get attachesExternalSubtitlesAtOpen => false;

  @override
  bool get needsDecoderRefreshAfterDisplaySwitch => false;

  @override
  bool get detectsFpsAfterRender => false;

  @override
  bool get providesNativeStats => false;

  Future<void>? _initFuture;

  Future<void> _ensureInitialized() async {
    if (initialized) return;
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    try {
      final result = await invoke<Object>('initialize');
      final int? textureId;
      if (result is int) {
        textureId = result;
      } else if (result is num) {
        textureId = result.toInt();
      } else {
        textureId = null;
      }
      if (textureId == null) {
        throw Exception('Inline player returned no texture id');
      }
      _textureIdValue = textureId;

      await observeCoreProperties(trackListFormat: 'string');
      await observeProperty('demuxer-cache-time', 'double');

      initialized = true;
    } catch (e) {
      _initFuture = null;
      errorController.add(PlayerError('Inline player initialization failed: $e'));
      rethrow;
    }
  }

  @override
  Future<void> open(
    Media media, {
    bool play = true,
    bool isLive = false,
    List<SubtitleTrack>? externalSubtitles,
    Duration timelineOffset = Duration.zero,
    Duration? timelineDuration,
  }) async {
    if (disposed) return;
    await _ensureInitialized();
    final startPosition = media.start ?? Duration.zero;
    configureTimeline(offset: timelineOffset, duration: timelineDuration);
    clearTracks();
    resetPlaybackProgress(startPosition);
    setSeekable(false);

    if (media.headers != null && media.headers!.isNotEmpty) {
      final headerList = media.headers!.entries.map((e) => '${e.key}: ${e.value}').toList();
      await setProperty('http-header-fields', headerList.join(','));
    }

    if (startPosition.inSeconds > 0) {
      await setProperty('start', (startPosition.inMilliseconds / 1000.0).toString());
    } else {
      await setProperty('start', 'none');
    }

    if (!play) {
      await setProperty('pause', 'yes');
    }

    await setProperty('sid', 'no');
    await setProperty('secondary-sid', 'no');

    await command(['loadfile', media.uri, 'replace']);

    if (play) {
      await setProperty('pause', 'no');
    }
  }

  @override
  Future<void> play() async {
    await setProperty('pause', 'no');
  }

  @override
  Future<void> pause() async {
    await setProperty('pause', 'yes');
  }

  @override
  Future<void> stop() async {
    await command(['stop']);
    setSeekable(false);
  }

  @override
  Future<void> seek(Duration position) async {
    final sourcePosition = sourceSeekPosition(position);
    await runSeek(position, () => command(['seek', (sourcePosition.inMilliseconds / 1000.0).toString(), 'absolute']));
  }

  @override
  Future<void> selectAudioTrack(AudioTrack track) async {
    await setProperty('aid', track.id);
  }

  @override
  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    await setProperty('sid', track.id);
  }

  @override
  Future<void> addSubtitleTrack({required String uri, String? title, String? language, bool select = false}) async {
    final args = ['sub-add', uri, select ? 'select' : 'auto'];
    if (title != null) args.add('title=$title');
    if (language != null) args.add('lang=$language');
    await command(args);
  }

  @override
  Future<void> setVolume(double volume) async {
    await setProperty('volume', volume.toString());
    if (!disposed) setVolumeState(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    await setProperty('speed', rate.toString());
  }

  @override
  Future<void> setProperty(String name, String value) async {
    if (disposed) return;
    await _ensureInitialized();
    await invoke('setProperty', {'name': name, 'value': value});
  }

  @override
  Future<String?> getProperty(String name) async {
    if (disposed) return null;
    await _ensureInitialized();
    return await invoke<String>('getProperty', {'name': name});
  }

  @override
  Future<void> command(List<String> args) async {
    if (disposed) return;
    await _ensureInitialized();
    await invoke('command', {'args': args});
  }

  @override
  Future<void> setLogLevel(String level) async {
    if (disposed) return;
    await _ensureInitialized();
    await invoke('setLogLevel', {'level': level});
  }

  @override
  Future<void> updateFrame() async {
    if (disposed || !initialized) return;
    await invoke('updateFrame');
  }

  @override
  Future<bool> setVisible(bool visible, {bool restoreOnWindowVisible = false}) async {
    if (visible) {
      await updateFrame();
    }
    return true;
  }

  /// Whether the inline texture player is available on this build.
  static bool get isSupported => Platform.isAndroid;
}
