import '../entities/auth_types.dart';

/// Auth endpoints the sign-in and session use cases need.
///
/// Implemented over HTTP. The 401 refresh-and-retry stays inside the adapter;
/// the application layer only sees the final response or error.
abstract interface class AuthGateway {
  Future<AuthResponse> register({
    required String email,
    required String password,
    String displayName,
    String? department,
  });

  Future<AuthResponse> login({
    required String email,
    required String password,
  });

  Future<AuthResponse> signInWithGoogle();

  Future<AuthResponse> signUpWithGoogle({
    required String displayName,
    required String department,
  });

  Future<RefreshResult> refreshToken(String token);

  Future<void> deleteAccount();

  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? email,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<void> requestPasswordReset({required String email});

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });
}

/// The persisted session. Implemented over secure storage.
abstract interface class SessionStorage {
  Map<String, dynamic>? get currentUser;
  DateTime? get expiresAt;
  String? get token;

  Future<bool> restore();
  Future<String?> readToken();

  Future<void> save({
    required String token,
    required Map<String, dynamic> user,
    String? expiresIso,
  });

  Future<void> applyRefresh({
    required String token,
    String? expiresIso,
    Map<String, dynamic>? user,
  });

  Future<void> persistUser(Map<String, dynamic> user);
  Future<void> clear();

  /// Widget-test hook: plants a session in memory only (nothing persists).
  void seed(Map<String, dynamic> user);
}

/// The local account scope a signed-in user owns.
abstract interface class AccountScope {
  Future<void> ensureForUser(int userId);
  Future<void> detachAccount(int userId);
}
