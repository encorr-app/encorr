import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../utils/app_logger.dart';
import '../base_shared_preferences_service.dart';
import '../credential_vault.dart';
import 'seerr_client.dart';
import 'seerr_models.dart';

/// Signs in to a Seerr server with the Plex account token already stored in
/// [ConnectionRegistry] — the user never sees a second login.
///
/// The resulting [SeerrSession] (server URL + `connect.sid` cookie + user
/// info) is persisted via [SeerrSessionStore] with the cookie encrypted by
/// [CredentialVault].
class SeerrAuthService {
  SeerrAuthService({this._httpClient});

  final http.Client? _httpClient;

  /// Resolve the Plex account token from the stored connections: prefers the
  /// default connection when it is a Plex account, otherwise the first Plex
  /// account. Tokens come out of the registry already decrypted.
  Future<String?> resolvePlexToken(ConnectionRegistry connections) async {
    final preferred = await connections.getDefault();
    if (preferred is PlexAccountConnection && preferred.accountToken.isNotEmpty) {
      return preferred.accountToken;
    }
    final accounts = await connections.listPlexAccounts();
    for (final account in accounts) {
      if (account.accountToken.isNotEmpty) return account.accountToken;
    }
    return null;
  }

  /// Sign in to the Seerr server at [serverUrl] using the stored Plex token.
  ///
  /// Throws [SeerrAuthException] when no Plex account is stored or the
  /// server rejects the token, [SeerrApiException] for other HTTP failures.
  Future<SeerrSession> signInWithStoredPlexToken({
    required String serverUrl,
    required ConnectionRegistry connections,
  }) async {
    final plexToken = await resolvePlexToken(connections);
    if (plexToken == null) {
      throw const SeerrAuthException('No Plex account with a stored token is available');
    }

    final client = SeerrClient(baseUrl: serverUrl, httpClient: _httpClient);
    try {
      final result = await client.signInWithPlex(plexToken);
      final session = SeerrSession(
        serverUrl: client.baseUrl,
        cookie: result.cookie,
        userId: result.user.id,
        displayName: result.user.resolvedDisplayName,
        email: result.user.email,
        avatar: result.user.avatar,
      );
      appLogger.i('Seerr: signed in as ${session.displayName} at ${session.serverUrl}');
      return session;
    } finally {
      if (_httpClient == null) client.dispose();
    }
  }
}

/// Persists the [SeerrSession] in SharedPreferences with the session cookie
/// encrypted via [CredentialVault]. One global slot — the Seerr server and
/// the Plex account token are app-wide, not per-Home-profile.
class SeerrSessionStore {
  static const String _key = 'seerr_session_v1';

  const SeerrSessionStore();

  Future<SeerrSession?> load() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final session = SeerrSession.fromJson(json.decode(raw) as Map<String, dynamic>);
      return session.copyWith(cookie: await CredentialVault.reveal(session.cookie));
    } catch (e, st) {
      appLogger.w('Seerr: failed to decode stored session', error: e, stackTrace: st);
      return null;
    }
  }

  Future<void> save(SeerrSession session) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final protected = session.copyWith(cookie: await CredentialVault.protect(session.cookie));
    await prefs.setString(_key, json.encode(protected.toJson()));
  }

  Future<void> clear() async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(_key);
  }
}

const SeerrSessionStore seerrSessionStore = SeerrSessionStore();
