import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_button.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../providers/seerr_provider.dart';
import '../../services/device_performance.dart';
import '../../services/image_cache_service.dart';
import '../../services/seerr/seerr_models.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/app_logger.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/dialog_action_button.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/glass/glass_panel.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/detail_trailer_focus.dart';
import '../../widgets/inline_trailer_player.dart';
import 'seerr_widgets.dart';

/// Detail page for a Seerr (TMDB) item that is not in the user's Plex
/// library: full-bleed backdrop, glass info panel, and a Request button.
class SeerrMediaDetailScreen extends StatefulWidget {
  final int tmdbId;
  final SeerrMediaType mediaType;

  /// Discover/search row that opened this screen — used for an instant
  /// backdrop and title while the detail request is in flight.
  final SeerrDiscoverResult? initial;

  const SeerrMediaDetailScreen({super.key, required this.tmdbId, required this.mediaType, this.initial});

  @override
  State<SeerrMediaDetailScreen> createState() => _SeerrMediaDetailScreenState();
}

class _SeerrMediaDetailScreenState extends State<SeerrMediaDetailScreen> with MountedSetStateMixin {
  SeerrMovieDetails? _movie;
  SeerrTvDetails? _tv;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  final InlineTrailerPlayerController _trailerController = InlineTrailerPlayerController();
  final DetailTrailerFocusController _detailTrailerFocusController = DetailTrailerFocusController();
  final FocusNode _requestButtonFocusNode = FocusNode(debugLabel: 'seerr_request');

  @override
  void dispose() {
    _trailerController.dispose();
    _detailTrailerFocusController.dispose();
    _requestButtonFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final provider = context.read<SeerrProvider>();
    try {
      if (widget.mediaType == SeerrMediaType.movie) {
        final movie = await provider.getMovie(widget.tmdbId);
        setStateIfMounted(() {
          _movie = movie;
          _loading = false;
        });
      } else {
        final tv = await provider.getTv(widget.tmdbId);
        setStateIfMounted(() {
          _tv = tv;
          _loading = false;
        });
      }
    } catch (e) {
      appLogger.w('Seerr: failed to load details for tmdb ${widget.tmdbId}', error: e);
      setStateIfMounted(() {
        _loading = false;
        _loadError = 'Could not load details from Seerr.';
      });
    }
  }

  // ─── Derived fields ─────────────────────────────────────────────────────

  String get _title => _movie?.title ?? _tv?.name ?? widget.initial?.displayTitle ?? '';

  String? get _overview => _movie?.overview ?? _tv?.overview ?? widget.initial?.overview;

  String? get _backdropPath => _movie?.backdropPath ?? _tv?.backdropPath ?? widget.initial?.backdropPath;

  String? get _posterPath => _movie?.posterPath ?? _tv?.posterPath ?? widget.initial?.posterPath;

  int? get _year =>
      seerrYearFromDate(_movie?.releaseDate ?? _tv?.firstAirDate ?? widget.initial?.displayDate);

  SeerrMediaInfo? get _mediaInfo => _movie?.mediaInfo ?? _tv?.mediaInfo ?? widget.initial?.mediaInfo;

  SeerrMediaStatus _statusOf(SeerrProvider provider) =>
      provider.cachedStatus(widget.tmdbId, widget.mediaType) ??
      _movie?.status ??
      _tv?.status ??
      widget.initial?.status ??
      SeerrMediaStatus.unknown;

  // ─── Request flow ───────────────────────────────────────────────────────

  bool _canRequest(SeerrMediaStatus status) {
    if (_loading || _submitting) return false;
    return switch (status) {
      SeerrMediaStatus.available || SeerrMediaStatus.pending || SeerrMediaStatus.processing => false,
      // For TV, partially available still allows requesting the remaining seasons.
      SeerrMediaStatus.partiallyAvailable => widget.mediaType == SeerrMediaType.tv,
      SeerrMediaStatus.unknown || SeerrMediaStatus.deleted => true,
    };
  }

  String _requestLabel(SeerrMediaStatus status) {
    if (_submitting) return 'Requesting…';
    return switch (status) {
      SeerrMediaStatus.available => 'Available',
      SeerrMediaStatus.pending => 'Pending approval',
      SeerrMediaStatus.processing => 'Processing',
      SeerrMediaStatus.partiallyAvailable =>
        widget.mediaType == SeerrMediaType.tv ? 'Request more seasons' : 'Available',
      SeerrMediaStatus.unknown || SeerrMediaStatus.deleted => 'Request',
    };
  }

  Future<void> _onRequestPressed() async {
    List<int>? seasons;
    if (widget.mediaType == SeerrMediaType.tv) {
      final choice = await _pickSeasons();
      if (choice == null) return;
      seasons = choice.allSeasons ? null : choice.seasons;
      if (seasons != null && seasons.isEmpty) return;
    }
    if (!mounted) return;

    setState(() => _submitting = true);
    try {
      await context.read<SeerrProvider>().submitRequest(widget.tmdbId, widget.mediaType, seasons: seasons);
      if (mounted) showSuccessSnackBar(context, 'Request submitted');
    } catch (e) {
      appLogger.w('Seerr: request failed for tmdb ${widget.tmdbId}', error: e);
      if (mounted) showErrorSnackBar(context, 'Request failed');
    } finally {
      setStateIfMounted(() => _submitting = false);
    }
  }

  Future<_SeasonRequestChoice?> _pickSeasons() async {
    final seasons = _tv?.requestableSeasons ?? const <SeerrSeason>[];
    if (seasons.isEmpty) {
      // No season list available — request everything.
      return const _SeasonRequestChoice(allSeasons: true, seasons: []);
    }

    // Seasons Seerr already knows about (requested/processing/available)
    // can't be requested again.
    final unavailable = <int>{};
    for (final info in _mediaInfo?.seasons ?? const <SeerrMediaSeasonInfo>[]) {
      final number = info.seasonNumber;
      if (number == null) continue;
      if (info.status != SeerrMediaStatus.unknown && info.status != SeerrMediaStatus.deleted) {
        unavailable.add(number);
      }
    }

    return showDialog<_SeasonRequestChoice>(
      context: context,
      builder: (context) => _SeasonPickerDialog(seasons: seasons, unavailableSeasons: unavailable),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final provider = context.watch<SeerrProvider>();
    final status = _statusOf(provider);
    final isTv = PlatformDetector.isTV();

    final backdrop = _buildTrailerBackdrop(t);
    final details = SafeArea(
      child: Padding(
        padding: EdgeInsets.all(isTv ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isTv) _buildBackButton(),
            if (isTv) const Spacer(),
            Align(alignment: isTv ? Alignment.bottomLeft : Alignment.topLeft, child: _buildInfoPanel(status)),
            if (!isTv) const Spacer(),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DetailTrailerFocusLayout(
            controller: _detailTrailerFocusController,
            trailerController: _trailerController,
            tmdbId: widget.tmdbId,
            mediaType: widget.mediaType,
            trailerEnabled: provider.isSignedIn,
            backdrop: backdrop,
            isTv: isTv,
            details: isTv ? Stack(fit: StackFit.expand, children: [_buildScrims(t), details]) : details,
          ),
          if (isTv)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _buildBackButton(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrailerBackdrop(MonoTokens t) {
    final backdropUrl = tmdbBackdropUrl(_backdropPath) ?? tmdbPosterUrl(_posterPath, size: 'original');
    final Widget backdrop = backdropUrl == null
        ? const ColoredBox(color: Color(0xFF101010))
        : CachedNetworkImage(
            imageUrl: backdropUrl,
            cacheManager: PlexImageCacheManager.instance,
            fit: BoxFit.cover,
            fadeInDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 300)),
            fadeOutDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 300)),
            placeholder: (context, url) => const ColoredBox(color: Color(0xFF101010)),
            errorBuilder: (context, error, stackTrace) => const ColoredBox(color: Color(0xFF101010)),
          );
    return backdrop;
  }

  Widget _buildScrims(MonoTokens t) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.scrimSoft, Colors.transparent, t.scrimStrong],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [t.scrimStrong, Colors.transparent],
              stops: const [0.0, 0.65],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return FocusableButton(
      onPressed: () => Navigator.of(context).maybePop(),
      onBack: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
        child: const Center(child: AppIcon(Symbols.arrow_back_rounded, size: 24, color: Colors.white)),
      ),
    );
  }

  Widget _buildInfoPanel(SeerrMediaStatus status) {
    final theme = Theme.of(context);
    final rating = widget.initial?.voteAverage;
    final overview = _overview;

    final metadata = <String>[
      widget.mediaType == SeerrMediaType.movie ? 'Movie' : 'TV Series',
      if (_year != null) '$_year',
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}',
      if (_movie?.runtime != null && _movie!.runtime! > 0) '${_movie!.runtime} min',
      if (_tv?.numberOfSeasons != null && _tv!.numberOfSeasons! > 0)
        '${_tv!.numberOfSeasons} season${_tv!.numberOfSeasons == 1 ? '' : 's'}',
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    metadata.join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ),
                if (status != SeerrMediaStatus.unknown && status != SeerrMediaStatus.deleted) ...[
                  const SizedBox(width: 12),
                  SeerrStatusBadge(status: status, compact: false),
                ],
              ],
            ),
            if (_loadError != null) ...[
              const SizedBox(height: 12),
              Text(_loadError!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
            ],
            if (overview != null && overview.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                overview,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, height: 1.45),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                _buildRequestButton(status),
                if (_loading) ...[
                  const SizedBox(width: 16),
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestButton(SeerrMediaStatus status) {
    final enabled = _canRequest(status);
    final label = _requestLabel(status);
    final icon = enabled
        ? Symbols.add_rounded
        : (_submitting ? Symbols.hourglass_top_rounded : seerrStatusIcon(status));

    return FocusableButton(
      autofocus: true,
      focusNode: _requestButtonFocusNode,
      onPressed: enabled ? _onRequestPressed : null,
      onNavigateUp: () {
        _detailTrailerFocusController.engageFromDetails();
        _trailerController.setUserEngaged(_detailTrailerFocusController.isEngaged);
      },
      onBack: () => Navigator.of(context).maybePop(),
      child: FilledButton.icon(
        onPressed: enabled ? _onRequestPressed : null,
        icon: AppIcon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _SeasonRequestChoice {
  final bool allSeasons;
  final List<int> seasons;

  const _SeasonRequestChoice({required this.allSeasons, required this.seasons});
}

/// Season multi-select for TV requests: "All seasons" or any combination of
/// individual seasons. Seasons Seerr already has (requested/available) are
/// shown disabled. D-pad friendly via [FocusableListTile].
class _SeasonPickerDialog extends StatefulWidget {
  final List<SeerrSeason> seasons;
  final Set<int> unavailableSeasons;

  const _SeasonPickerDialog({required this.seasons, required this.unavailableSeasons});

  @override
  State<_SeasonPickerDialog> createState() => _SeasonPickerDialogState();
}

class _SeasonPickerDialogState extends State<_SeasonPickerDialog> {
  final Set<int> _selected = {};
  bool _allSeasons = false;

  @override
  void initState() {
    super.initState();
    // Default to everything selected so the primary action is one click.
    _allSeasons = true;
    _selected.addAll(_selectableSeasonNumbers);
  }

  List<int> get _selectableSeasonNumbers => [
    for (final season in widget.seasons)
      if (season.seasonNumber != null && !widget.unavailableSeasons.contains(season.seasonNumber))
        season.seasonNumber!,
  ];

  void _toggleAll() {
    setState(() {
      _allSeasons = !_allSeasons;
      _selected.clear();
      if (_allSeasons) _selected.addAll(_selectableSeasonNumbers);
    });
  }

  void _toggleSeason(int seasonNumber) {
    setState(() {
      if (!_selected.remove(seasonNumber)) _selected.add(seasonNumber);
      _allSeasons = _selected.length == _selectableSeasonNumbers.length && _selected.isNotEmpty;
    });
  }

  Widget _checkIcon(bool checked, {bool enabled = true}) {
    final theme = Theme.of(context);
    return AppIcon(
      checked ? Symbols.check_box_rounded : Symbols.check_box_outline_blank_rounded,
      size: 22,
      color: enabled
          ? (checked ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant)
          : theme.disabledColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _allSeasons || _selected.isNotEmpty;

    return AlertDialog(
      title: const Text('Request seasons'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            FocusableListTile(
              autofocus: true,
              title: const Text('All seasons'),
              trailing: _checkIcon(_allSeasons),
              onTap: _toggleAll,
            ),
            const Divider(height: 8),
            for (final season in widget.seasons)
              if (season.seasonNumber != null)
                _buildSeasonTile(season, widget.unavailableSeasons.contains(season.seasonNumber)),
          ],
        ),
      ),
      actions: [
        DialogActionButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        DialogActionButton(
          label: 'Request',
          isPrimary: true,
          onPressed: hasSelection
              ? () => Navigator.of(context).pop(
                  _SeasonRequestChoice(allSeasons: _allSeasons, seasons: _selected.toList()..sort()),
                )
              : () {},
        ),
      ],
    );
  }

  Widget _buildSeasonTile(SeerrSeason season, bool unavailable) {
    final number = season.seasonNumber!;
    final episodes = season.episodeCount;
    final subtitleParts = <String>[
      if (episodes != null && episodes > 0) '$episodes episode${episodes == 1 ? '' : 's'}',
      if (unavailable) 'Already requested or available',
    ];

    return FocusableListTile(
      enabled: !unavailable,
      title: Text(season.name ?? 'Season $number'),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' • ')),
      trailing: _checkIcon(unavailable || _selected.contains(number), enabled: !unavailable),
      onTap: unavailable ? null : () => _toggleSeason(number),
    );
  }
}
