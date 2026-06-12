import 'package:json_annotation/json_annotation.dart';

part 'seerr_models.g.dart';

/// Media kind used across Seerr endpoints and request payloads.
enum SeerrMediaType {
  movie,
  tv;

  /// Wire value used in URLs and request bodies (`movie` / `tv`).
  String get apiValue => name;

  static SeerrMediaType? fromApiValue(String? value) => switch (value) {
    'movie' => SeerrMediaType.movie,
    'tv' => SeerrMediaType.tv,
    _ => null,
  };
}

/// Availability of an item on the linked media server, as reported by
/// Seerr's `mediaInfo.status` (Overseerr `MediaStatus`).
enum SeerrMediaStatus {
  unknown(1),
  pending(2),
  processing(3),
  partiallyAvailable(4),
  available(5),
  deleted(6);

  const SeerrMediaStatus(this.value);
  final int value;

  static SeerrMediaStatus fromValue(num? value) =>
      values.firstWhere((s) => s.value == value?.toInt(), orElse: () => SeerrMediaStatus.unknown);
}

/// Approval state of a Seerr media request (Overseerr `MediaRequestStatus`).
enum SeerrRequestStatus {
  pending(1),
  approved(2),
  declined(3),
  failed(4);

  const SeerrRequestStatus(this.value);
  final int value;

  static SeerrRequestStatus fromValue(num? value) =>
      values.firstWhere((s) => s.value == value?.toInt(), orElse: () => SeerrRequestStatus.pending);
}

/// Seerr user, as returned by `POST /auth/plex` and `GET /auth/me`.
@JsonSerializable(createToJson: false)
class SeerrUser {
  final int id;
  final String? email;
  final String? username;
  final String? plexUsername;
  final String? displayName;
  final String? avatar;

  const SeerrUser({required this.id, this.email, this.username, this.plexUsername, this.displayName, this.avatar});

  /// Best human-readable name available for this user.
  String get resolvedDisplayName {
    for (final candidate in [displayName, plexUsername, username, email]) {
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return 'User $id';
  }

  factory SeerrUser.fromJson(Map<String, dynamic> json) => _$SeerrUserFromJson(json);
}

/// One entry of `relatedVideos` on movie/TV detail responses. YouTube
/// trailers have `site == 'YouTube'` and [key] is the YouTube video id.
@JsonSerializable(createToJson: false)
class SeerrRelatedVideo {
  final String? url;
  final String? key;
  final String? name;
  final int? size;
  final String? type;
  final String? site;

  const SeerrRelatedVideo({this.url, this.key, this.name, this.size, this.type, this.site});

  bool get isYouTube => site?.toLowerCase() == 'youtube';
  bool get isTrailer => type?.toLowerCase() == 'trailer';

  factory SeerrRelatedVideo.fromJson(Map<String, dynamic> json) => _$SeerrRelatedVideoFromJson(json);
}

/// Per-season availability inside [SeerrMediaInfo.seasons].
@JsonSerializable(createToJson: false)
class SeerrMediaSeasonInfo {
  final int? id;
  final int? seasonNumber;

  @JsonKey(fromJson: SeerrMediaStatus.fromValue)
  final SeerrMediaStatus status;

  const SeerrMediaSeasonInfo({this.id, this.seasonNumber, this.status = SeerrMediaStatus.unknown});

  factory SeerrMediaSeasonInfo.fromJson(Map<String, dynamic> json) => _$SeerrMediaSeasonInfoFromJson(json);
}

/// Seerr's media record (`mediaInfo` on discover/detail payloads, or a
/// result row from `GET /media`). Present only when Seerr knows about the
/// item (requested or available); absent means "not requested".
@JsonSerializable(createToJson: false)
class SeerrMediaInfo {
  final int? id;
  final int? tmdbId;
  final int? tvdbId;
  final String? mediaType;

  @JsonKey(fromJson: SeerrMediaStatus.fromValue)
  final SeerrMediaStatus status;

  @JsonKey(fromJson: SeerrMediaStatus.fromValue)
  final SeerrMediaStatus status4k;

  final List<SeerrMediaSeasonInfo>? seasons;
  final List<SeerrRequest>? requests;
  final String? plexUrl;

  const SeerrMediaInfo({
    this.id,
    this.tmdbId,
    this.tvdbId,
    this.mediaType,
    this.status = SeerrMediaStatus.unknown,
    this.status4k = SeerrMediaStatus.unknown,
    this.seasons,
    this.requests,
    this.plexUrl,
  });

  factory SeerrMediaInfo.fromJson(Map<String, dynamic> json) => _$SeerrMediaInfoFromJson(json);
}

/// A season entry inside a request payload.
@JsonSerializable(createToJson: false)
class SeerrRequestSeason {
  final int? id;
  final int? seasonNumber;

  @JsonKey(fromJson: SeerrRequestStatus.fromValue)
  final SeerrRequestStatus status;

  const SeerrRequestSeason({this.id, this.seasonNumber, this.status = SeerrRequestStatus.pending});

  factory SeerrRequestSeason.fromJson(Map<String, dynamic> json) => _$SeerrRequestSeasonFromJson(json);
}

/// A media request (`POST /request` response and `GET /request` rows).
@JsonSerializable(createToJson: false)
class SeerrRequest {
  final int id;

  @JsonKey(fromJson: SeerrRequestStatus.fromValue)
  final SeerrRequestStatus status;

  /// `movie` or `tv`.
  final String? type;

  final SeerrMediaInfo? media;
  final List<SeerrRequestSeason>? seasons;
  final SeerrUser? requestedBy;
  final bool? is4k;
  final String? createdAt;
  final String? updatedAt;

  const SeerrRequest({
    required this.id,
    this.status = SeerrRequestStatus.pending,
    this.type,
    this.media,
    this.seasons,
    this.requestedBy,
    this.is4k,
    this.createdAt,
    this.updatedAt,
  });

  factory SeerrRequest.fromJson(Map<String, dynamic> json) => _$SeerrRequestFromJson(json);
}

/// A movie or TV row from `/discover/*` and `/search`. Person results are
/// filtered out during page parsing.
@JsonSerializable(createToJson: false)
class SeerrDiscoverResult {
  /// TMDB id.
  final int id;

  /// `movie` or `tv`.
  final String mediaType;

  /// Movie title (movies only).
  final String? title;

  /// Series name (TV only).
  final String? name;

  final String? posterPath;
  final String? backdropPath;
  final String? overview;

  /// Movie release date (movies only), `YYYY-MM-DD`.
  final String? releaseDate;

  /// First air date (TV only), `YYYY-MM-DD`.
  final String? firstAirDate;

  final double? voteAverage;
  final SeerrMediaInfo? mediaInfo;

  const SeerrDiscoverResult({
    required this.id,
    required this.mediaType,
    this.title,
    this.name,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.releaseDate,
    this.firstAirDate,
    this.voteAverage,
    this.mediaInfo,
  });

  SeerrMediaType? get type => SeerrMediaType.fromApiValue(mediaType);
  String get displayTitle => title ?? name ?? '';
  String? get displayDate => releaseDate ?? firstAirDate;
  SeerrMediaStatus get status => mediaInfo?.status ?? SeerrMediaStatus.unknown;

  factory SeerrDiscoverResult.fromJson(Map<String, dynamic> json) => _$SeerrDiscoverResultFromJson(json);
}

/// One page of discover/search results (`{page, totalPages, totalResults,
/// results}`). Hand-rolled fromJson so person rows can be dropped.
class SeerrDiscoverPage {
  final int page;
  final int totalPages;
  final int totalResults;
  final List<SeerrDiscoverResult> results;

  const SeerrDiscoverPage({
    required this.page,
    required this.totalPages,
    required this.totalResults,
    required this.results,
  });

  bool get hasMore => page < totalPages;

  factory SeerrDiscoverPage.fromJson(Map<String, dynamic> json) {
    final raw = json['results'];
    final results = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .where((m) => m['mediaType'] == 'movie' || m['mediaType'] == 'tv')
              .map(SeerrDiscoverResult.fromJson)
              .toList()
        : <SeerrDiscoverResult>[];
    return SeerrDiscoverPage(
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      totalResults: (json['totalResults'] as num?)?.toInt() ?? results.length,
      results: results,
    );
  }
}

/// Pagination block on `GET /request` and `GET /media` responses.
class SeerrPageInfo {
  final int page;
  final int pages;
  final int pageSize;
  final int results;

  const SeerrPageInfo({required this.page, required this.pages, required this.pageSize, required this.results});

  factory SeerrPageInfo.fromJson(Map<String, dynamic>? json) => SeerrPageInfo(
    page: (json?['page'] as num?)?.toInt() ?? 1,
    pages: (json?['pages'] as num?)?.toInt() ?? 1,
    pageSize: (json?['pageSize'] as num?)?.toInt() ?? 0,
    results: (json?['results'] as num?)?.toInt() ?? 0,
  );
}

/// One page of `GET /request` results.
class SeerrRequestPage {
  final SeerrPageInfo pageInfo;
  final List<SeerrRequest> results;

  const SeerrRequestPage({required this.pageInfo, required this.results});

  factory SeerrRequestPage.fromJson(Map<String, dynamic> json) {
    final raw = json['results'];
    return SeerrRequestPage(
      pageInfo: SeerrPageInfo.fromJson(json['pageInfo'] as Map<String, dynamic>?),
      results: raw is List ? raw.whereType<Map<String, dynamic>>().map(SeerrRequest.fromJson).toList() : const [],
    );
  }
}

/// One page of `GET /media` results.
class SeerrMediaPage {
  final SeerrPageInfo pageInfo;
  final List<SeerrMediaInfo> results;

  const SeerrMediaPage({required this.pageInfo, required this.results});

  factory SeerrMediaPage.fromJson(Map<String, dynamic> json) {
    final raw = json['results'];
    return SeerrMediaPage(
      pageInfo: SeerrPageInfo.fromJson(json['pageInfo'] as Map<String, dynamic>?),
      results: raw is List ? raw.whereType<Map<String, dynamic>>().map(SeerrMediaInfo.fromJson).toList() : const [],
    );
  }
}

/// Movie detail from `GET /movie/{tmdbId}`.
@JsonSerializable(createToJson: false)
class SeerrMovieDetails {
  /// TMDB id.
  final int id;

  final String? title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final int? runtime;
  final String? tagline;
  final SeerrMediaInfo? mediaInfo;
  final List<SeerrRelatedVideo>? relatedVideos;

  const SeerrMovieDetails({
    required this.id,
    this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.runtime,
    this.tagline,
    this.mediaInfo,
    this.relatedVideos,
  });

  SeerrMediaStatus get status => mediaInfo?.status ?? SeerrMediaStatus.unknown;

  /// YouTube key of the best trailer, or null when none exists.
  String? get youTubeTrailerKey => bestYouTubeVideoKey(relatedVideos);

  factory SeerrMovieDetails.fromJson(Map<String, dynamic> json) => _$SeerrMovieDetailsFromJson(json);
}

/// A season summary inside [SeerrTvDetails.seasons].
@JsonSerializable(createToJson: false)
class SeerrSeason {
  final int? id;
  final int? seasonNumber;
  final String? name;
  final String? overview;
  final String? airDate;
  final int? episodeCount;
  final String? posterPath;

  const SeerrSeason({
    this.id,
    this.seasonNumber,
    this.name,
    this.overview,
    this.airDate,
    this.episodeCount,
    this.posterPath,
  });

  factory SeerrSeason.fromJson(Map<String, dynamic> json) => _$SeerrSeasonFromJson(json);
}

/// TV detail from `GET /tv/{tmdbId}`.
@JsonSerializable(createToJson: false)
class SeerrTvDetails {
  /// TMDB id.
  final int id;

  final String? name;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? firstAirDate;
  final int? numberOfSeasons;
  final List<SeerrSeason>? seasons;
  final SeerrMediaInfo? mediaInfo;
  final List<SeerrRelatedVideo>? relatedVideos;

  const SeerrTvDetails({
    required this.id,
    this.name,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.numberOfSeasons,
    this.seasons,
    this.mediaInfo,
    this.relatedVideos,
  });

  SeerrMediaStatus get status => mediaInfo?.status ?? SeerrMediaStatus.unknown;

  /// Seasons that can be requested (skips season 0 specials).
  List<SeerrSeason> get requestableSeasons =>
      (seasons ?? const []).where((s) => (s.seasonNumber ?? 0) > 0).toList();

  /// YouTube key of the best trailer, or null when none exists.
  String? get youTubeTrailerKey => bestYouTubeVideoKey(relatedVideos);

  factory SeerrTvDetails.fromJson(Map<String, dynamic> json) => _$SeerrTvDetailsFromJson(json);
}

/// Picks the most useful YouTube video key from `relatedVideos`: prefers
/// videos typed "Trailer", falls back to any YouTube video.
String? bestYouTubeVideoKey(List<SeerrRelatedVideo>? videos) {
  if (videos == null || videos.isEmpty) return null;
  SeerrRelatedVideo? fallback;
  for (final video in videos) {
    if (!video.isYouTube || video.key == null || video.key!.isEmpty) continue;
    if (video.isTrailer) return video.key;
    fallback ??= video;
  }
  return fallback?.key;
}

/// Persisted Seerr session: which server we're signed into and the
/// `connect.sid` session cookie. The cookie is encrypted via
/// `CredentialVault` before this object is written to disk.
@JsonSerializable()
class SeerrSession {
  /// Normalized base URL of the Seerr server (no trailing slash, no `/api/v1`).
  final String serverUrl;

  /// Session cookie in `connect.sid=<value>` form, sent on every request.
  final String cookie;

  final int? userId;
  final String? displayName;
  final String? email;
  final String? avatar;

  const SeerrSession({
    required this.serverUrl,
    required this.cookie,
    this.userId,
    this.displayName,
    this.email,
    this.avatar,
  });

  SeerrSession copyWith({
    String? serverUrl,
    String? cookie,
    int? userId,
    String? displayName,
    String? email,
    String? avatar,
  }) {
    return SeerrSession(
      serverUrl: serverUrl ?? this.serverUrl,
      cookie: cookie ?? this.cookie,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
    );
  }

  Map<String, dynamic> toJson() => _$SeerrSessionToJson(this);

  factory SeerrSession.fromJson(Map<String, dynamic> json) => _$SeerrSessionFromJson(json);
}
