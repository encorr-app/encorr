import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/key_event_utils.dart';
import '../../focus/locked_hub_controller.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/seerr_provider.dart';
import '../../services/device_performance.dart';
import '../../services/image_cache_service.dart';
import '../../services/seerr/seerr_models.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/layout_constants.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/navigation_transitions.dart';
import '../../utils/platform_detector.dart';
import '../../utils/scroll_utils.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focus_builders.dart';
import '../../widgets/horizontal_scroll_with_arrows.dart';
import 'seerr_media_detail_screen.dart';

// ─── TMDB image CDN helpers ─────────────────────────────────────────────

/// Poster URL on the TMDB image CDN, or null when [posterPath] is missing.
String? tmdbPosterUrl(String? posterPath, {String size = 'w342'}) =>
    (posterPath == null || posterPath.isEmpty) ? null : 'https://image.tmdb.org/t/p/$size$posterPath';

/// Backdrop URL on the TMDB image CDN, or null when [backdropPath] is missing.
String? tmdbBackdropUrl(String? backdropPath, {String size = 'original'}) =>
    (backdropPath == null || backdropPath.isEmpty) ? null : 'https://image.tmdb.org/t/p/$size$backdropPath';

/// Four-digit year from a `YYYY-MM-DD` date string, or null.
int? seerrYearFromDate(String? date) {
  if (date == null || date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}

// ─── Status badge ───────────────────────────────────────────────────────

Color seerrStatusColor(SeerrMediaStatus status) => switch (status) {
  SeerrMediaStatus.available => const Color(0xFF2E9E5B),
  SeerrMediaStatus.partiallyAvailable => const Color(0xFF2E9E5B),
  SeerrMediaStatus.processing => const Color(0xFF4F6BD8),
  SeerrMediaStatus.pending => const Color(0xFF9C5BD8),
  SeerrMediaStatus.unknown || SeerrMediaStatus.deleted => Colors.transparent,
};

String seerrStatusLabel(SeerrMediaStatus status) => switch (status) {
  SeerrMediaStatus.available => 'Available',
  SeerrMediaStatus.partiallyAvailable => 'Partially available',
  SeerrMediaStatus.processing => 'Processing',
  SeerrMediaStatus.pending => 'Pending',
  SeerrMediaStatus.unknown || SeerrMediaStatus.deleted => '',
};

IconData seerrStatusIcon(SeerrMediaStatus status) => switch (status) {
  SeerrMediaStatus.available => Symbols.check_rounded,
  SeerrMediaStatus.partiallyAvailable => Symbols.check_rounded,
  SeerrMediaStatus.processing => Symbols.downloading_rounded,
  SeerrMediaStatus.pending => Symbols.hourglass_top_rounded,
  SeerrMediaStatus.unknown || SeerrMediaStatus.deleted => Symbols.add_rounded,
};

/// Small availability indicator for Seerr cards and detail pages.
///
/// [compact] renders an icon-only circle (poster overlay); otherwise a
/// labeled pill for detail layouts. Renders nothing for unknown/deleted.
class SeerrStatusBadge extends StatelessWidget {
  final SeerrMediaStatus status;
  final bool compact;

  const SeerrStatusBadge({super.key, required this.status, this.compact = true});

  @override
  Widget build(BuildContext context) {
    if (status == SeerrMediaStatus.unknown || status == SeerrMediaStatus.deleted) {
      return const SizedBox.shrink();
    }
    final color = seerrStatusColor(status);

    if (compact) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.35), width: 1),
        ),
        child: Center(child: AppIcon(seerrStatusIcon(status), fill: 1, size: 14, color: Colors.white)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(seerrStatusIcon(status), fill: 1, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            seerrStatusLabel(status),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ─── Poster card ────────────────────────────────────────────────────────

/// Full-bleed TMDB poster card with an availability badge. Focus decoration
/// is applied by the caller (locked-focus wrapper); this is just the content.
class SeerrPosterCard extends StatelessWidget {
  final SeerrDiscoverResult item;
  final double width;
  final double height;

  const SeerrPosterCard({super.key, required this.item, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final posterUrl = tmdbPosterUrl(item.posterPath);
    // Status comes from the provider cache (primed from discover payloads) so
    // badges refresh when a request is submitted elsewhere in the app.
    final type = item.type;
    final cached = type == null ? null : context.watch<SeerrProvider>().cachedStatus(item.id, type);
    final status = cached ?? item.status;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radiusSm),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (posterUrl != null)
              CachedNetworkImage(
                imageUrl: posterUrl,
                cacheManager: PlexImageCacheManager.instance,
                fit: BoxFit.cover,
                fadeInDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
                fadeOutDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
                placeholder: (context, url) =>
                    ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                errorBuilder: (context, error, stackTrace) => _buildFallback(context),
              )
            else
              _buildFallback(context),
            Positioned(top: 6, right: 6, child: SeerrStatusBadge(status: status)),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                item.type == SeerrMediaType.tv ? Symbols.tv_rounded : Symbols.movie_rounded,
                fill: 1,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                item.displayTitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Navigation helper ──────────────────────────────────────────────────

/// Open a Seerr discover/search result. Items already available in Plex try
/// to deep-link into the matching library item (title + year match via the
/// aggregation search); everything else opens [SeerrMediaDetailScreen].
Future<void> openSeerrResult(BuildContext context, SeerrDiscoverResult result) async {
  final type = result.type;
  if (type == null) return;

  final seerr = context.read<SeerrProvider>();
  final status = seerr.cachedStatus(result.id, type) ?? result.status;
  if (status == SeerrMediaStatus.available) {
    final opened = await _tryOpenInLibrary(context, result, type);
    if (opened) return;
  }

  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(fadeRoute(SeerrMediaDetailScreen(tmdbId: result.id, mediaType: type, initial: result)));
}

Future<bool> _tryOpenInLibrary(BuildContext context, SeerrDiscoverResult result, SeerrMediaType type) async {
  final title = result.displayTitle.trim();
  if (title.isEmpty) return false;

  try {
    final multiServer = context.read<MultiServerProvider>();
    if (!multiServer.hasConnectedServers) return false;

    final year = seerrYearFromDate(result.displayDate);
    final matches = await multiServer.aggregationService.searchAcrossServers(title, limit: 20);
    final lowerTitle = title.toLowerCase();
    MediaItem? match;
    for (final item in matches) {
      final isRightType = type == SeerrMediaType.movie ? item.isMovie : item.isShow;
      if (!isRightType) continue;
      if (item.displayTitle.trim().toLowerCase() != lowerTitle) continue;
      if (year != null && item.year != null && item.year != year) continue;
      match = item;
      break;
    }
    if (match == null || !context.mounted) return false;

    await navigateToMediaItem(context, match);
    return true;
  } catch (e) {
    appLogger.w('Seerr: library deep-link failed, falling back to Seerr detail', error: e);
    return false;
  }
}

// ─── Hub section (rail) ─────────────────────────────────────────────────

/// Horizontal rail of [SeerrPosterCard]s with the same locked-focus d-pad
/// pattern as [HubSection]: one Focus node per rail, visual focus index in
/// state, arrow keys never escape to random elements.
class SeerrHubSection extends StatefulWidget {
  /// Stable id used for per-hub focus memory.
  final String hubId;
  final String title;
  final IconData icon;
  final List<SeerrDiscoverResult> items;
  final void Function(SeerrDiscoverResult item)? onItemSelected;

  /// Reports the focused item — used by the TV spotlight backdrop.
  final ValueChanged<SeerrDiscoverResult>? onFocusedItemChanged;

  /// Vertical d-pad navigation between rails. Return true when handled.
  final bool Function(bool isUp)? onVerticalNavigation;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateToSidebar;
  final VoidCallback? onBack;

  const SeerrHubSection({
    super.key,
    required this.hubId,
    required this.title,
    required this.icon,
    required this.items,
    this.onItemSelected,
    this.onFocusedItemChanged,
    this.onVerticalNavigation,
    this.onNavigateUp,
    this.onNavigateToSidebar,
    this.onBack,
  });

  @override
  State<SeerrHubSection> createState() => SeerrHubSectionState();
}

class SeerrHubSectionState extends State<SeerrHubSection> with MountedSetStateMixin {
  late final FocusNode _hubFocusNode = FocusNode(debugLabel: 'seerr_hub_${widget.hubId}');
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  int _focusedIndex = 0;
  double _itemExtent = 0;
  double _leadingPadding = 12;

  @override
  void initState() {
    super.initState();
    _hubFocusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(SeerrHubSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      _itemKeys.removeWhere((index, _) => index >= widget.items.length);
      final maxIndex = widget.items.isEmpty ? 0 : widget.items.length - 1;
      if (_focusedIndex > maxIndex) _focusedIndex = maxIndex;
    }
  }

  @override
  void dispose() {
    _hubFocusNode.removeListener(_onFocusChange);
    _hubFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _itemKeyFor(int index) => _itemKeys.putIfAbsent(index, () => GlobalKey());

  void _onFocusChange() {
    if (_hubFocusNode.hasFocus) _notifyFocusedItemChanged();
    setStateIfMounted(() {});
  }

  bool get hasFocusedItem => _hubFocusNode.hasFocus;

  /// Request focus on this rail at a specific item index.
  void requestFocusAt(int index) {
    if (widget.items.isEmpty) return;
    final clamped = index.clamp(0, widget.items.length - 1).toInt();
    _focusedIndex = clamped;
    HubFocusMemory.setForHub(widget.hubId, clamped);
    _notifyFocusedItemChanged();
    _scrollToIndex(clamped);
    _hubFocusNode.requestFocus();
    setStateIfMounted(() {});
    scrollContextToCenter(context);
  }

  /// Request focus using the stored per-hub memory.
  void requestFocusFromMemory() {
    requestFocusAt(HubFocusMemory.getForHub(widget.hubId, widget.items.length));
  }

  void _scrollToIndex(int index, {bool animate = true}) {
    scrollListToIndex(_scrollController, index, itemExtent: _itemExtent, leadingPadding: _leadingPadding, animate: animate);
    if (index >= 0 && index < widget.items.length) {
      scrollKeyedChildToHorizontalCenter(
        _scrollController,
        _itemKeyFor(index),
        animate: animate,
        isCurrent: () => _focusedIndex == index && index < widget.items.length,
      );
    }
  }

  void _notifyFocusedItemChanged() {
    if (_focusedIndex < 0 || _focusedIndex >= widget.items.length) return;
    widget.onFocusedItemChanged?.call(widget.items[_focusedIndex]);
  }

  void _activateCurrentItem() {
    if (_focusedIndex < 0 || _focusedIndex >= widget.items.length) return;
    widget.onItemSelected?.call(widget.items[_focusedIndex]);
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;

    if (key.isSelectKey) {
      if (SelectKeyUpSuppressor.consumeIfSuppressed(event)) return KeyEventResult.handled;
      return handleOneShotSelect(event, _activateCurrentItem);
    }

    if (widget.onBack != null) {
      final backResult = handleBackKeyAction(event, widget.onBack!);
      if (backResult != KeyEventResult.ignored) return backResult;
    }

    if (!event.isActionable) return KeyEventResult.ignored;
    if (widget.items.isEmpty) return KeyEventResult.ignored;

    if (key.isLeftKey) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        HubFocusMemory.setForHub(widget.hubId, _focusedIndex);
        _notifyFocusedItemChanged();
        _scrollToIndex(_focusedIndex);
      } else {
        widget.onNavigateToSidebar?.call();
      }
      return KeyEventResult.handled;
    }

    if (key.isRightKey) {
      if (_focusedIndex < widget.items.length - 1) {
        setState(() => _focusedIndex++);
        HubFocusMemory.setForHub(widget.hubId, _focusedIndex);
        _notifyFocusedItemChanged();
        _scrollToIndex(_focusedIndex);
      }
      return KeyEventResult.handled;
    }

    if (key.isUpKey) {
      final handled = widget.onVerticalNavigation?.call(true) ?? false;
      if (!handled) widget.onNavigateUp?.call();
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      widget.onVerticalNavigation?.call(false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  double _cardWidthFor(double availableWidth, bool isTv) {
    if (!isTv) return 124;
    final usable = (availableWidth - (_leadingPadding * 2)).clamp(1.0, double.infinity);
    return (usable / 6.5).clamp(150.0, 250.0).toDouble();
  }

  void _onItemTapped(int index) {
    if (widget.items.isEmpty) return;
    final clamped = index.clamp(0, widget.items.length - 1).toInt();
    setState(() => _focusedIndex = clamped);
    HubFocusMemory.setForHub(widget.hubId, clamped);
    _notifyFocusedItemChanged();
    _scrollToIndex(clamped);
    _hubFocusNode.requestFocus();
    _activateCurrentItem();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final hasFocus = _hubFocusNode.hasFocus;
    final isTv = PlatformDetector.isTV();
    _leadingPadding = isTv ? TvLayoutConstants.shelfHorizontalInset : 12.0;
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontSize: isTv ? 24 : null, fontWeight: FontWeight.w700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(_leadingPadding, isTv ? 6 : 2, 8, isTv ? 8 : 2),
          child: ExcludeFocus(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(widget.icon, fill: 1, size: isTv ? 26 : null),
                SizedBox(width: isTv ? 12 : 8),
                Flexible(
                  child: Text(widget.title, style: titleStyle, overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
        Focus(
          focusNode: _hubFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = _cardWidthFor(constraints.maxWidth, isTv);
              final cardHeight = cardWidth * 1.5;
              _itemExtent = cardWidth + 8;

              return SizedBox(
                height: cardHeight + (isTv ? 18 : 10),
                child: HorizontalScrollWithArrows(
                  controller: _scrollController,
                  builder: (scrollController) => ListView.builder(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: EdgeInsets.symmetric(horizontal: _leadingPadding, vertical: isTv ? 6 : 2),
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isItemFocused = hasFocus && index == _focusedIndex;
                      return Padding(
                        key: _itemKeyFor(index),
                        padding: const EdgeInsets.only(right: 8),
                        child: FocusBuilders.buildLockedFocusWrapper(
                          context: context,
                          isFocused: isItemFocused,
                          borderRadius: tokens(context).radiusSm,
                          onTap: () => _onItemTapped(index),
                          child: SeerrPosterCard(item: item, width: cardWidth, height: cardHeight),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
