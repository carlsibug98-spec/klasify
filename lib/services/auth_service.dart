import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Configurable auth backend client. Defaults to a local dev server;
/// production builds override via --dart-define=KLASIFY_API_URL=...
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Base URL of the sync API. Override at build time:
  ///   flutter run --dart-define=KLASIFY_API_URL=https://api.klasify.app/v1
  static const String _defaultBaseUrl = 'http://localhost:3000/v1';
  static String get baseUrl =>
      const String.fromEnvironment('KLASIFY_API_URL', defaultValue: _defaultBaseUrl);

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'klasify_auth_token';
  static const _userKey = 'klasify_auth_user';

  /// Currently signed-in user, or null if logged out.
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  /// Whether a session exists (token present).
  bool get isLoggedIn => _currentUser != null;

  /// Load any persisted session from secure storage.
  Future<void> restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    if (token != null && userJson != null) {
      try {
        _currentUser = jsonDecode(userJson) as Map<String, dynamic>;
        _currentUser!['token'] = token;
      } catch (_) {
        await _clearSession();
      }
    }
  }

  /// Register a new account. Returns the user map on success, throws on failure.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'display_name': displayName,
      }),
    );
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await _saveSession(data);
      return data['user'] as Map<String, dynamic>;
    }
    throw _parseError(res);
  }

  /// Sign in with email + password.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await _saveSession(data);
      return data['user'] as Map<String, dynamic>;
    }
    throw _parseError(res);
  }

  /// Sign out: clear local session (server session expires naturally).
  Future<void> logout() async {
    await _clearSession();
  }

  /// Delete the account and all server-side data.
  Future<void> deleteAccount() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return;
    await http.delete(
      Uri.parse('$baseUrl/auth/account'),
      headers: {'Authorization': 'Bearer $token'},
    );
    await _clearSession();
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final token = data['token'] as String;
    final user = data['user'] as Map<String, dynamic>;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
    _currentUser = {...user, 'token': token};
  }

  Future<void> _clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    _currentUser = null;
  }

  Exception _parseError(http.Response res) {
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return Exception(data['error'] ?? 'Request failed (${res.statusCode})');
    } catch (_) {
      return Exception('Request failed (${res.statusCode})');
    }
  }
}
