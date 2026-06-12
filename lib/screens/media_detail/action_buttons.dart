part of '../media_detail_screen.dart';

extension _MediaDetailActionButtons on _MediaDetailScreenState {
  Widget _buildActionButtons(MediaItem metadata) {
    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final actionSize = isTv ? _tvDetailActionSize * tvScale : 48.0;
    final playButtonLabel = _getPlayButtonLabel(metadata);
    final playIconSize = isTv ? 22 * tvScale : 20.0;
    final playTextStyle = TextStyle(fontSize: isTv ? 17 * tvScale : 16, fontWeight: .w700);
    final playButtonIcon = AppIcon(_getPlayButtonIcon(metadata), fill: 1, size: playIconSize);

    Future<void> onPlayPressed() async {
      // For TV shows, play the OnDeck episode if available
      // Otherwise, play the first episode of the first season
      if (metadata.isShow) {
        if (_onDeckEpisode != null) {
          appLogger.d('Playing on deck episode: ${_onDeckEpisode!.title}');
          await navigateToVideoPlayerWithRefresh(
            context,
            metadata: _onDeckEpisode!,
            isOffline: widget.isOffline,
            onRefresh: _loadFullMetadata,
          );
        } else {
          // No on deck episode, fetch first episode of first season
          await _playFirstEpisode();
        }
      } else if (metadata.isSeason) {
        // For seasons, play the first episode
        if (_episodes.isNotEmpty) {
          await navigateToVideoPlayerWithRefresh(
            context,
            metadata: _episodes.first,
            isOffline: widget.isOffline,
            onRefresh: _loadFullMetadata,
          );
        } else {
          await _playFirstEpisode();
        }
      } else {
        appLogger.d('Playing: ${metadata.title}');
        // For movies or episodes, play directly
        await navigateToVideoPlayerWithRefresh(
          context,
          metadata: metadata,
          isOffline: widget.isOffline,
          onRefresh: _loadFullMetadata,
        );
      }
    }

    final primaryTrailer = _getPrimaryTrailer();

    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);
    final colorScheme = Theme.of(context).colorScheme;

    // In keyboard/d-pad mode, focused buttons get a prominent style.
    // overlayColor is set to transparent to prevent the Material focus
    // overlay from dimming the background color we set.
    final focusBg = colorScheme.inverseSurface;
    final focusFg = colorScheme.onInverseSurface;
    final tonalBg = colorScheme.secondaryContainer;
    final idleBg = isTv ? tonalBg.withValues(alpha: 0.38) : tonalBg;
    final tonalFg = colorScheme.onSecondaryContainer;
    final noOverlay = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return Colors.transparent;
      return null; // default for other states
    });

    ButtonStyle actionButtonStyle({Color? foregroundColor, EdgeInsetsGeometry? padding, bool showFocus = false}) {
      if (!isKeyboardMode && !isTv) {
        if (padding != null) {
          return FilledButton.styleFrom(padding: padding);
        }
        return IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          maximumSize: const Size(48, 48),
          foregroundColor: foregroundColor,
        );
      }

      return ButtonStyle(
        padding: padding != null ? WidgetStatePropertyAll(padding) : null,
        minimumSize: WidgetStatePropertyAll(padding == null ? Size.square(actionSize) : Size(0, actionSize)),
        maximumSize: padding == null ? WidgetStatePropertyAll(Size.square(actionSize)) : null,
        fixedSize: padding == null ? WidgetStatePropertyAll(Size.square(actionSize)) : null,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        overlayColor: noOverlay,
        backgroundColor: WidgetStatePropertyAll(showFocus ? focusBg : idleBg),
        foregroundColor: WidgetStatePropertyAll(showFocus ? focusFg : foregroundColor ?? tonalFg),
      );
    }

    // Plays the resolved trailer. Shared by the row's trailer button and the
    // ⋮ menu item so the trailer stays reachable when the row hides its button.
    final VoidCallback? onPlayTrailer = primaryTrailer == null
        ? null
        : () => unawaited(navigateToVideoPlayer(context, metadata: primaryTrailer));

    final gap = isTv ? 8.0 * tvScale : 12.0;

    Widget playButton(FocusableActionBuildState state) {
      return SizedBox(
        height: actionSize,
        child: FilledButton(
          onPressed: onPlayPressed,
          style: actionButtonStyle(
            showFocus: state.showFocus,
            padding: .symmetric(horizontal: isTv ? 17 * tvScale : 16, vertical: isTv ? 9 * tvScale : 0),
          ),
          child: playButtonLabel.isNotEmpty
              ? Row(
                  mainAxisSize: .min,
                  children: [
                    playButtonIcon,
                    SizedBox(width: isTv ? 7 * tvScale : 8),
                    Text(playButtonLabel, style: playTextStyle),
                  ],
                )
              : playButtonIcon,
        ),
      );
    }

    Widget iconActionButton(
      FocusableActionBuildState state, {
      required Widget icon,
      required VoidCallback? onPressed,
      String? tooltip,
      Color? foregroundColor,
    }) {
      return IconButton.filledTonal(
        onPressed: onPressed,
        icon: icon,
        tooltip: tooltip,
        iconSize: isTv ? 21 * tvScale : 20,
        style: actionButtonStyle(foregroundColor: foregroundColor, showFocus: state.showFocus),
      );
    }

    final playAction = FocusableAction(
      debugLabel: 'detail_play',
      focusNode: _playButtonFocusNode,
      autofocus: isKeyboardMode,
      onPressed: onPlayPressed,
      builder: (context, state) => playButton(state),
    );

    final trailerAction = primaryTrailer == null
        ? null
        : FocusableAction(
            debugLabel: 'detail_trailer',
            onPressed: onPlayTrailer,
            builder: (context, state) => iconActionButton(
              state,
              onPressed: onPlayTrailer,
              icon: const AppIcon(Symbols.theaters_rounded, fill: 1),
              tooltip: t.tooltips.playTrailer,
            ),
          );

    final shuffleAction = (metadata.isShow || metadata.isSeason)
        ? FocusableAction(
            debugLabel: 'detail_shuffle',
            onPressed: () async {
              await _handleShufflePlayWithQueue(context, metadata);
            },
            builder: (context, state) => iconActionButton(
              state,
              onPressed: () async {
                await _handleShufflePlayWithQueue(context, metadata);
              },
              icon: const AppIcon(Symbols.shuffle_rounded, fill: 1),
              tooltip: t.tooltips.shufflePlay,
            ),
          )
        : null;

    final downloadAction = !widget.isOffline && !PlatformDetector.isAppleTV()
        ? FocusableAction(
            debugLabel: 'detail_download',
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            builder: (context, state) =>
                _buildDownloadButton(metadata, actionButtonStyle, tvScale, showFocus: state.showFocus),
          )
        : null;

    final watchedAction = FocusableAction(
      debugLabel: 'detail_watched',
      onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
      builder: (context, state) =>
          _buildWatchedToggleButton(metadata, actionButtonStyle, tvScale, showFocus: state.showFocus),
    );

    // Seerr request button (Plezy-Seerr fork): shown when signed in to Seerr
    // and the item maps to a TMDB id. Disabled states mirror the Seerr
    // availability status; otherwise it submits a request (movies confirm,
    // shows pick seasons).
    final seerr = widget.isOffline ? null : context.watch<SeerrProvider?>();
    final seerrRef = _seerrRef;
    FocusableAction? seerrAction;
    if (seerr != null && seerr.isSignedIn && seerrRef != null) {
      final status = seerr.cachedStatus(seerrRef.tmdbId, seerrRef.mediaType) ?? SeerrMediaStatus.unknown;
      final isSeerrMovie = seerrRef.mediaType == SeerrMediaType.movie;
      final isAvailable =
          status == SeerrMediaStatus.available || (isSeerrMovie && status == SeerrMediaStatus.partiallyAvailable);
      final isInProgress = status == SeerrMediaStatus.pending || status == SeerrMediaStatus.processing;
      final requestEnabled = !isAvailable && !isInProgress && !_seerrRequestInFlight;

      Widget buildSeerrButton(FocusableActionBuildState state) {
        if (_seerrRequestInFlight) {
          return IconButton.filledTonal(
            onPressed: null,
            icon: LoadingIndicatorBox(size: isTv ? 21 * tvScale : 20),
            iconSize: isTv ? 21 * tvScale : 20,
            style: actionButtonStyle(showFocus: state.showFocus),
          );
        }
        if (isAvailable) {
          return iconActionButton(
            state,
            onPressed: null,
            icon: const AppIcon(Symbols.check_circle_rounded, fill: 1),
            tooltip: 'Available',
            foregroundColor: Colors.teal,
          );
        }
        if (isInProgress) {
          final processing = status == SeerrMediaStatus.processing;
          return iconActionButton(
            state,
            onPressed: null,
            icon: AppIcon(processing ? Symbols.autorenew_rounded : Symbols.hourglass_top_rounded, fill: 1),
            tooltip: processing ? 'Processing' : 'Requested',
            foregroundColor: Colors.amber,
          );
        }
        return iconActionButton(
          state,
          onPressed: () => unawaited(_handleSeerrRequestPressed(metadata)),
          icon: const AppIcon(Symbols.add_to_queue_rounded, fill: 1),
          tooltip: !isSeerrMovie && status == SeerrMediaStatus.partiallyAvailable ? 'Request more seasons' : 'Request',
        );
      }

      seerrAction = FocusableAction(
        debugLabel: 'detail_seerr_request',
        onPressed: requestEnabled ? () => unawaited(_handleSeerrRequestPressed(metadata)) : null,
        builder: (context, state) => buildSeerrButton(state),
      );
    }

    // Trailer affordances (Plezy-Seerr fork): only while a background
    // trailer is actually playing on this page.
    final trailerAudioAction = _trailerController.isActive && _trailerController.canUnmute
        ? FocusableAction(
            debugLabel: 'detail_trailer_mute',
            onPressed: () => unawaited(_trailerController.toggleMute()),
            builder: (context, state) => iconActionButton(
              state,
              onPressed: () => unawaited(_trailerController.toggleMute()),
              icon: AppIcon(
                _trailerController.isMuted ? Symbols.volume_off_rounded : Symbols.volume_up_rounded,
                fill: 1,
              ),
              tooltip: _trailerController.isMuted ? 'Unmute trailer' : 'Mute trailer',
            ),
          )
        : null;

    final trailerReplayAction = _trailerController.isActive
        ? FocusableAction(
            debugLabel: 'detail_trailer_replay',
            onPressed: () => unawaited(_trailerController.replay()),
            builder: (context, state) => iconActionButton(
              state,
              onPressed: () => unawaited(_trailerController.replay()),
              icon: const AppIcon(Symbols.replay_rounded, fill: 1),
              tooltip: 'Replay trailer',
            ),
          )
        : null;

    void showMoreActions() => _contextMenuKey.currentState?.showContextMenu(context);

    final moreActionsAction = widget.isOffline
        ? null
        : FocusableAction(
            debugLabel: 'detail_more',
            onPressed: showMoreActions,
            builder: (context, state) => _buildMoreActionsButton(
              metadata,
              actionButtonStyle,
              tvScale,
              onPlayTrailer: onPlayTrailer,
              showFocus: state.showFocus,
            ),
          );

    final allActions = <FocusableAction>[
      playAction,
      ?trailerAction,
      ?shuffleAction,
      ?downloadAction,
      watchedAction,
      ?seerrAction,
      ?trailerAudioAction,
      ?trailerReplayAction,
      ?moreActionsAction,
    ];

    double playButtonWidthEstimate() {
      if (playButtonLabel.isEmpty) return 64.0;
      final textPainter = TextPainter(
        text: TextSpan(text: playButtonLabel, style: playTextStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      final textWidth = textPainter.width;
      textPainter.dispose();
      final horizontalPadding = isTv ? 34.0 * tvScale : 32.0;
      final iconGap = isTv ? 7.0 * tvScale : 8.0;
      return (horizontalPadding + playIconSize + iconGap + textWidth).clamp(64.0, double.infinity).toDouble();
    }

    final estimatedPlayWidth = playButtonWidthEstimate();
    double estimatedRowWidth(List<FocusableAction> actions) {
      if (actions.isEmpty) return 0;
      return estimatedPlayWidth + (actions.length - 1) * actionSize + (actions.length - 1) * gap;
    }

    List<FocusableAction> compactActionsFor(double maxWidth) {
      if (widget.isOffline) {
        final compact = <FocusableAction>[playAction, watchedAction];
        if (maxWidth.isFinite && estimatedRowWidth(compact) > maxWidth) return [playAction];
        return compact;
      }

      final medium = <FocusableAction>[playAction, ?downloadAction, watchedAction, ?seerrAction, ?moreActionsAction];
      if (!maxWidth.isFinite || estimatedRowWidth(medium) <= maxWidth) return medium;

      final compact = <FocusableAction>[playAction, watchedAction, ?moreActionsAction];
      if (estimatedRowWidth(compact) <= maxWidth) return compact;

      return [playAction, ?moreActionsAction];
    }

    Widget actionBar(List<FocusableAction> actions) {
      return FocusableActionBar(
        actions: actions,
        spacing: gap,
        onFocusChange: isTv ? _setTvDetailActionRowFocus : null,
        onNavigateUp: _focusAboveActionRow,
        onNavigateDown: _focusBelowActionRow,
      );
    }

    // TV screens are wide and D-pad focus should see every direct action.
    // On smaller online screens, hidden actions remain available from ⋮.
    if (isTv) return actionBar(allActions);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || estimatedRowWidth(allActions) <= maxWidth) {
          return actionBar(allActions);
        }
        return actionBar(compactActionsFor(maxWidth));
      },
    );
  }

  /// Submit a Seerr request for this item. Movies get a one-tap confirm;
  /// shows get a season picker (multi-select or all seasons).
  Future<void> _handleSeerrRequestPressed(MediaItem metadata) async {
    final ref = _seerrRef;
    if (ref == null || _seerrRequestInFlight) return;
    final seerr = context.read<SeerrProvider>();
    if (!seerr.isSignedIn) return;

    List<int>? seasons;
    if (ref.mediaType == SeerrMediaType.tv) {
      final selection = await _showSeerrSeasonPicker(ref, seerr, metadata);
      if (selection == null || !mounted) return;
      // Empty selection means "all seasons" (Seerr wire value 'all').
      seasons = selection.isEmpty ? null : selection;
    } else {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Request movie',
        message: 'Request "${metadata.displayTitle}"?',
        confirmText: 'Request',
      );
      if (!confirmed || !mounted) return;
    }

    setStateIfMounted(() => _seerrRequestInFlight = true);
    try {
      await seerr.submitRequest(ref.tmdbId, ref.mediaType, seasons: seasons);
      if (mounted) showSuccessSnackBar(context, 'Request submitted');
    } catch (e) {
      appLogger.w('Seerr: request failed', error: e);
      if (mounted) showErrorSnackBar(context, 'Request failed: $e');
    } finally {
      setStateIfMounted(() => _seerrRequestInFlight = false);
    }
  }

  /// Season multi-select for TV requests. Returns null when cancelled, an
  /// empty list for "all seasons", or the selected season numbers.
  Future<List<int>?> _showSeerrSeasonPicker(SeerrMediaRef ref, SeerrProvider seerr, MediaItem metadata) async {
    SeerrTvDetails tv;
    try {
      tv = await seerr.getTv(ref.tmdbId);
    } catch (e) {
      appLogger.w('Seerr: season list fetch failed', error: e);
      if (mounted) showErrorSnackBar(context, 'Could not load seasons: $e');
      return null;
    }
    if (!mounted) return null;

    final seasons = tv.requestableSeasons;
    if (seasons.isEmpty) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Request series',
        message: 'Request all seasons of "${metadata.displayTitle}"?',
        confirmText: 'Request',
      );
      return confirmed ? <int>[] : null;
    }

    // Seasons Seerr already has (or has in flight) can't be re-requested.
    final blockedSeasons = <int, SeerrMediaStatus>{};
    for (final info in tv.mediaInfo?.seasons ?? const <SeerrMediaSeasonInfo>[]) {
      final number = info.seasonNumber;
      if (number == null) continue;
      if (info.status != SeerrMediaStatus.unknown && info.status != SeerrMediaStatus.deleted) {
        blockedSeasons[number] = info.status;
      }
    }

    final selected = <int>{};
    return showDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            String blockedLabel(SeerrMediaStatus status) => switch (status) {
              SeerrMediaStatus.available => 'Available',
              SeerrMediaStatus.partiallyAvailable => 'Partial',
              SeerrMediaStatus.processing => 'Processing',
              _ => 'Requested',
            };

            return AlertDialog(
              title: const Text('Request seasons'),
              content: SizedBox(
                width: 420,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      FocusableListTile(
                        autofocus: true,
                        leading: const AppIcon(Symbols.select_all_rounded),
                        title: const Text('All seasons'),
                        onTap: () => Navigator.pop(dialogContext, <int>[]),
                      ),
                      for (final season in seasons)
                        Builder(
                          builder: (context) {
                            final number = season.seasonNumber!;
                            final blocked = blockedSeasons[number];
                            final isSelected = selected.contains(number);
                            return FocusableListTile(
                              enabled: blocked == null,
                              leading: AppIcon(
                                isSelected ? Symbols.check_box_rounded : Symbols.check_box_outline_blank_rounded,
                                fill: isSelected ? 1.0 : 0.0,
                              ),
                              title: Text(season.name ?? 'Season $number'),
                              subtitle: season.episodeCount != null ? Text('${season.episodeCount} episodes') : null,
                              trailing: blocked != null ? Text(blockedLabel(blocked)) : null,
                              onTap: blocked != null
                                  ? null
                                  : () => setDialogState(() {
                                      if (!selected.add(number)) selected.remove(number);
                                    }),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                FocusableButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(t.common.cancel),
                  ),
                ),
                FocusableButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, selected.toList()..sort()),
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(dialogContext, selected.toList()..sort()),
                    child: const Text('Request'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleWatchedTogglePressed(MediaItem metadata) async {
    try {
      final isWatched = metadata.isWatched;
      if (widget.isOffline) {
        // Offline mode: queue action for later sync
        final offlineWatch = context.read<OfflineWatchProvider>();
        if (isWatched) {
          await offlineWatch.markAsUnwatched(serverId: ServerId(metadata.serverId!), itemId: metadata.id);
        } else {
          await offlineWatch.markAsWatched(serverId: ServerId(metadata.serverId!), itemId: metadata.id);
        }
        if (mounted) {
          showAppSnackBar(context, isWatched ? t.messages.markedAsUnwatchedOffline : t.messages.markedAsWatchedOffline);
        }
      } else {
        // Online mode: dispatch via the right backend's neutral method so
        // Jellyfin items hit /UserPlayedItems and Plex items hit /:/scrobble.
        final serverId = metadata.serverId;
        if (serverId == null) return;
        final client = context.tryGetMediaClientForServer(ServerId(serverId));
        if (client == null) return;

        if (isWatched) {
          await client.markUnwatched(metadata);
          unawaited(TrackerCoordinator.instance.markUnwatched(metadata, client));
        } else {
          await client.markWatched(metadata);
          unawaited(TrackerCoordinator.instance.markWatched(metadata, client));
        }
        if (mounted) {
          _watchStateChanged = true;
          showSuccessSnackBar(context, isWatched ? t.messages.markedAsUnwatched : t.messages.markedAsWatched);
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, t.messages.errorLoading(error: e.toString()));
      }
    }
  }

  Widget _buildWatchedToggleButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    bool showFocus = false,
  }) {
    return IconButton.filledTonal(
      onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
      icon: AppIcon(metadata.isWatched ? Symbols.remove_done_rounded : Symbols.check_rounded, fill: 1),
      tooltip: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
      iconSize: PlatformDetector.isTV() ? 21 * tvScale : 20,
      style: actionButtonStyle(showFocus: showFocus),
    );
  }

  Widget _buildMoreActionsButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    VoidCallback? onPlayTrailer,
    bool showFocus = false,
  }) {
    return MediaContextMenu(
      key: _contextMenuKey,
      item: metadata,
      onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
      onPlayTrailer: onPlayTrailer,
      child: Builder(
        builder: (buttonContext) => IconButton.filledTonal(
          onPressed: () {
            final renderBox = buttonContext.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final position = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
              _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
            }
          },
          icon: const AppIcon(Symbols.more_vert_rounded, fill: 1),
          iconSize: PlatformDetector.isTV() ? 21 * tvScale : 20,
          style: actionButtonStyle(showFocus: showFocus),
        ),
      ),
    );
  }

  Future<void> _handleDownloadButtonPressed(MediaItem metadata) async {
    final downloadProvider = context.read<DownloadProvider>();
    final globalKey = metadata.globalKey;
    final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
    final progress = downloadProvider.getProgress(globalKey);

    if (downloadProvider.isQueueing(globalKey) ||
        progress?.status == DownloadStatus.queued ||
        progress?.status == DownloadStatus.downloading) {
      return;
    }

    if (progress?.status == DownloadStatus.paused) {
      final client = _getMediaClientForMetadata(context);
      if (client == null) return;
      await downloadProvider.resumeDownload(globalKey, client);
      if (mounted) showAppSnackBar(context, t.downloads.downloadResumed);
      return;
    }

    if (progress?.status == DownloadStatus.failed) {
      final client = _getMediaClientForMetadata(context);
      if (client == null) return;

      final versionConfig = await _resolveDownloadVersion(context, metadata, client);
      if (versionConfig == null || !mounted) return;

      await downloadProvider.deleteDownload(globalKey);
      try {
        await downloadProvider.queueDownload(metadata, client, versionConfig: versionConfig);
        if (mounted) showSuccessSnackBar(context, t.downloads.downloadQueued);
      } on CellularDownloadBlockedException {
        if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
      }
      return;
    }

    if (progress?.status == DownloadStatus.cancelled) {
      final retry = await showConfirmDialog(
        context,
        title: t.downloads.cancelledDownloadTitle,
        message: t.downloads.cancelledDownloadMessage,
        cancelText: t.common.delete,
        confirmText: t.common.retry,
      );

      if (!retry && mounted) {
        await downloadProvider.deleteDownload(globalKey);
        if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
      } else if (retry && mounted) {
        final client = _getMediaClientForMetadata(context);
        if (client == null) return;

        final versionConfig = await _resolveDownloadVersion(context, metadata, client);
        if (versionConfig == null || !mounted) return;

        await downloadProvider.deleteDownload(globalKey);
        try {
          await downloadProvider.queueDownload(metadata, client, versionConfig: versionConfig);
          if (mounted) showSuccessSnackBar(context, t.downloads.downloadQueued);
        } on CellularDownloadBlockedException {
          if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
        }
      }
      return;
    }

    if (progress?.status == DownloadStatus.partial) {
      if (downloadProvider.hasSyncRule(ruleKey)) {
        await _showSyncRuleActions(context, downloadProvider, metadata, ruleKey: ruleKey, downloadGlobalKey: globalKey);
        return;
      }

      final client = _getMediaClientForMetadata(context);
      if (client == null) return;

      final versionConfig = await _resolveDownloadVersion(context, metadata, client);
      if (versionConfig == null || !mounted) return;

      final count = await downloadProvider.queueMissingEpisodes(metadata, client, versionConfig: versionConfig);
      if (mounted) {
        final message = count > 0 ? t.downloads.episodesQueued(count: count) : t.downloads.allEpisodesAlreadyDownloaded;
        showAppSnackBar(context, message);
      }
      return;
    }

    if (downloadProvider.isDownloaded(globalKey)) {
      if (downloadProvider.hasSyncRule(ruleKey)) {
        await _showSyncRuleActions(context, downloadProvider, metadata, ruleKey: ruleKey, downloadGlobalKey: globalKey);
        return;
      }

      final canDownloadMore = metadata.isShow || metadata.isSeason;
      Future<void> confirmAndDelete() async {
        final confirmed = await showDeleteConfirmation(
          context,
          title: t.downloads.deleteDownload,
          message: t.downloads.deleteConfirm(title: metadata.displayTitle),
        );
        if (confirmed && mounted) {
          await downloadProvider.deleteDownload(globalKey);
          if (mounted) showSuccessSnackBar(context, t.downloads.downloadDeleted);
        }
      }

      if (!canDownloadMore) {
        await confirmAndDelete();
        return;
      }

      final client = _getMediaClientForMetadata(context);
      if (client == null) return;
      try {
        final result = await showDownloadOptionsAndQueue(
          context,
          metadata: metadata,
          client: client,
          downloadProvider: downloadProvider,
          onDelete: confirmAndDelete,
        );
        if (result == null || !mounted) return;
        showSuccessSnackBar(context, result.toSnackBarMessage());
      } on CellularDownloadBlockedException {
        if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
      }
      return;
    }

    final client = _getMediaClientForMetadata(context);
    if (client == null) return;

    try {
      final result = await showDownloadOptionsAndQueue(
        context,
        metadata: metadata,
        client: client,
        downloadProvider: downloadProvider,
      );
      if (result == null || !mounted) return;

      showSuccessSnackBar(context, result.toSnackBarMessage());
    } on CellularDownloadBlockedException {
      if (mounted) showErrorSnackBar(context, t.settings.cellularDownloadBlocked);
    }
  }

  Widget _buildDownloadButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    bool showFocus = false,
  }) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final iconSize = PlatformDetector.isTV() ? 21.0 * tvScale : 20.0;
        final globalKey = metadata.globalKey;
        final ruleKey = _syncRuleKeyForMetadata(context, downloadProvider, metadata);
        final progress = downloadProvider.getProgress(globalKey);
        final isQueueing = downloadProvider.isQueueing(globalKey);

        // Debug logging
        if (progress != null) {
          appLogger.d('UI rebuilding for $globalKey: status=${progress.status}, progress=${progress.progress}%');
        }

        // State 1: Queueing (building download queue)
        if (isQueueing) {
          return IconButton.filledTonal(
            onPressed: null,
            icon: LoadingIndicatorBox(size: iconSize),
            iconSize: iconSize,
            style: actionButtonStyle(showFocus: showFocus),
          );
        }

        // State 2: Queued (waiting to download)
        if (progress?.status == DownloadStatus.queued) {
          final currentFile = progress?.currentFile;
          final tooltip = currentFile != null && currentFile.contains('episodes')
              ? t.downloads.queuedFilesTooltip(files: currentFile)
              : t.downloads.queuedTooltip;

          return IconButton.filledTonal(
            onPressed: null,
            tooltip: tooltip,
            icon: const AppIcon(Symbols.schedule_rounded, fill: 1),
            iconSize: iconSize,
            style: actionButtonStyle(showFocus: showFocus),
          );
        }

        // State 3: Downloading (active download)
        if (progress?.status == DownloadStatus.downloading) {
          // Show episode count in tooltip for shows/seasons
          final currentFile = progress?.currentFile;
          final tooltip = currentFile != null && currentFile.contains('episodes')
              ? t.downloads.downloadingFilesTooltip(files: currentFile)
              : t.downloads.downloadingTooltip;

          return IconButton.filledTonal(
            onPressed: null,
            tooltip: tooltip,
            icon: _buildRadialProgress(progress?.progressPercent),
            iconSize: iconSize,
            style: actionButtonStyle(showFocus: showFocus),
          );
        }

        // State 4: Paused (can resume)
        if (progress?.status == DownloadStatus.paused) {
          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.pause_circle_outline_rounded, fill: 1),
            tooltip: t.downloads.resumeDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.amber, showFocus: showFocus),
          );
        }

        // State 5: Failed (can retry)
        if (progress?.status == DownloadStatus.failed) {
          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.error_outline_rounded, fill: 1),
            tooltip: t.downloads.retryDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.red, showFocus: showFocus),
          );
        }

        // State 6: Cancelled (can delete or retry)
        if (progress?.status == DownloadStatus.cancelled) {
          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.cancel_rounded, fill: 1),
            tooltip: t.downloads.cancelledDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.grey, showFocus: showFocus),
          );
        }

        // State 7: Partial Download (some episodes downloaded, not all)
        if (progress?.status == DownloadStatus.partial) {
          final hasSyncRule = downloadProvider.hasSyncRule(ruleKey);
          final currentFile = progress?.currentFile;

          if (hasSyncRule) {
            // Synced partial — this is the normal state for sync rules
            final syncRule = downloadProvider.getSyncRule(ruleKey);
            final isEnabled = syncRule?.enabled ?? true;
            final tooltip = currentFile != null
                ? t.downloads.syncingFile(
                    file: currentFile,
                    status: t.downloads.keepNUnwatched(count: syncRule?.episodeCount.toString() ?? '?'),
                  )
                : t.downloads.keepSynced;

            return IconButton.filledTonal(
              onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
              tooltip: tooltip,
              icon: AppIcon(isEnabled ? Symbols.sync_rounded : Symbols.sync_disabled_rounded, fill: 1),
              iconSize: iconSize,
              style: actionButtonStyle(foregroundColor: isEnabled ? Colors.teal : Colors.grey, showFocus: showFocus),
            );
          }

          final tooltip = currentFile != null
              ? t.downloads.downloadedFileClickToComplete(file: currentFile)
              : t.downloads.partialDownloadClickToComplete;

          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            tooltip: tooltip,
            icon: const AppIcon(Symbols.downloading_rounded, fill: 1),
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.orange, showFocus: showFocus),
          );
        }

        // State 8: Downloaded/Completed (can delete)
        if (downloadProvider.isDownloaded(globalKey)) {
          final hasSyncRule = downloadProvider.hasSyncRule(ruleKey);

          if (hasSyncRule) {
            // Synced + complete — show sync icon
            final syncRule = downloadProvider.getSyncRule(ruleKey);
            final isEnabled = syncRule?.enabled ?? true;
            return IconButton.filledTonal(
              onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
              icon: AppIcon(isEnabled ? Symbols.sync_rounded : Symbols.sync_disabled_rounded, fill: 1),
              tooltip: t.downloads.keepNUnwatched(count: syncRule?.episodeCount.toString() ?? '?'),
              iconSize: iconSize,
              style: actionButtonStyle(foregroundColor: isEnabled ? Colors.teal : Colors.grey, showFocus: showFocus),
            );
          }

          // Shows/seasons may have more episodes to fetch; movies/episodes don't.
          final canDownloadMore = metadata.isShow || metadata.isSeason;

          return IconButton.filledTonal(
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            icon: const AppIcon(Symbols.download_rounded, fill: 1),
            tooltip: canDownloadMore ? t.downloads.manage : t.downloads.deleteDownload,
            iconSize: iconSize,
            style: actionButtonStyle(foregroundColor: Colors.orange, showFocus: showFocus),
          );
        }

        // State 9: Not downloaded (default - can download)
        return IconButton.filledTonal(
          onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
          icon: const AppIcon(Symbols.download_rounded, fill: 1),
          tooltip: t.downloads.downloadNow,
          iconSize: iconSize,
          style: actionButtonStyle(showFocus: showFocus),
        );
      },
    );
  }
}
