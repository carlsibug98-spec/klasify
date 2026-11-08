import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Typed auth API error: the backend message plus its semantic code, so
/// screens can branch on codes (EMAIL_EXISTS, INVALID_CREDENTIALS, ...)
/// without parsing strings. `toString()` returns the message only.
class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.code = 'UNKNOWN', this.statusCode = 0});
  final String message;
  final String code;
  final int statusCode;

  @override
  String toString() => message;
}

class _RetryAfterRefresh {
  const _RetryAfterRefresh();
}

/// Marker returned by [_attempt] when a 401 TOKEN_EXPIRED hit the signed-in
/// identity and one silent refresh + retry should happen.
const _retryMarker = _RetryAfterRefresh();

/// Marker for 204-style responses with an empty body.
class _NoContent {
  const _NoContent();
}

const _noContent = _NoContent();

/// Configurable auth backend client. Defaults to a local dev server;
/// production builds override via --dart-define=KLASIFY_API_URL=...
///
/// Also a ChangeNotifier: sign-in/out, profile edits and session refreshes
/// notify listeners so the Profile tab stays live without polling.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Test hook: when set, every HTTP call the service makes goes through
  /// this client instead of a fresh default one. Null in production.
  @visibleForTesting
  static http.Client? testClient;

  http.Client get _http => testClient ?? http.Client();

  /// Base URL of the sync API. Override at build time:
  ///   flutter run --dart-define=KLASIFY_API_URL=https://api.klasify.app/v1
  static const String _defaultBaseUrl = 'http://localhost:3000/v1';
  static String get baseUrl =>
      const String.fromEnvironment('KLASIFY_API_URL', defaultValue: _defaultBaseUrl);

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'klasify_auth_token';
  static const _userKey = 'klasify_auth_user';
  static const _expiresKey = 'klasify_auth_expires_at';

  /// Currently signed-in user, or null if logged out. Carries the token
  /// under the 'token' key in memory (never re-persisted inside the user
  /// JSON — the token has its own storage key).
  Map<String, dynamic>? _currentUser;
  DateTime? _expiresAt;

  Map<String, dynamic>? get currentUser => _currentUser;

  /// Whether a session exists (token present).
  bool get isLoggedIn => _currentUser != null;

  /// Convenience getters for the profile UI.
  String? get displayName => _currentUser?['display_name'] as String?;
  String? get userEmail => _currentUser?['email'] as String?;

  /// The session token, or null when signed out.
  String? get token => _currentUser?['token'] as String?;

  /// Whether the JWT is known-expired or expires within 10 minutes. Sessions
  /// restored without a stored expiry (old installs) count as "refresh me".
  bool get _shouldRefresh {
    final expiry = _expiresAt;
    if (expiry == null) return true;
    return expiry.isBefore(DateTime.now().add(const Duration(minutes: 10)));
  }

  /// Load any persisted session from secure storage.
  Future<void> restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    final expiresIso = await _storage.read(key: _expiresKey);
    _expiresAt = expiresIso == null ? null : DateTime.tryParse(expiresIso);
    if (token != null && userJson != null) {
      try {
        _currentUser = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUser!['token'] = token;
      } catch (_) {
        await _clearSession();
      }
    }
    notifyListeners();
  }

  /// Register a new account. Returns the user map on success, throws on failure.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    final data = await _api(
      'POST',
      '/auth/register',
      body: {'email': email, 'password': password, 'display_name': displayName},
      auth: false,
    ) as Map<String, dynamic>;
    await _saveSession(data);
    return data['user'] as Map<String, dynamic>;
  }

  /// Sign in with email + password.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final data = await _api(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
      auth: false,
    ) as Map<String, dynamic>;
    await _saveSession(data);
    return data['user'] as Map<String, dynamic>;
  }

  /// Sign out: clear local session (server session expires naturally).
  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  /// Delete the account and all server-side data, then clear the session.
  /// Local schedule data on the phone stays, as decided.
  Future<void> deleteAccount() async {
    try {
      await _api('DELETE', '/auth/account');
    } finally {
      await _clearSession();
      notifyListeners();
    }
  }

  /// PATCH /auth/me — partial profile edit. Returns the updated user map.
  /// Throws [AuthApiException] with code EMAIL_EXISTS / VALIDATION_ERROR.
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? email,
  }) async {
    final body = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (email != null) 'email': email,
    };
    if (body.isEmpty) {
      throw const AuthApiException(
        'Nothing to update',
        code: 'VALIDATION_ERROR',
      );
    }
    final data = await _api('PATCH', '/auth/me', body: body) as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>;
    await _persistUser(user);
    notifyListeners();
    return user;
  }

  /// POST /auth/change-password — verifies the current password server-side.
  /// Throws AuthApiException (INVALID_CREDENTIALS / VALIDATION_ERROR).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api('POST', '/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// POST /auth/forgot-password — requests a 6-digit reset code. Responds
  /// 200 whether or not the email is registered, so the UI shows the same
  /// message either way. Throws AuthApiException (VALIDATION_ERROR 422,
  /// RATE_LIMITED 429).
  Future<void> requestPasswordReset({required String email}) async {
    await _api('POST', '/auth/forgot-password', body: {'email': email}, auth: false);
  }

  /// POST /auth/reset-password — consumes the emailed code (single-use) and
  /// sets the new password. Throws with "invalid or expired" otherwise.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _api(
      'POST',
      '/auth/reset-password',
      body: {'email': email, 'code': code, 'new_password': newPassword},
      auth: false,
    );
  }

  /// Silent /auth/refresh. Calls the refresh endpoint with the current
  /// token (the server accepts it within a grace window even when expired)
  /// and persists the new token. Returns true when a fresh token is in
  /// place; false (after clearing the session) when the token is rejected.
  Future<bool> refreshSession() async {
    final stored = await _storage.read(key: _tokenKey);
    if (stored == null) return false;
    try {
      final res = await _http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Authorization': 'Bearer $stored'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newToken = data['token'] as String;
        await _storage.write(key: _tokenKey, value: newToken);
        final expiresIso = data['expires_at'] as String?;
        _expiresAt = expiresIso == null ? null : DateTime.tryParse(expiresIso);
        if (expiresIso != null) {
          await _storage.write(key: _expiresKey, value: expiresIso);
        }
        _currentUser?['token'] = newToken;
        notifyListeners();
        return true;
      }
    } catch (_) {
      // Network hiccup or server down: keep the session, callers retry.
      return false;
    }
    // Rejected (deleted user, revoked identity): end the local session.
    await _clearSession();
    notifyListeners();
    return false;
  }

  /// Refresh-on-expiry for callers about to send an authorized request.
  Future<void> ensureFreshToken() async {
    if (!isLoggedIn || !_shouldRefresh) return;
    await refreshSession();
  }

  /// Widget-test hook: plants a session in memory only (nothing persists),
  /// so screens can render and respond to the signed-in state.
  @visibleForTesting
  void debugSeedSession({required Map<String, dynamic> user}) {
    _currentUser = {...user, 'token': 'test-token'};
    _expiresAt = DateTime.now().add(const Duration(days: 1));
    notifyListeners();
  }

  // ----------------------------------------------------------------------

  /// One API call. On a 401 TOKEN_EXPIRED for the signed-in identity,
  /// silently refreshes once and retries the request.
  Future<dynamic> _api(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    dynamic payload = await _attempt(method, path, body: body, auth: auth);
    if (identical(payload, _retryMarker)) {
      if (!auth) {
        throw const AuthApiException(
          'Session expired, please sign in again',
          code: 'TOKEN_EXPIRED',
          statusCode: 401,
        );
      }
      final refreshed = await refreshSession();
      if (!refreshed) {
        throw const AuthApiException(
          'Session expired, please sign in again',
          code: 'TOKEN_EXPIRED',
          statusCode: 401,
        );
      }
      payload = await _attempt(method, path, body: body, auth: auth);
      if (identical(payload, _retryMarker)) {
        throw const AuthApiException(
          'Session expired, please sign in again',
          code: 'TOKEN_EXPIRED',
          statusCode: 401,
        );
      }
    }
    return payload;
  }

  Future<dynamic> _attempt(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final stored = await _storage.read(key: _tokenKey);
      if (stored == null) {
        throw const AuthApiException(
          'Not signed in',
          code: 'UNAUTHORIZED',
          statusCode: 401,
        );
      }
      headers['Authorization'] = 'Bearer $stored';
    }
    final uri = Uri.parse('$baseUrl$path');
    final client = _http;
    final http.Response res;
    if (method == 'PATCH') {
      res = await client.patch(uri, headers: headers, body: jsonEncode(body));
    } else if (method == 'DELETE') {
      res = await client.delete(uri, headers: headers);
    } else if (method == 'GET') {
      res = await client.get(uri, headers: headers);
    } else {
      res = await client.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return _noContent;
      return jsonDecode(res.body);
    }

    final err = _errorFrom(res);
    if (res.statusCode == 401 && auth && err.code == 'TOKEN_EXPIRED') {
      return _retryMarker;
    }
    throw err;
  }

  /// Keeps the in-memory user in sync and rewrites the stored user JSON.
  Future<void> _persistUser(Map<String, dynamic> user) async {
    if (_currentUser != null) {
      _currentUser!['display_name'] = user['display_name'];
      _currentUser!['email'] = user['email'];
    }
    final bare = {...user}..remove('token');
    await _storage.write(key: _userKey, value: jsonEncode(bare));
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final token = data['token'] as String;
    final user = data['user'] as Map<String, dynamic>;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
    final expiresIso = data['expires_at'] as String?;
    if (expiresIso != null) {
      _expiresAt = DateTime.tryParse(expiresIso);
      await _storage.write(key: _expiresKey, value: expiresIso);
    }
    _currentUser = {...user, 'token': token};
    notifyListeners();
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _expiresKey);
    _currentUser = null;
    _expiresAt = null;
  }

  AuthApiException _errorFrom(http.Response res) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return AuthApiException(
        data['error'] as String? ?? 'Request failed (${res.statusCode})',
        code: data['code'] as String? ?? 'UNKNOWN',
        statusCode: res.statusCode,
      );
    } catch (_) {
      return AuthApiException(
        'Request failed (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
  }
}
