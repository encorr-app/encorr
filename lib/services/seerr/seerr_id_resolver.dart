import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import 'seerr_models.dart';

/// A library item mapped to its Seerr coordinate: TMDB id + media type.
/// Seasons and episodes map to their parent show (Seerr requests are
/// show-scoped with a season list).
class SeerrMediaRef {
  final int tmdbId;
  final SeerrMediaType mediaType;

  const SeerrMediaRef({required this.tmdbId, required this.mediaType});
}

/// Resolves a [MediaItem] from a Plex/Jellyfin library to its TMDB id via
/// the backend-neutral [MediaServerClient.fetchExternalIds] surface (Plex
/// reads the `Guid` array — `tmdb://456` — Jellyfin the inline `ProviderIds`
/// map). Results, including "no TMDB id", are cached per item for the app
/// session so detail pages don't refetch guids on every visit.
class SeerrIdResolver {
  SeerrIdResolver._();

  static final Map<String, SeerrMediaRef?> _cache = {};
  static final Map<String, Future<SeerrMediaRef?>> _inFlight = {};

  /// TMDB id + media type for [item], or null when the item kind is not
  /// requestable (music, collections…) or the server has no TMDB guid.
  /// Never throws — lookup failures resolve to null.
  static Future<SeerrMediaRef?> resolve(MediaItem item, MediaServerClient client) {
    final target = _targetFor(item);
    if (target == null) return Future.value(null);

    final cacheKey = '${item.serverId ?? ''}:${target.itemId}';
    if (_cache.containsKey(cacheKey)) return Future.value(_cache[cacheKey]);

    return _inFlight[cacheKey] ??= _doResolve(target, client, cacheKey).whenComplete(() {
      _inFlight.remove(cacheKey);
    });
  }

  static Future<SeerrMediaRef?> _doResolve(
    ({String itemId, SeerrMediaType mediaType}) target,
    MediaServerClient client,
    String cacheKey,
  ) async {
    try {
      final external = await client.fetchExternalIds(target.itemId);
      final tmdb = external.tmdb;
      final ref = tmdb == null ? null : SeerrMediaRef(tmdbId: tmdb, mediaType: target.mediaType);
      _cache[cacheKey] = ref;
      return ref;
    } catch (e) {
      appLogger.d('Seerr: external id lookup failed for ${target.itemId}', error: e);
      return null;
    }
  }

  /// The item whose guids carry the TMDB id, plus the Seerr media type.
  /// Episodes/seasons resolve against the show because Seerr only tracks
  /// shows and movies.
  static ({String itemId, SeerrMediaType mediaType})? _targetFor(MediaItem item) {
    if (item.isMovie) return (itemId: item.id, mediaType: SeerrMediaType.movie);
    if (item.isShow) return (itemId: item.id, mediaType: SeerrMediaType.tv);
    if (item.isSeason) {
      final showId = item.parentId;
      if (showId == null || showId.isEmpty) return null;
      return (itemId: showId, mediaType: SeerrMediaType.tv);
    }
    if (item.isEpisode) {
      final showId = item.grandparentId;
      if (showId == null || showId.isEmpty) return null;
      return (itemId: showId, mediaType: SeerrMediaType.tv);
    }
    return null;
  }
}
