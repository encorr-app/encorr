import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_wrapper.dart';
import '../focus/input_mode_tracker.dart';
import '../services/seerr/seerr_models.dart';
import '../theme/mono_tokens.dart';
import 'app_icon.dart';
import 'inline_trailer_player.dart';

/// Visual state of the detail-page trailer strip.
enum DetailTrailerVisualState {
  /// Horizontal bar (~25% screen height), muted autoplay when available.
  collapsedBar,

  /// Taller strip (~55% height) after the user presses UP from details.
  expanded,

  /// Full-screen overlay; user explicitly selected the trailer.
  fullscreen,
}

/// Focus + layout controller for [DetailTrailerFocusLayout].
class DetailTrailerFocusController extends ChangeNotifier {
  DetailTrailerVisualState _state = DetailTrailerVisualState.collapsedBar;
  final FocusNode trailerFocusNode = FocusNode(debugLabel: 'detail_trailer_bar');

  DetailTrailerVisualState get state => _state;

  bool get isEngaged =>
      _state == DetailTrailerVisualState.expanded || _state == DetailTrailerVisualState.fullscreen;

  /// UP from the details panel: expand the bar, then focus the trailer zone.
  void engageFromDetails() {
    switch (_state) {
      case DetailTrailerVisualState.collapsedBar:
        _state = DetailTrailerVisualState.expanded;
        notifyListeners();
      case DetailTrailerVisualState.expanded:
        trailerFocusNode.requestFocus();
      case DetailTrailerVisualState.fullscreen:
        break;
    }
  }

  void enterFullscreen() {
    if (_state == DetailTrailerVisualState.fullscreen) return;
    _state = DetailTrailerVisualState.fullscreen;
    notifyListeners();
  }

  void exitFullscreen() {
    if (_state != DetailTrailerVisualState.fullscreen) return;
    _state = DetailTrailerVisualState.expanded;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (trailerFocusNode.canRequestFocus) trailerFocusNode.requestFocus();
    });
  }

  void collapseToBar() {
    if (_state == DetailTrailerVisualState.collapsedBar) return;
    _state = DetailTrailerVisualState.collapsedBar;
    notifyListeners();
  }

  @override
  void dispose() {
    trailerFocusNode.dispose();
    super.dispose();
  }
}

/// TV-first detail layout: trailer strip on top, details + rails below.
///
/// Default focus stays in [details]. Press UP from details to expand the
/// trailer bar; press UP again (or when expanded) to focus trailer controls.
/// Select on the trailer enters [DetailTrailerVisualState.fullscreen].
class DetailTrailerFocusLayout extends StatefulWidget {
  final DetailTrailerFocusController controller;
  final InlineTrailerPlayerController? trailerController;
  final Widget backdrop;
  final String? streamUrl;
  final bool streamUrlHasAudio;
  final int? tmdbId;
  final SeerrMediaType? mediaType;
  final bool trailerEnabled;
  final Widget details;
  final VoidCallback? onFullscreenTrailer;
  final bool isTv;

  const DetailTrailerFocusLayout({
    super.key,
    required this.controller,
    required this.backdrop,
    required this.details,
    this.trailerController,
    this.streamUrl,
    this.streamUrlHasAudio = true,
    this.tmdbId,
    this.mediaType,
    this.trailerEnabled = true,
    this.onFullscreenTrailer,
    this.isTv = true,
  });

  @override
  State<DetailTrailerFocusLayout> createState() => _DetailTrailerFocusLayoutState();
}

class _DetailTrailerFocusLayoutState extends State<DetailTrailerFocusLayout> {
  static const _collapsedFraction = 0.25;
  static const _expandedFraction = 0.55;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.trailerController?.addListener(_syncEngagement);
    _syncEngagement();
  }

  @override
  void didUpdateWidget(DetailTrailerFocusLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.trailerController != widget.trailerController) {
      oldWidget.trailerController?.removeListener(_syncEngagement);
      widget.trailerController?.addListener(_syncEngagement);
      _syncEngagement();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.trailerController?.removeListener(_syncEngagement);
    super.dispose();
  }

  void _onControllerChanged() {
    _syncEngagement();
    setState(() {});
  }

  void _syncEngagement() {
    widget.trailerController?.setUserEngaged(widget.controller.isEngaged);
  }

  double _heightFraction(DetailTrailerVisualState state) {
    return switch (state) {
      DetailTrailerVisualState.collapsedBar => _collapsedFraction,
      DetailTrailerVisualState.expanded => _expandedFraction,
      DetailTrailerVisualState.fullscreen => 1.0,
    };
  }

  KeyEventResult _handleTrailerBack(FocusNode node, KeyEvent event) {
    if (!event.logicalKey.isBackKey) return KeyEventResult.ignored;
    if (event is! KeyUpEvent) return KeyEventResult.handled;
    if (widget.controller.state == DetailTrailerVisualState.fullscreen) {
      widget.controller.exitFullscreen();
      return KeyEventResult.handled;
    }
    if (widget.controller.state == DetailTrailerVisualState.expanded) {
      widget.controller.collapseToBar();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onTrailerSelected() {
    widget.controller.enterFullscreen();
    _syncEngagement();
    widget.onFullscreenTrailer?.call();
  }

  void _onTrailerTap() {
    if (!widget.isTv) {
      if (widget.controller.state == DetailTrailerVisualState.collapsedBar) {
        widget.controller.engageFromDetails();
        _syncEngagement();
      } else {
        _onTrailerSelected();
      }
    }
  }

  Widget _buildTrailerStrip(BuildContext context, double height) {
    final t = tokens(context);
    final trailerActive = widget.trailerController?.isActive ?? false;
    final showFocusHint = widget.isTv && InputModeTracker.isKeyboardMode(context);

    Widget trailerLayer = InlineTrailerPlayer(
      streamUrl: widget.streamUrl,
      streamUrlHasAudio: widget.streamUrlHasAudio,
      tmdbId: widget.tmdbId,
      mediaType: widget.mediaType,
      controller: widget.trailerController,
      enabled: widget.trailerEnabled,
      child: widget.backdrop,
    );

    if (!widget.isTv) {
      trailerLayer = GestureDetector(onTap: _onTrailerTap, child: trailerLayer);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      height: height,
      width: double.infinity,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            trailerLayer,
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.15), Colors.transparent, t.scrimSoft],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            if (widget.isTv)
              Focus(
                onKeyEvent: _handleTrailerBack,
                child: FocusableWrapper(
                  focusNode: widget.controller.trailerFocusNode,
                  onSelect: _onTrailerSelected,
                  onNavigateDown: widget.controller.collapseToBar,
                  onBack: () {
                    if (widget.controller.state == DetailTrailerVisualState.fullscreen) {
                      widget.controller.exitFullscreen();
                    } else {
                      widget.controller.collapseToBar();
                    }
                  },
                  borderRadius: 8,
                  autoScroll: false,
                  child: AnimatedOpacity(
                    opacity: widget.controller.trailerFocusNode.hasFocus && showFocusHint ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(
                                  trailerActive ? Symbols.fullscreen_rounded : Symbols.theaters_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  trailerActive ? 'Fullscreen trailer' : 'Trailer unavailable',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final state = widget.controller.state;
    final isFullscreen = state == DetailTrailerVisualState.fullscreen;
    final barHeight = size.height * _heightFraction(state);

    if (isFullscreen) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: widget.details),
          Positioned.fill(child: _buildTrailerStrip(context, size.height)),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            child: FocusableButton(
              onPressed: widget.controller.exitFullscreen,
              onBack: widget.controller.exitFullscreen,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                child: const Center(child: AppIcon(Symbols.close_rounded, size: 24, color: Colors.white)),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTrailerStrip(context, barHeight),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: widget.details,
          ),
        ),
      ],
    );
  }
}
