import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../domain/entities/auth_types.dart';
import '../domain/repositories/auth_ports.dart';
import 'session_store.dart';

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

/// HTTP client for the Klasify auth endpoints.
///
/// The client is stateless apart from the [SessionStore] it reads the bearer
/// token from. Session changes and listener notifications belong to
/// `AuthService`.
class AuthApi implements AuthGateway {
  AuthApi({SessionStore? session, Future<bool> Function()? onTokenExpired})
    : _session = session ?? SessionStore(),
      _onTokenExpired = onTokenExpired ?? _noRefresh;

  static Future<bool> _noRefresh() async => false;

  /// Test hook: when set, every HTTP call goes through this client instead of
  /// a fresh default one. Null in production. (The `@visibleForTesting`
  /// annotation lives on the public `AuthService.testClient` forwarder.)
  static http.Client? testClient;

  static http.Client _client() => testClient ?? http.Client();

  /// Base URL of the sync API. Override at build time:
  ///   flutter run --dart-define=KLASIFY_API_URL=https://api.klasify.app/v1
  ///
  /// Defaults to the XAMPP deployment documented in php-backend/README.md and
  /// the PHP/XAMPP migration plan (Apache serves php-backend/ as
  /// /klasify-api on the dev PC's LAN IP; a phone reaches it over Wi-Fi).
  /// The old Node default (http://localhost:3000/v1) pointed at the retired
  /// Docker stack and made every plain `flutter run` fail to connect.
  static const String _defaultBaseUrl = 'http://192.168.1.67/klasify-api';
  static const String _configuredBaseUrl = String.fromEnvironment(
    'KLASIFY_API_URL',
    defaultValue: _defaultBaseUrl,
  );

  /// Test hook: points requests at a local HTTP server. Null in production.
  /// (The `@visibleForTesting` annotation lives on the public
  /// `AuthService.baseUrlOverride` forwarder.)
  static String? baseUrlOverride;

  /// Release builds must never send credentials or bearer tokens over plain
  /// HTTP. Debug/profile builds keep the LAN default for the demo workflow.
  static String get baseUrl {
    final override = baseUrlOverride;
    // Release builds ignore the test hook, so the HTTPS policy below can
    // never be bypassed by a field that ships in the binary.
    if (!kReleaseMode && override != null) return override;
    if (kReleaseMode && !isSecureApiUrl(_configuredBaseUrl)) {
      throw StateError(
        'Klasify release builds require an HTTPS KLASIFY_API_URL '
        '(configured: $_configuredBaseUrl).',
      );
    }
    return _configuredBaseUrl;
  }

  /// True when [url] is an absolute HTTPS URL with a host. Exposed for tests
  /// so the release policy is pinned without switching build modes. (The
  /// `@visibleForTesting` annotation lives on the AuthService forwarder.)
  static bool isSecureApiUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  final SessionStore _session;
  final Future<bool> Function() _onTokenExpired;

  /// Register a new account. Returns the session payload on success.
  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    String displayName = '',
    String? department,
  }) async {
    final data =
        await send(
              'POST',
              '/auth/register',
              body: {
                'email': email,
                'password': password,
                'display_name': displayName,
                'department': department,
              },
              auth: false,
            )
            as Map<String, dynamic>;
    return AuthResponse.fromJson(data);
  }

  /// Sign in with email + password.
  @override
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final data =
        await send(
              'POST',
              '/auth/login',
              body: {'email': email, 'password': password},
              auth: false,
            )
            as Map<String, dynamic>;
    return AuthResponse.fromJson(data);
  }

  /// Sign in with Google. Never creates an account: a Google identity with
  /// no Klasify account gets ACCOUNT_NOT_FOUND, so the sign-in screen can
  /// point the user at Create account instead of silently provisioning one.
  @override
  Future<AuthResponse> signInWithGoogle() async {
    final idToken = await _googleIdToken();
    final data =
        await send(
              'POST',
              '/auth/google',
              body: {'id_token': idToken, 'mode': 'signin'},
              auth: false,
            )
            as Map<String, dynamic>;
    return AuthResponse.fromJson(data);
  }

  /// Create an account with Google. Name and department come from the
  /// create-account form, not from the Google profile, so the user always
  /// chooses what the school sees.
  @override
  Future<AuthResponse> signUpWithGoogle({
    required String displayName,
    required String department,
  }) async {
    final idToken = await _googleIdToken();
    final data =
        await send(
              'POST',
              '/auth/google',
              body: {
                'id_token': idToken,
                'mode': 'signup',
                'display_name': displayName,
                'department': department,
              },
              auth: false,
            )
            as Map<String, dynamic>;
    return AuthResponse.fromJson(data);
  }

  /// DELETE /auth/account. The caller clears the local session afterwards.
  @override
  Future<void> deleteAccount() async {
    await send('DELETE', '/auth/account');
  }

  /// PATCH /auth/me — partial profile edit. Returns the updated user map.
  /// Throws [AuthApiException] with code EMAIL_EXISTS / VALIDATION_ERROR.
  @override
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
    final data =
        await send('PATCH', '/auth/me', body: body) as Map<String, dynamic>;
    return data['user'] as Map<String, dynamic>;
  }

  /// POST /auth/change-password — verifies the current password server-side.
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await send(
      'POST',
      '/auth/change-password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  /// POST /auth/forgot-password — requests a 6-digit reset code.
  @override
  Future<void> requestPasswordReset({required String email}) async {
    await send(
      'POST',
      '/auth/forgot-password',
      body: {'email': email},
      auth: false,
    );
  }

  /// POST /auth/reset-password — consumes the emailed code (single-use).
  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await send(
      'POST',
      '/auth/reset-password',
      body: {'email': email, 'code': code, 'new_password': newPassword},
      auth: false,
    );
  }

  /// Silent /auth/refresh for [token]. Does not mutate the session store; the
  /// caller applies a successful result and clears on rejection.
  @override
  Future<RefreshResult> refreshToken(String token) async {
    try {
      final res = await _client().post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newToken = data['token'] as String;
        final rawUser = data['user'];
        return RefreshResult.refreshed(
          token: newToken,
          expiresAt: data['expires_at'] as String?,
          user: rawUser is Map<String, dynamic> ? rawUser : null,
        );
      }
    } catch (_) {
      // Network hiccup, server down, or malformed body: keep the session.
      return RefreshResult.unreachable();
    }
    // Rejected (deleted user, revoked identity): end the local session.
    return RefreshResult.rejected();
  }

  /// One API call. On a 401 TOKEN_EXPIRED for the signed-in identity,
  /// silently refreshes once and retries the request.
  Future<dynamic> send(
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
      final refreshed = await _onTokenExpired();
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

  /// Runs the native Google account picker and returns the ID token.
  ///
  /// The picker is forced every time — without `signOut()` google_sign_in
  /// silently re-uses the last account and there's no way to switch or merge.
  Future<String> _googleIdToken() async {
    final googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      // The web client id whose audience the backend accepts (php-backend
      // config.php 'google_client_id'). It must be compiled into the app or
      // google_sign_in returns no ID token at all; builds for a different
      // backend override it with --dart-define=GOOGLE_WEB_CLIENT_ID=...
      serverClientId: const String.fromEnvironment(
        'GOOGLE_WEB_CLIENT_ID',
        defaultValue:
            '359657054360-0v7f3rlt56caci4h78v6kc0me91v2s4m.apps.googleusercontent.com',
      ),
    );
    await googleSignIn.signOut();
    final account = await googleSignIn.signIn();
    if (account == null) {
      throw const AuthApiException(
        'Google sign-in was cancelled',
        code: 'CANCELLED',
      );
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AuthApiException(
        'Could not get Google ID token',
        code: 'VALIDATION_ERROR',
      );
    }
    return idToken;
  }

  Future<dynamic> _attempt(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final stored = await _session.readToken();
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
    final client = _client();
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
