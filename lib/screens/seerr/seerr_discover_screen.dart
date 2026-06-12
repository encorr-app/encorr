import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../mixins/refreshable.dart';
import '../../navigation/main_screen_scope.dart';
import '../../providers/seerr_provider.dart';
import '../../services/device_performance.dart';
import '../../services/image_cache_service.dart';
import '../../services/seerr/seerr_models.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/debouncer.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../settings/seerr_settings_screen.dart';
import 'seerr_widgets.dart';

/// Seerr "Discover+" tab: Trending / Popular Movies / Popular TV /
/// Your Requests rails. On TV the focused card drives a full-bleed
/// spotlight backdrop behind the rails.
class SeerrDiscoverScreen extends StatefulWidget {
  const SeerrDiscoverScreen({super.key});

  @override
  State<SeerrDiscoverScreen> createState() => SeerrDiscoverScreenState();
}

class _SeerrSectionData {
  final String id;
  final String title;
  final IconData icon;
  List<SeerrDiscoverResult> items = [];

  _SeerrSectionData({required this.id, required this.title, required this.icon});
}

class SeerrDiscoverScreenState extends State<SeerrDiscoverScreen>
    with Refreshable, FocusableTab, MountedSetStateMixin {
  static const _trendingId = 'seerr_trending';
  static const _moviesId = 'seerr_movies';
  static const _tvId = 'seerr_tv';
  static const _requestsId = 'seerr_requests';

  late final List<_SeerrSectionData> _sections = [
    _SeerrSectionData(id: _trendingId, title: 'Trending', icon: Symbols.local_fire_department_rounded),
    _SeerrSectionData(id: _moviesId, title: 'Popular Movies', icon: Symbols.movie_rounded),
    _SeerrSectionData(id: _tvId, title: 'Popular TV', icon: Symbols.tv_rounded),
    _SeerrSectionData(id: _requestsId, title: 'Your Requests', icon: Symbols.list_alt_rounded),
  ];

  final Map<String, GlobalKey<SeerrHubSectionState>> _hubKeys = {};

  final ValueNotifier<SeerrDiscoverResult?> _spotlightItem = ValueNotifier(null);
  final Debouncer _spotlightDebouncer = Debouncer(const Duration(milliseconds: 150));

  SeerrProvider? _provider;
  bool _wasSignedIn = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = context.read<SeerrProvider>();
      _wasSignedIn = _provider!.isSignedIn;
      _provider!.addListener(_handleProviderChanged);
      if (_wasSignedIn) _load();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_handleProviderChanged);
    _spotlightDebouncer.dispose();
    _spotlightItem.dispose();
    super.dispose();
  }

  void _handleProviderChanged() {
    final signedIn = _provider?.isSignedIn ?? false;
    if (signedIn == _wasSignedIn) return;
    _wasSignedIn = signedIn;
    if (signedIn) {
      _load();
    } else {
      setStateIfMounted(() {
        for (final section in _sections) {
          section.items = [];
        }
      });
    }
  }

  // ─── Data loading ───────────────────────────────────────────────────────

  @override
  void refresh() => _load();

  Future<void> _load() async {
    final provider = _provider ?? context.read<SeerrProvider>();
    if (!provider.isSignedIn || _loading) return;

    setStateIfMounted(() {
      _loading = true;
      _error = null;
    });

    await Future.wait([
      _loadSection(_trendingId, () async => (await provider.discoverTrending()).results),
      _loadSection(_moviesId, () async => (await provider.discoverMovies()).results),
      _loadSection(_tvId, () async => (await provider.discoverTv()).results),
      _loadRequestsSection(provider),
    ]);

    if (!mounted) return;
    final hasAnything = _sections.any((s) => s.items.isNotEmpty);
    setStateIfMounted(() {
      _loading = false;
      _error = hasAnything ? null : 'Could not load anything from Seerr.';
    });
  }

  Future<void> _loadSection(String id, Future<List<SeerrDiscoverResult>> Function() fetch) async {
    final provider = _provider;
    try {
      final items = await fetch();
      provider?.primeStatusCache(items);
      final section = _sections.firstWhere((s) => s.id == id);
      setStateIfMounted(() => section.items = items);
    } catch (e) {
      appLogger.w('Seerr: failed to load discover section $id', error: e);
    }
  }

  /// "Your Requests" rows only carry a TMDB id, so resolve a handful of
  /// detail records in parallel to get posters and titles.
  Future<void> _loadRequestsSection(SeerrProvider provider) async {
    try {
      final page = await provider.getRequests(take: 30);
      final seen = <String>{};
      final entries = <(int, SeerrMediaType)>[];
      for (final request in page.results) {
        final tmdbId = request.media?.tmdbId;
        final type = SeerrMediaType.fromApiValue(request.type ?? request.media?.mediaType);
        if (tmdbId == null || type == null) continue;
        if (!seen.add('${type.apiValue}:$tmdbId')) continue;
        entries.add((tmdbId, type));
        if (entries.length >= 12) break;
      }

      final results = await Future.wait(entries.map((entry) => _resolveRequestItem(provider, entry.$1, entry.$2)));
      final items = results.whereType<SeerrDiscoverResult>().toList();
      provider.primeStatusCache(items);
      final section = _sections.firstWhere((s) => s.id == _requestsId);
      setStateIfMounted(() => section.items = items);
    } catch (e) {
      appLogger.w('Seerr: failed to load requests section', error: e);
    }
  }

  Future<SeerrDiscoverResult?> _resolveRequestItem(SeerrProvider provider, int tmdbId, SeerrMediaType type) async {
    try {
      if (type == SeerrMediaType.movie) {
        final movie = await provider.getMovie(tmdbId);
        return SeerrDiscoverResult(
          id: movie.id,
          mediaType: SeerrMediaType.movie.apiValue,
          title: movie.title,
          posterPath: movie.posterPath,
          backdropPath: movie.backdropPath,
          overview: movie.overview,
          releaseDate: movie.releaseDate,
          mediaInfo: movie.mediaInfo,
        );
      }
      final tv = await provider.getTv(tmdbId);
      return SeerrDiscoverResult(
        id: tv.id,
        mediaType: SeerrMediaType.tv.apiValue,
        name: tv.name,
        posterPath: tv.posterPath,
        backdropPath: tv.backdropPath,
        overview: tv.overview,
        firstAirDate: tv.firstAirDate,
        mediaInfo: tv.mediaInfo,
      );
    } catch (e) {
      appLogger.w('Seerr: failed to resolve requested item tmdb $tmdbId', error: e);
      return null;
    }
  }

  // ─── Focus / navigation ─────────────────────────────────────────────────

  List<String> get _visibleSectionIds => [
    for (final section in _sections)
      if (section.items.isNotEmpty) section.id,
  ];

  GlobalKey<SeerrHubSectionState> _hubKeyFor(String id) =>
      _hubKeys.putIfAbsent(id, () => GlobalKey<SeerrHubSectionState>());

  @override
  void focusActiveTabIfReady() {
    final visible = _visibleSectionIds;
    if (visible.isEmpty) return;
    _hubKeyFor(visible.first).currentState?.requestFocusFromMemory();
  }

  bool _handleVerticalNavigation(String fromId, bool isUp) {
    final visible = _visibleSectionIds;
    final index = visible.indexOf(fromId);
    if (index < 0) return false;
    final target = index + (isUp ? -1 : 1);
    if (target < 0 || target >= visible.length) {
      // Consume at the edges so focus can't escape the rail stack.
      return true;
    }
    _hubKeyFor(visible[target]).currentState?.requestFocusFromMemory();
    return true;
  }

  void _navigateToSidebar() {
    MainScreenFocusScope.of(context, listen: false)?.focusSidebar();
  }

  void _onFocusedItemChanged(SeerrDiscoverResult item) {
    _spotlightDebouncer.run(() {
      if (mounted) _spotlightItem.value = item;
    });
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SeerrProvider>();

    if (!provider.isSignedIn) {
      return _buildSignedOutState(provider);
    }

    final isTv = PlatformDetector.isTV();
    if (isTv) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildTvSpotlight()),
          _buildRailList(topFraction: 0.42),
        ],
      );
    }
    return _buildRailList(topFraction: 0);
  }

  Widget _buildSignedOutState(SeerrProvider provider) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(Symbols.travel_explore_rounded, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Discover with Seerr', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              provider.isConfigured
                  ? 'Sign in to your Seerr server to browse trending titles and request new content.'
                  : 'Connect a Seerr server to browse trending titles and request new content.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FocusableButton(
              autofocus: PlatformDetector.isTV(),
              onPressed: _openSeerrSettings,
              onNavigateLeft: _navigateToSidebar,
              child: FilledButton.icon(
                onPressed: _openSeerrSettings,
                icon: const Icon(Symbols.settings_rounded),
                label: const Text('Open Seerr settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSeerrSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SeerrSettingsScreen()));
  }

  Widget _buildRailList({required double topFraction}) {
    final visible = _visibleSectionIds;

    if (visible.isEmpty) {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_error != null) {
        final theme = Theme.of(context);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                FocusableButton(
                  autofocus: PlatformDetector.isTV(),
                  onPressed: _load,
                  onNavigateLeft: _navigateToSidebar,
                  child: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Symbols.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final topPadding = constraints.maxHeight * topFraction;
        return CustomScrollView(
          slivers: [
            SliverPadding(padding: EdgeInsets.only(top: topPadding == 0 ? 12 : topPadding)),
            for (final section in _sections)
              if (section.items.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SeerrHubSection(
                      key: _hubKeyFor(section.id),
                      hubId: section.id,
                      title: section.title,
                      icon: section.icon,
                      items: section.items,
                      onItemSelected: (item) => openSeerrResult(context, item),
                      onFocusedItemChanged: _onFocusedItemChanged,
                      onVerticalNavigation: (isUp) => _handleVerticalNavigation(section.id, isUp),
                      onNavigateToSidebar: _navigateToSidebar,
                      onBack: _navigateToSidebar,
                    ),
                  ),
                ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        );
      },
    );
  }

  /// Full-bleed spotlight backdrop driven by the focused card (TV layout).
  Widget _buildTvSpotlight() {
    final t = tokens(context);
    return ValueListenableBuilder<SeerrDiscoverResult?>(
      valueListenable: _spotlightItem,
      builder: (context, item, _) {
        final backdropUrl = item == null
            ? null
            : (tmdbBackdropUrl(item.backdropPath, size: 'w1280') ?? tmdbPosterUrl(item.posterPath, size: 'original'));
        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: DevicePerformance.reducedDuration(const Duration(milliseconds: 280)),
              child: backdropUrl == null
                  ? const ColoredBox(key: ValueKey('seerr-spotlight-empty'), color: Colors.transparent)
                  : CachedNetworkImage(
                      key: ValueKey(backdropUrl),
                      imageUrl: backdropUrl,
                      cacheManager: PlexImageCacheManager.instance,
                      fit: BoxFit.cover,
                      fadeInDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
                      fadeOutDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
                      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                    ),
            ),
            // Scrims keep rails and the info block readable over the artwork.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, t.scrimStrong],
                    stops: const [0.30, 0.85],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [t.scrimSoft, Colors.transparent],
                      stops: const [0.0, 0.55],
                    ),
                  ),
                ),
              ),
            ),
            if (item != null) _buildSpotlightInfo(item),
          ],
        );
      },
    );
  }

  Widget _buildSpotlightInfo(SeerrDiscoverResult item) {
    final theme = Theme.of(context);
    final year = seerrYearFromDate(item.displayDate);
    final rating = item.voteAverage;
    final metadata = <String>[
      item.type == SeerrMediaType.tv ? 'TV Series' : 'Movie',
      if (year != null) '$year',
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}',
    ];

    return Positioned(
      left: 48,
      top: 48,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                metadata.join('  •  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
              ),
              if (item.overview != null && item.overview!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  item.overview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85), height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
