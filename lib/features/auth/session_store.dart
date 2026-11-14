import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns the persisted session: secure-storage keys, the in-memory user map,
/// and the JWT expiry.
///
/// This class performs no HTTP and never notifies listeners; [AuthService]
/// decides when a storage change becomes a UI event.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'klasify_auth_token';
  static const _userKey = 'klasify_auth_user';
  static const _expiresKey = 'klasify_auth_expires_at';

  /// Currently signed-in user, or null if logged out. Carries the token
  /// under the 'token' key in memory (never re-persisted inside the user
  /// JSON — the token has its own storage key).
  Map<String, dynamic>? _currentUser;
  DateTime? _expiresAt;

  Map<String, dynamic>? get currentUser => _currentUser;
  DateTime? get expiresAt => _expiresAt;
  String? get token => _currentUser?['token'] as String?;

  /// Loads any persisted session from secure storage.
  ///
  /// Returns true when a token and user were restored. A corrupt user payload
  /// clears the session; missing keys simply leave the store empty. The
  /// caller still notifies listeners in every case.
  Future<bool> restore() async {
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    final expiresIso = await _storage.read(key: _expiresKey);
    _expiresAt = expiresIso == null ? null : DateTime.tryParse(expiresIso);
    if (token == null || userJson == null) return false;
    try {
      final user = jsonDecode(userJson) as Map<String, dynamic>;
      _currentUser = {...user, 'token': token};
      return true;
    } catch (_) {
      await clear();
      return false;
    }
  }

  /// Returns the stored token without touching the in-memory user.
  ///
  /// Authorized requests read the token from storage rather than
  /// [_currentUser], so a debug-seeded session still behaves like the real
  /// thing: it can render the UI but cannot call the API until it is persisted.
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  /// Persists a successful sign-in/register response.
  Future<void> save({
    required String token,
    required Map<String, dynamic> user,
    String? expiresIso,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
    if (expiresIso != null) {
      _expiresAt = DateTime.tryParse(expiresIso);
      await _storage.write(key: _expiresKey, value: expiresIso);
    }
    _currentUser = {...user, 'token': token};
  }

  /// Applies a successful silent refresh: new token, new expiry, optional
  /// refreshed user payload.
  Future<void> applyRefresh({
    required String token,
    String? expiresIso,
    Map<String, dynamic>? user,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    _expiresAt = expiresIso == null ? null : DateTime.tryParse(expiresIso);
    if (expiresIso != null) {
      await _storage.write(key: _expiresKey, value: expiresIso);
    }
    _currentUser?['token'] = token;
    if (user != null) await persistUser(user);
  }

  /// Keeps the in-memory user in sync and rewrites the stored user JSON.
  Future<void> persistUser(Map<String, dynamic> user) async {
    if (_currentUser != null) {
      // Merge every server-owned field (name, email, role, department) so
      // a promotion or department change lands without a fresh sign-in.
      for (final entry in user.entries) {
        if (entry.key != 'token') _currentUser![entry.key] = entry.value;
      }
    }
    final bare = {...user}..remove('token');
    await _storage.write(key: _userKey, value: jsonEncode(bare));
  }

  /// Deletes every persisted session key and the in-memory copy.
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _expiresKey);
    _currentUser = null;
    _expiresAt = null;
  }

  /// Widget-test hook: plants a session in memory only (nothing persists).
  void seed(Map<String, dynamic> user) {
    _currentUser = {...user, 'token': 'test-token'};
    _expiresAt = DateTime.now().add(const Duration(days: 1));
  }
}
