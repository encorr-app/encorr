import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:rate_limiter/rate_limiter.dart';

import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../mixins/controller_disposer_mixin.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../mixins/refreshable.dart';
import '../providers/multi_server_provider.dart';
import '../providers/seerr_provider.dart';
import '../services/image_cache_service.dart';
import '../services/seerr/seerr_models.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/focusable_list_tile.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/pill_input_decoration.dart';
import '../widgets/focusable_media_card.dart';
import '../utils/focus_utils.dart';
import 'libraries/state_messages.dart';
import 'main_screen.dart';
import 'seerr/seerr_widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with
        Refreshable,
        FullRefreshable,
        SearchInputFocusable,
        FocusableTab,
        ControllerDisposerMixin,
        MountedSetStateMixin {
  late final _searchController = createTextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'SearchInput');
  final _firstResultFocusNode = FocusNode(debugLabel: 'SearchFirstResult');
  List<MediaItem> _searchResults = [];
  List<SeerrDiscoverResult> _seerrResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  late final Debounce _searchDebounce;
  String _lastSearchedQuery = '';
  String? _focusResultsForQuery;

  @override
  void initState() {
    super.initState();
    _searchDebounce = debounce(_performSearch, const Duration(milliseconds: 500));
    _searchController.addListener(_onSearchChanged);
    FocusUtils.requestFocusAfterBuild(this, _searchFocusNode);
  }

  @override
  void dispose() {
    _searchDebounce.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchFocusNode.dispose();
    _firstResultFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;

    final query = _searchController.text;

    if (query.trim().isEmpty) {
      _searchDebounce.cancel();
      _focusResultsForQuery = null;
      setStateIfMounted(() {
        _searchResults = [];
        _seerrResults = [];
        _hasSearched = false;
        _isSearching = false;
        _lastSearchedQuery = '';
      });
      return;
    }

    // Only search if the query has actually changed
    if (query.trim() == _lastSearchedQuery.trim()) {
      return;
    }

    _searchDebounce([query]);
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    if (query.trim().isEmpty) {
      setStateIfMounted(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setStateIfMounted(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      if (!mounted) return;
      final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);

      if (!multiServerProvider.hasConnectedServers) {
        throw Exception('No servers available');
      }

      // Kick off the Seerr search in parallel with the library search.
      final seerrProvider = Provider.of<SeerrProvider?>(context, listen: false);
      final seerrFuture = (seerrProvider?.isSignedIn ?? false) ? seerrProvider!.search(query) : null;

      final neutral = await multiServerProvider.aggregationService.searchAcrossServers(query);

      var seerrResults = <SeerrDiscoverResult>[];
      if (seerrFuture != null) {
        try {
          final page = await seerrFuture;
          seerrResults = _filterSeerrResults(page.results, neutral);
          seerrProvider!.primeStatusCache(seerrResults);
        } catch (e) {
          appLogger.w('Seerr: search failed', error: e);
        }
      }

      if (mounted) {
        setStateIfMounted(() {
          _searchResults = neutral;
          _seerrResults = seerrResults;
          _isSearching = false;
          _lastSearchedQuery = query.trim();
        });
        _maybeFocusResultsAfterSubmit(query, neutral);
      }
    } catch (e) {
      _focusResultsForQuery = null;
      if (mounted) {
        setStateIfMounted(() {
          _isSearching = false;
        });
        showErrorSnackBar(context, t.errors.searchFailed(error: e));
      }
    }
  }

  /// Drop Seerr rows that duplicate a library result (title + year match) —
  /// those are already playable from the list above.
  List<SeerrDiscoverResult> _filterSeerrResults(List<SeerrDiscoverResult> seerr, List<MediaItem> library) {
    final libraryKeys = <String>{
      for (final item in library) '${item.displayTitle.trim().toLowerCase()}|${item.year ?? ''}',
    };
    return seerr.where((result) {
      if (result.type == null || result.displayTitle.isEmpty) return false;
      final year = seerrYearFromDate(result.displayDate);
      return !libraryKeys.contains('${result.displayTitle.trim().toLowerCase()}|${year ?? ''}');
    }).toList();
  }

  /// OSK "Search" / hardware Enter on TV: jump to results, or force the
  /// search to run now and focus results when it lands.
  void _handleSearchSubmit() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (_searchResults.isNotEmpty && !_isSearching && query == _lastSearchedQuery.trim()) {
      _firstResultFocusNode.requestFocus();
      return;
    }

    _focusResultsForQuery = query;
    if (_searchDebounce.isPending || !_isSearching) {
      _searchDebounce.cancel();
      _performSearch(query);
    }
    // else: the in-flight search already covers the current text; its
    // completion focuses the results.
  }

  void _maybeFocusResultsAfterSubmit(String query, List<MediaItem> results) {
    if (_focusResultsForQuery == null || _focusResultsForQuery != query.trim()) return;
    _focusResultsForQuery = null;
    if (results.isEmpty) return;
    if (_searchController.text.trim() != query.trim()) return; // user kept editing
    FocusUtils.requestFocusAfterBuild(this, _firstResultFocusNode);
  }

  @override
  void refresh() {
    if (!mounted) return;
    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  /// Focus the search input field
  @override
  void focusSearchInput() {
    if (!mounted) return;
    _searchFocusNode.requestFocus();
  }

  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    _searchFocusNode.requestFocus();
  }

  /// Set the search query externally (e.g. from companion remote)
  @override
  void setSearchQuery(String query) {
    if (!mounted) return;
    _searchController.text = query;
  }

  // Public method to fully reload all content (for profile switches)
  @override
  void fullRefresh() {
    if (!mounted) return;
    appLogger.d('SearchScreen.fullRefresh() called - clearing search and reloading');
    // Clear search results and search text for new profile
    _searchController.clear();
    _focusResultsForQuery = null;
    setStateIfMounted(() {
      _searchResults.clear();
      _seerrResults = [];
      _isSearching = false;
      _hasSearched = false;
      _lastSearchedQuery = '';
    });
  }

  void updateItem(String _) {
    if (!mounted) return;
    // Trigger a refresh of the search to get updated metadata
    if (_searchController.text.isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  /// Navigate focus to the sidebar
  void _navigateToSidebar() {
    MainScreenFocusScope.of(context, listen: false)?.focusSidebar();
  }

  Widget _buildResultsList(BuildContext context) {
    final multiServer = context.watch<MultiServerProvider>();
    final showServerName = multiServer.totalServerCount > 1;
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = _searchResults[index];
          return FocusableMediaCard(
            key: Key(item.globalKey),
            item: item,
            forceListMode: true,
            disableScale: true,
            focusNode: index == 0 ? _firstResultFocusNode : null,
            onRefresh: updateItem,
            onListRefresh: () => updateItem(item.id),
            onNavigateLeft: _navigateToSidebar,
            onNavigateUp: index == 0 ? focusSearchInput : null,
            showServerName: showServerName,
          );
        }, childCount: _searchResults.length),
      ),
    );
  }

  /// "Request on Seerr" section below the library results: titles found on
  /// the Seerr server that aren't already in the user's libraries.
  List<Widget> _buildSeerrSectionSlivers(BuildContext context) {
    if (_seerrResults.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              AppIcon(Symbols.travel_explore_rounded, fill: 1, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Request on Seerr',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final result = _seerrResults[index];
            return _buildSeerrResultTile(context, result);
          }, childCount: _seerrResults.length),
        ),
      ),
    ];
  }

  Widget _buildSeerrResultTile(BuildContext context, SeerrDiscoverResult result) {
    final theme = Theme.of(context);
    final year = seerrYearFromDate(result.displayDate);
    final type = result.type;
    final status = type == null
        ? result.status
        : (context.watch<SeerrProvider?>()?.cachedStatus(result.id, type) ?? result.status);
    final posterUrl = tmdbPosterUrl(result.posterPath, size: 'w92');
    final subtitleParts = [
      type == SeerrMediaType.tv ? 'TV Series' : 'Movie',
      if (year != null) '$year',
    ];

    return FocusableListTile(
      title: Text(result.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitleParts.join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 34,
          height: 51,
          child: posterUrl == null
              ? ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: AppIcon(
                    type == SeerrMediaType.tv ? Symbols.tv_rounded : Symbols.movie_rounded,
                    fill: 1,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: posterUrl,
                  cacheManager: PlexImageCacheManager.instance,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                ),
        ),
      ),
      trailing: status == SeerrMediaStatus.unknown || status == SeerrMediaStatus.deleted
          ? const AppIcon(Symbols.add_circle_rounded, fill: 1, size: 22)
          : SeerrStatusBadge(status: status, compact: false),
      onTap: () => openSeerrResult(context, result),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          primary: false,
          slivers: [
            DesktopSliverAppBar(title: Text(t.common.search), floating: true),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: FocusableTextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onNavigateLeft: _navigateToSidebar,
                  onNavigateDown: _searchResults.isNotEmpty && !_isSearching
                      ? _firstResultFocusNode.requestFocus
                      : null,
                  onEditingComplete: PlatformDetector.isTV() ? _handleSearchSubmit : null,
                  onBack: () {
                    if (_searchController.text.isNotEmpty) {
                      _searchController.clear();
                    } else {
                      _navigateToSidebar();
                    }
                  },
                  decoration: pillInputDecoration(
                    context,
                    hintText: t.search.hint,
                    prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const AppIcon(Symbols.clear_rounded, fill: 1),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            if (_isSearching)
              LoadingIndicatorBox.sliver
            else if (!_hasSearched)
              SliverFillRemaining(
                child: StateMessageWidget(
                  message: t.search.searchYourMedia,
                  subtitle: t.search.enterTitleActorOrKeyword,
                  icon: Symbols.search_rounded,
                  iconSize: 80,
                ),
              )
            else if (_searchResults.isEmpty && _seerrResults.isEmpty)
              SliverFillRemaining(
                child: StateMessageWidget(
                  message: t.messages.noResultsFound,
                  subtitle: t.search.tryDifferentTerm,
                  icon: Symbols.search_off_rounded,
                  iconSize: 80,
                ),
              )
            else ...[
              if (_searchResults.isNotEmpty) _buildResultsList(context),
              ..._buildSeerrSectionSlivers(context),
            ],
          ],
        ),
      ),
    );
  }
}
