import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../utils/abortable_http_request.dart';
import '../../utils/app_logger.dart';
import '../../utils/platform_http_client_stub.dart'
    if (dart.library.io) '../../utils/platform_http_client_io.dart'
    as platform;
import '../trackers/tracker_constants.dart';
import 'seerr_models.dart';

/// HTTP wrapper for the Seerr REST API (Overseerr v1 API, paths under
/// `/api/v1`).
///
/// Authentication is a `connect.sid` session cookie obtained from
/// `POST /auth/plex` (Plex SSO — no second login). 401/403 responses raise
/// [SeerrAuthException] so the UI layer can prompt for re-auth; the optional
/// [onSessionInvalidated] callback fires at the same time.
class SeerrClient {
  /// Base URL without the `/api/v1` suffix or trailing slash.
  final String baseUrl;

  /// Session cookie currently attached to requests (`connect.sid=...`).
  String? sessionCookie;

  final http.Client _http;

  /// Fired when a request comes back 401/403, i.e. the stored session cookie
  /// is no longer valid. The provider uses this to clear stored state.
  final void Function()? onSessionInvalidated;

  SeerrClient({required String baseUrl, this.sessionCookie, this.onSessionInvalidated, http.Client? httpClient})
    : baseUrl = normalizeBaseUrl(baseUrl),
      _http = httpClient ?? platform.createPlatformClient();

  void dispose() => _http.close();

  /// Strips whitespace, a trailing slash, and a trailing `/api/v1` so users
  /// can paste any variant of their server URL.
  static String normalizeBaseUrl(String url) {
    var normalized = url.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.toLowerCase().endsWith('/api/v1')) {
      normalized = normalized.substring(0, normalized.length - '/api/v1'.length);
    }
    return normalized;
  }

  /// Exchange a plex.tv account token for a Seerr session. On success the
  /// returned cookie is also installed on this client for follow-up calls.
  Future<({SeerrUser user, String cookie})> signInWithPlex(String plexToken) async {
    final res = await _send('POST', '/auth/plex', body: {'authToken': plexToken});
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SeerrAuthException('Plex sign-in rejected: HTTP ${res.statusCode}');
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw SeerrApiException(statusCode: res.statusCode, body: res.body);
    }

    final cookie = _extractSessionCookie(res.headers);
    if (cookie == null) {
      throw const SeerrAuthException('Sign-in succeeded but no connect.sid cookie was returned');
    }
    sessionCookie = cookie;

    final user = SeerrUser.fromJson(json.decode(res.body) as Map<String, dynamic>);
    return (user: user, cookie: cookie);
  }

  /// Validate the current session and return the signed-in user.
  Future<SeerrUser> getCurrentUser() async {
    final res = await _request('GET', '/auth/me');
    return SeerrUser.fromJson(res as Map<String, dynamic>);
  }

  Future<SeerrDiscoverPage> search(String query, {int page = 1}) async {
    final res = await _request('GET', '/search', query: {'query': query, 'page': '$page'});
    return SeerrDiscoverPage.fromJson(res as Map<String, dynamic>);
  }

  Future<SeerrDiscoverPage> discoverMovies({int page = 1}) async {
    final res = await _request('GET', '/discover/movies', query: {'page': '$page'});
    return _moviePage(res as Map<String, dynamic>);
  }

  Future<SeerrDiscoverPage> discoverTv({int page = 1}) async {
    final res = await _request('GET', '/discover/tv', query: {'page': '$page'});
    return _tvPage(res as Map<String, dynamic>);
  }

  Future<SeerrDiscoverPage> discoverTrending({int page = 1}) async {
    final res = await _request('GET', '/discover/trending', query: {'page': '$page'});
    return SeerrDiscoverPage.fromJson(res as Map<String, dynamic>);
  }

  Future<SeerrMovieDetails> getMovie(int tmdbId) async {
    final res = await _request('GET', '/movie/$tmdbId');
    return SeerrMovieDetails.fromJson(res as Map<String, dynamic>);
  }

  Future<SeerrTvDetails> getTv(int tmdbId) async {
    final res = await _request('GET', '/tv/$tmdbId');
    return SeerrTvDetails.fromJson(res as Map<String, dynamic>);
  }

  /// Submit a request. For TV pass [seasons] (season numbers) or leave null
  /// to request all seasons.
  Future<SeerrRequest> submitRequest({
    required int mediaId,
    required SeerrMediaType mediaType,
    List<int>? seasons,
    bool is4k = false,
  }) async {
    final body = <String, dynamic>{
      'mediaType': mediaType.apiValue,
      'mediaId': mediaId,
      if (is4k) 'is4k': true,
      if (mediaType == SeerrMediaType.tv) 'seasons': seasons ?? 'all',
    };
    final res = await _request('POST', '/request', body: body);
    return SeerrRequest.fromJson(res as Map<String, dynamic>);
  }

  /// List requests. [filter] matches Overseerr's `filter` query param
  /// (`all`, `approved`, `available`, `pending`, `processing`, `unavailable`).
  Future<SeerrRequestPage> getRequests({
    int take = 20,
    int skip = 0,
    String filter = 'all',
    String sort = 'added',
  }) async {
    final res = await _request(
      'GET',
      '/request',
      query: {'take': '$take', 'skip': '$skip', 'filter': filter, 'sort': sort},
    );
    return SeerrRequestPage.fromJson(res as Map<String, dynamic>);
  }

  /// List media known to Seerr. [filter] matches Overseerr's `filter` query
  /// param (`all`, `available`, `partial`, `allavailable`, `processing`, `pending`).
  Future<SeerrMediaPage> getMedia({int take = 20, int skip = 0, String filter = 'all'}) async {
    final res = await _request('GET', '/media', query: {'take': '$take', 'skip': '$skip', 'filter': filter});
    return SeerrMediaPage.fromJson(res as Map<String, dynamic>);
  }

  /// `/discover/movies` rows omit `mediaType`; backfill it before parsing.
  SeerrDiscoverPage _moviePage(Map<String, dynamic> json) => SeerrDiscoverPage.fromJson(_withMediaType(json, 'movie'));

  /// `/discover/tv` rows omit `mediaType`; backfill it before parsing.
  SeerrDiscoverPage _tvPage(Map<String, dynamic> json) => SeerrDiscoverPage.fromJson(_withMediaType(json, 'tv'));

  static Map<String, dynamic> _withMediaType(Map<String, dynamic> json, String mediaType) {
    final results = json['results'];
    if (results is List) {
      for (final row in results) {
        if (row is Map<String, dynamic>) row['mediaType'] ??= mediaType;
      }
    }
    return json;
  }

  /// Extract `connect.sid=<value>` from a Set-Cookie header. package:http
  /// folds repeated headers into one comma-separated string, so match the
  /// cookie name directly rather than splitting on commas (expiry dates
  /// contain commas too).
  static String? _extractSessionCookie(Map<String, String> headers) {
    final setCookie = headers['set-cookie'];
    if (setCookie == null) return null;
    final match = RegExp(r'connect\.sid=([^;,\s]+)').firstMatch(setCookie);
    if (match == null) return null;
    return 'connect.sid=${match.group(1)}';
  }

  /// Send an authenticated request and decode the JSON body.
  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Set<int> allowStatuses = const {200, 201, 204},
  }) async {
    final res = await _send(method, path, query: query, body: body);

    if (res.statusCode == 401 || res.statusCode == 403) {
      onSessionInvalidated?.call();
      throw SeerrAuthException('HTTP ${res.statusCode} for $method $path');
    }

    if (allowStatuses.contains(res.statusCode)) {
      if (res.body.isEmpty) return null;
      try {
        return json.decode(res.body);
      } catch (_) {
        return null;
      }
    }

    throw SeerrApiException(statusCode: res.statusCode, body: res.body);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (sessionCookie != null && sessionCookie!.isNotEmpty) 'Cookie': sessionCookie!,
    };

    final sw = Stopwatch()..start();
    final res = await sendAbortableHttpRequest(
      _http,
      method,
      uri,
      headers: headers,
      body: body == null ? null : json.encode(body),
      timeout: TrackerConstants.requestTimeout,
      operation: 'Seerr $method ${uri.path}',
    );
    sw.stop();

    appLogger.d('Seerr $method ${uri.path} → ${res.statusCode} (${sw.elapsedMilliseconds}ms)');
    return res;
  }
}

class SeerrApiException implements Exception {
  final int statusCode;
  final String body;
  const SeerrApiException({required this.statusCode, required this.body});
  @override
  String toString() => 'SeerrApiException(HTTP $statusCode): $body';
}

/// Raised on 401/403 — the session cookie is missing or expired and the UI
/// should prompt the user to sign in again.
class SeerrAuthException implements Exception {
  final String message;
  const SeerrAuthException(this.message);
  @override
  String toString() => 'SeerrAuthException: $message';
}
