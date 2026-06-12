// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seerr_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SeerrUser _$SeerrUserFromJson(Map<String, dynamic> json) => SeerrUser(
  id: (json['id'] as num).toInt(),
  email: json['email'] as String?,
  username: json['username'] as String?,
  plexUsername: json['plexUsername'] as String?,
  displayName: json['displayName'] as String?,
  avatar: json['avatar'] as String?,
);

SeerrRelatedVideo _$SeerrRelatedVideoFromJson(Map<String, dynamic> json) =>
    SeerrRelatedVideo(
      url: json['url'] as String?,
      key: json['key'] as String?,
      name: json['name'] as String?,
      size: (json['size'] as num?)?.toInt(),
      type: json['type'] as String?,
      site: json['site'] as String?,
    );

SeerrMediaSeasonInfo _$SeerrMediaSeasonInfoFromJson(
  Map<String, dynamic> json,
) => SeerrMediaSeasonInfo(
  id: (json['id'] as num?)?.toInt(),
  seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
  status: json['status'] == null
      ? SeerrMediaStatus.unknown
      : SeerrMediaStatus.fromValue(json['status'] as num?),
);

SeerrMediaInfo _$SeerrMediaInfoFromJson(Map<String, dynamic> json) =>
    SeerrMediaInfo(
      id: (json['id'] as num?)?.toInt(),
      tmdbId: (json['tmdbId'] as num?)?.toInt(),
      tvdbId: (json['tvdbId'] as num?)?.toInt(),
      mediaType: json['mediaType'] as String?,
      status: json['status'] == null
          ? SeerrMediaStatus.unknown
          : SeerrMediaStatus.fromValue(json['status'] as num?),
      status4k: json['status4k'] == null
          ? SeerrMediaStatus.unknown
          : SeerrMediaStatus.fromValue(json['status4k'] as num?),
      seasons: (json['seasons'] as List<dynamic>?)
          ?.map((e) => SeerrMediaSeasonInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      requests: (json['requests'] as List<dynamic>?)
          ?.map((e) => SeerrRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
      plexUrl: json['plexUrl'] as String?,
    );

SeerrRequestSeason _$SeerrRequestSeasonFromJson(Map<String, dynamic> json) =>
    SeerrRequestSeason(
      id: (json['id'] as num?)?.toInt(),
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      status: json['status'] == null
          ? SeerrRequestStatus.pending
          : SeerrRequestStatus.fromValue(json['status'] as num?),
    );

SeerrRequest _$SeerrRequestFromJson(Map<String, dynamic> json) => SeerrRequest(
  id: (json['id'] as num).toInt(),
  status: json['status'] == null
      ? SeerrRequestStatus.pending
      : SeerrRequestStatus.fromValue(json['status'] as num?),
  type: json['type'] as String?,
  media: json['media'] == null
      ? null
      : SeerrMediaInfo.fromJson(json['media'] as Map<String, dynamic>),
  seasons: (json['seasons'] as List<dynamic>?)
      ?.map((e) => SeerrRequestSeason.fromJson(e as Map<String, dynamic>))
      .toList(),
  requestedBy: json['requestedBy'] == null
      ? null
      : SeerrUser.fromJson(json['requestedBy'] as Map<String, dynamic>),
  is4k: json['is4k'] as bool?,
  createdAt: json['createdAt'] as String?,
  updatedAt: json['updatedAt'] as String?,
);

SeerrDiscoverResult _$SeerrDiscoverResultFromJson(Map<String, dynamic> json) =>
    SeerrDiscoverResult(
      id: (json['id'] as num).toInt(),
      mediaType: json['mediaType'] as String,
      title: json['title'] as String?,
      name: json['name'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      overview: json['overview'] as String?,
      releaseDate: json['releaseDate'] as String?,
      firstAirDate: json['firstAirDate'] as String?,
      voteAverage: (json['voteAverage'] as num?)?.toDouble(),
      mediaInfo: json['mediaInfo'] == null
          ? null
          : SeerrMediaInfo.fromJson(json['mediaInfo'] as Map<String, dynamic>),
    );

SeerrMovieDetails _$SeerrMovieDetailsFromJson(Map<String, dynamic> json) =>
    SeerrMovieDetails(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      releaseDate: json['releaseDate'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      tagline: json['tagline'] as String?,
      mediaInfo: json['mediaInfo'] == null
          ? null
          : SeerrMediaInfo.fromJson(json['mediaInfo'] as Map<String, dynamic>),
      relatedVideos: (json['relatedVideos'] as List<dynamic>?)
          ?.map((e) => SeerrRelatedVideo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

SeerrSeason _$SeerrSeasonFromJson(Map<String, dynamic> json) => SeerrSeason(
  id: (json['id'] as num?)?.toInt(),
  seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
  name: json['name'] as String?,
  overview: json['overview'] as String?,
  airDate: json['airDate'] as String?,
  episodeCount: (json['episodeCount'] as num?)?.toInt(),
  posterPath: json['posterPath'] as String?,
);

SeerrTvDetails _$SeerrTvDetailsFromJson(Map<String, dynamic> json) =>
    SeerrTvDetails(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      firstAirDate: json['firstAirDate'] as String?,
      numberOfSeasons: (json['numberOfSeasons'] as num?)?.toInt(),
      seasons: (json['seasons'] as List<dynamic>?)
          ?.map((e) => SeerrSeason.fromJson(e as Map<String, dynamic>))
          .toList(),
      mediaInfo: json['mediaInfo'] == null
          ? null
          : SeerrMediaInfo.fromJson(json['mediaInfo'] as Map<String, dynamic>),
      relatedVideos: (json['relatedVideos'] as List<dynamic>?)
          ?.map((e) => SeerrRelatedVideo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

SeerrSession _$SeerrSessionFromJson(Map<String, dynamic> json) => SeerrSession(
  serverUrl: json['serverUrl'] as String,
  cookie: json['cookie'] as String,
  userId: (json['userId'] as num?)?.toInt(),
  displayName: json['displayName'] as String?,
  email: json['email'] as String?,
  avatar: json['avatar'] as String?,
);

Map<String, dynamic> _$SeerrSessionToJson(SeerrSession instance) =>
    <String, dynamic>{
      'serverUrl': instance.serverUrl,
      'cookie': instance.cookie,
      'userId': instance.userId,
      'displayName': instance.displayName,
      'email': instance.email,
      'avatar': instance.avatar,
    };
