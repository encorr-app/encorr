import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../providers/seerr_provider.dart';
import '../utils/app_logger.dart';
import 'seerr/seerr_models.dart';

/// A resolved background trailer: the YouTube video id and a direct,
/// player-openable stream URL.
class TrailerResolution {
  final String youTubeKey;
  final String streamUrl;

  /// Whether [streamUrl] carries an audio track (muxed stream). Video-only
  /// streams cannot be unmuted; the UI hides the unmute affordance then.
  final bool hasAudio;

  const TrailerResolution({required this.youTubeKey, required this.streamUrl, required this.hasAudio});
}

/// Resolves background trailers for detail pages.
///
/// Pipeline: TMDB id → Seerr `relatedVideos` (best YouTube trailer key) →
/// youtube_explode_dart stream manifest → direct mp4 stream URL (≤1080p).
/// Seerr is the only metadata source — when the user isn't signed in there
/// is no trailer. Every failure resolves to null so the static backdrop is
/// the silent fallback; YouTube extraction breaking must never surface.
///
/// Resolutions are cached in memory for the app session. Note YouTube
/// stream URLs expire after ~6 hours; acceptable for a session cache.
class TrailerService {
  TrailerService._();

  static final TrailerService instance = TrailerService._();

  /// `movie:123` / `tv:456` → resolution (null = known to have none).
  final Map<String, Future<TrailerResolution?>> _byMedia = {};

  /// YouTube key → resolution.
  final Map<String, Future<TrailerResolution?>> _byKey = {};

  /// Resolve a playable trailer stream for a TMDB id, or null when the user
  /// isn't signed in to Seerr, the item has no YouTube trailer, or stream
  /// extraction failed.
  Future<TrailerResolution?> resolveForMedia({
    required int tmdbId,
    required SeerrMediaType mediaType,
    required SeerrProvider seerr,
  }) {
    if (!seerr.isSignedIn) return Future.value(null);
    final cacheKey = '${mediaType.apiValue}:$tmdbId';
    return _byMedia[cacheKey] ??= _resolveForMedia(tmdbId, mediaType, seerr);
  }

  Future<TrailerResolution?> _resolveForMedia(int tmdbId, SeerrMediaType mediaType, SeerrProvider seerr) async {
    String? key;
    try {
      key = switch (mediaType) {
        SeerrMediaType.movie => (await seerr.getMovie(tmdbId)).youTubeTrailerKey,
        SeerrMediaType.tv => (await seerr.getTv(tmdbId)).youTubeTrailerKey,
      };
    } catch (e) {
      appLogger.d('Trailer: Seerr detail fetch failed for $mediaType/$tmdbId', error: e);
      return null;
    }
    if (key == null || key.isEmpty) {
      appLogger.d('Trailer: no YouTube key from Seerr for $mediaType/$tmdbId');
      return null;
    }
    return resolveYouTubeKey(key);
  }

  /// Resolve a YouTube video id to a direct stream URL. Null on any failure.
  Future<TrailerResolution?> resolveYouTubeKey(String youTubeKey) {
    return _byKey[youTubeKey] ??= _resolveYouTubeKey(youTubeKey);
  }

  Future<TrailerResolution?> _resolveYouTubeKey(String youTubeKey) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streams.getManifest(youTubeKey);
      final pick = _pickStream(manifest);
      if (pick == null) {
        appLogger.d('Trailer: no suitable mp4 stream for $youTubeKey');
        return null;
      }
      appLogger.d('Trailer: picked ${pick.info.videoResolution.height}p stream for $youTubeKey (audio=${pick.hasAudio})');
      return TrailerResolution(
        youTubeKey: youTubeKey,
        streamUrl: pick.info.url.toString(),
        hasAudio: pick.hasAudio,
      );
    } catch (e) {
      appLogger.d('Trailer: manifest fetch failed for $youTubeKey', error: e);
      return null;
    } finally {
      yt.close();
    }
  }

  /// Best mp4 stream ≤1080p. The trailer plays muted in the background, so
  /// visual quality wins: video-only streams (up to 1080p) are preferred
  /// over muxed ones (which YouTube caps around 360p). Muxed is the
  /// fallback — and the only path that can be unmuted.
  ({VideoStreamInfo info, bool hasAudio})? _pickStream(StreamManifest manifest) {
    VideoStreamInfo? bestOf(Iterable<VideoStreamInfo> streams) {
      VideoStreamInfo? best;
      for (final stream in streams) {
        if (stream.container.name != 'mp4') continue;
        final height = stream.videoResolution.height;
        if (height > 1080) continue;
        if (best == null ||
            height > best.videoResolution.height ||
            (height == best.videoResolution.height && stream.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond)) {
          best = stream;
        }
      }
      return best;
    }

    final videoOnly = bestOf(manifest.videoOnly);
    final muxed = bestOf(manifest.muxed);

    // A muxed stream that matches (or beats) the video-only height is the
    // better pick — same picture plus an audio track for unmute.
    if (muxed != null && (videoOnly == null || muxed.videoResolution.height >= videoOnly.videoResolution.height)) {
      return (info: muxed, hasAudio: true);
    }
    if (videoOnly != null) return (info: videoOnly, hasAudio: false);
    if (muxed != null) return (info: muxed, hasAudio: true);
    return null;
  }
}
