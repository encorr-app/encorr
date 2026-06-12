import 'dart:async';

import 'package:flutter/foundation.dart';

import '../connection/connection_registry.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/seerr/seerr_auth_service.dart';
import '../services/seerr/seerr_client.dart';
import '../services/seerr/seerr_models.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';

/// Owns the Seerr connection state: the persisted session (server URL +
/// `connect.sid` cookie), a live [SeerrClient], discover/search fetchers,
/// request submission, and a per-TMDB-id availability status cache used by
/// detail pages and discover cards.
class SeerrProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  SeerrProvider({required this._connections, SeerrAuthService? authService})
    : _auth = authService ?? SeerrAuthService();

  final ConnectionRegistry _connections;
  final SeerrAuthService _auth;
  final _store = seerrSessionStore;

  SeerrSession? _session;
  SeerrClient? _client;
  bool _initialized = false;
  bool _isSigningIn = false;
  String? _lastError;

  /// Availability cache keyed by `mediaType:tmdbId`.
  final Map<String, SeerrMediaStatus> _statusCache = {};
  final Map<String, Future<SeerrMediaStatus>> _statusInFlight = {};

  // ─── State ────────────────────────────────────────────────────────────

  /// Whether a Seerr server URL has been saved (signed in or not).
  bool get isConfigured => isSignedIn || (serverUrl?.isNotEmpty ?? false);

  bool get isSignedIn => _session != null;
  bool get isSigningIn => _isSigningIn;

  /// Human-readable failure from the last sign-in attempt, if any.
  String? get lastError => _lastError;

  SeerrSession? get session => _session;

  /// Normalized server URL — from the active session when signed in,
  /// otherwise from the saved preference.
  String? get serverUrl =>
      _session?.serverUrl ?? SettingsService.instanceOrNull?.read(SettingsService.seerrUrl);

  String? get displayName => _session?.displayName;

  /// Live client, or null when signed out.
  SeerrClient? get client => _client;

  /// Load the persisted session from disk. Called once at startup.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final loaded = await _store.load();
    if (loaded != null) _setSession(loaded);
  }

  // ─── Auth ─────────────────────────────────────────────────────────────

  /// Sign in to the Seerr server at [url] using the stored Plex account
  /// token. Persists the session (cookie encrypted) and the URL pref.
  /// Returns true on success; on failure [lastError] is populated.
  Future<bool> signIn(String url) async {
    if (_isSigningIn) return false;
    _isSigningIn = true;
    _lastError = null;
    notifyListeners();
    try {
      final session = await _auth.signInWithStoredPlexToken(serverUrl: url, connections: _connections);
      await _store.save(session);
      final settings = SettingsService.instanceOrNull;
      if (settings != null) {
        await settings.write(SettingsService.seerrUrl, session.serverUrl);
      }
      _setSession(session);
      return true;
    } on SeerrAuthException catch (e) {
      appLogger.w('Seerr: sign-in failed', error: e);
      _lastError = e.message;
      return false;
    } catch (e, st) {
      appLogger.w('Seerr: sign-in failed', error: e, stackTrace: st);
      _lastError = e.toString();
      return false;
    } finally {
      _isSigningIn = false;
      safeNotifyListeners();
    }
  }

  /// Clear the stored session and cookie. Keeps the saved URL so the user
  /// can re-connect with one tap.
  Future<void> signOut() async {
    await _store.clear();
    _setSession(null);
  }

  // ─── Discover / search ────────────────────────────────────────────────

  Future<SeerrDiscoverPage> discoverMovies({int page = 1}) => _requireClient().discoverMovies(page: page);

  Future<SeerrDiscoverPage> discoverTv({int page = 1}) => _requireClient().discoverTv(page: page);

  Future<SeerrDiscoverPage> discoverTrending({int page = 1}) => _requireClient().discoverTrending(page: page);

  Future<SeerrDiscoverPage> search(String query, {int page = 1}) => _requireClient().search(query, page: page);

  Future<SeerrMovieDetails> getMovie(int tmdbId) => _requireClient().getMovie(tmdbId);

  Future<SeerrTvDetails> getTv(int tmdbId) => _requireClient().getTv(tmdbId);

  Future<SeerrRequestPage> getRequests({int take = 20, int skip = 0, String filter = 'all'}) =>
      _requireClient().getRequests(take: take, skip: skip, filter: filter);

  // ─── Requests ─────────────────────────────────────────────────────────

  /// Submit a request for [tmdbId]. For TV, pass [seasons] (season numbers)
  /// or leave null to request all seasons. Updates the status cache and
  /// notifies listeners so badges refresh.
  Future<SeerrRequest> submitRequest(int tmdbId, SeerrMediaType mediaType, {List<int>? seasons}) async {
    final request = await _requireClient().submitRequest(mediaId: tmdbId, mediaType: mediaType, seasons: seasons);
    final status = request.media?.status ?? SeerrMediaStatus.pending;
    _statusCache[_statusKey(tmdbId, mediaType)] = status;
    safeNotifyListeners();
    return request;
  }

  // ─── Status cache ─────────────────────────────────────────────────────

  /// Synchronous cache lookup — null when the status hasn't been fetched.
  SeerrMediaStatus? cachedStatus(int tmdbId, SeerrMediaType mediaType) =>
      _statusCache[_statusKey(tmdbId, mediaType)];

  /// Fetch availability for a TMDB id from the detail endpoint, caching the
  /// result. Concurrent calls for the same item share one request.
  Future<SeerrMediaStatus> fetchStatus(int tmdbId, SeerrMediaType mediaType, {bool refresh = false}) {
    final key = _statusKey(tmdbId, mediaType);
    if (!refresh) {
      final cached = _statusCache[key];
      if (cached != null) return Future.value(cached);
    }
    return _statusInFlight[key] ??= _doFetchStatus(tmdbId, mediaType, key).whenComplete(() {
      _statusInFlight.remove(key);
    });
  }

  Future<SeerrMediaStatus> _doFetchStatus(int tmdbId, SeerrMediaType mediaType, String key) async {
    final client = _requireClient();
    final status = switch (mediaType) {
      SeerrMediaType.movie => (await client.getMovie(tmdbId)).status,
      SeerrMediaType.tv => (await client.getTv(tmdbId)).status,
    };
    _statusCache[key] = status;
    safeNotifyListeners();
    return status;
  }

  /// Seed the status cache from discover/search rows that already carry
  /// `mediaInfo`, avoiding a detail fetch per card.
  void primeStatusCache(Iterable<SeerrDiscoverResult> results) {
    var changed = false;
    for (final result in results) {
      final type = result.type;
      final info = result.mediaInfo;
      if (type == null || info == null) continue;
      final key = _statusKey(result.id, type);
      if (_statusCache[key] != info.status) {
        _statusCache[key] = info.status;
        changed = true;
      }
    }
    if (changed) safeNotifyListeners();
  }

  // ─── Internals ────────────────────────────────────────────────────────

  static String _statusKey(int tmdbId, SeerrMediaType mediaType) => '${mediaType.apiValue}:$tmdbId';

  SeerrClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const SeerrAuthException('Not signed in to Seerr');
    }
    return client;
  }

  void _setSession(SeerrSession? session) {
    _session = session;
    _client?.dispose();
    _client = session == null
        ? null
        : SeerrClient(
            baseUrl: session.serverUrl,
            sessionCookie: session.cookie,
            onSessionInvalidated: _handleSessionInvalidated,
          );
    _statusCache.clear();
    safeNotifyListeners();
  }

  /// Called by [SeerrClient] on 401/403 — the cookie expired server-side.
  /// Clears local state so the UI shows "not signed in" and the user can
  /// re-link (a fresh sign-in only needs the stored Plex token).
  void _handleSessionInvalidated() {
    if (_session == null) return;
    appLogger.w('Seerr: session invalidated, clearing stored cookie');
    unawaited(_store.clear());
    _setSession(null);
  }

  @override
  void dispose() {
    _client?.dispose();
    _client = null;
    super.dispose();
  }
}
