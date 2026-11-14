import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/auth/admin_api.dart';
import '../features/auth/auth_api.dart';
import '../features/auth/session_store.dart';

export '../features/auth/auth_api.dart' show AuthApiException;

/// Configurable auth backend client and session controller.
///
/// This facade keeps the public API screens already use. Persistence lives in
/// `SessionStore`, auth HTTP in `AuthApi`, and admin HTTP in `AdminApi`, so the
/// security boundary can be reviewed without reading UI-facing state code.
///
/// Also a ChangeNotifier: sign-in/out, profile edits and session refreshes
/// notify listeners so the Profile tab stays live without polling.
class AuthService extends ChangeNotifier {
  AuthService._() {
    _api = AuthApi(session: _session, onTokenExpired: refreshSession);
    _admin = AdminApi(_api);
  }
  static final AuthService instance = AuthService._();

  final _session = SessionStore();
  late final AuthApi _api;
  late final AdminApi _admin;

  /// Test hook: when set, every HTTP call the service makes goes through
  /// this client instead of a fresh default one. Null in production.
  @visibleForTesting
  static http.Client? get testClient => AuthApi.testClient;
  static set testClient(http.Client? client) => AuthApi.testClient = client;

  /// Base URL of the sync API. Override at build time:
  ///   flutter run --dart-define=KLASIFY_API_URL=https://api.klasify.app/v1
  static String get baseUrl => AuthApi.baseUrl;

  /// True when [url] is an absolute HTTPS URL with a host. Exposed for tests
  /// so the release policy is pinned without switching build modes.
  @visibleForTesting
  static bool isSecureApiUrl(String url) => AuthApi.isSecureApiUrl(url);

  /// Currently signed-in user, or null if logged out. Carries the token
  /// under the 'token' key in memory (never re-persisted inside the user
  /// JSON — the token has its own storage key).
  Map<String, dynamic>? get currentUser => _session.currentUser;

  /// Whether a session exists (token present).
  bool get isLoggedIn => _session.currentUser != null;

  /// Convenience getters for the profile UI.
  String? get displayName => _session.currentUser?['display_name'] as String?;
  String? get userEmail => _session.currentUser?['email'] as String?;
  String get userRole => _session.currentUser?['role'] as String? ?? 'user';
  String? get userDepartment => _session.currentUser?['department'] as String?;
  bool get isAdmin => userRole == 'admin' || userRole == 'super_admin';
  bool get isSuperAdmin => userRole == 'super_admin';

  /// The session token, or null when signed out.
  String? get token => _session.token;

  /// Whether the JWT is known-expired or expires within 10 minutes. Sessions
  /// restored without a stored expiry (old installs) count as "refresh me".
  bool get _shouldRefresh {
    final expiry = _session.expiresAt;
    if (expiry == null) return true;
    return expiry.isBefore(DateTime.now().add(const Duration(minutes: 10)));
  }

  /// Load any persisted session from secure storage.
  Future<void> restoreSession() async {
    final restored = await _session.restore();
    if (restored) {
      // Refresh once per cold start so a promotion, demotion, or department
      // change made on another device lands without a sign-out. Offline
      // restores keep the stored session (refreshSession swallows network
      // errors); only a rejected token clears it.
      unawaited(refreshSession());
    }
    notifyListeners();
  }

  /// Register a new account. Returns the user map on success, throws on failure.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String displayName = '',
    String? department,
  }) async {
    final response = await _api.register(
      email: email,
      password: password,
      displayName: displayName,
      department: department,
    );
    await _applySignIn(response);
    return response.user;
  }

  /// Sign in with email + password.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.login(email: email, password: password);
    await _applySignIn(response);
    return response.user;
  }

  /// Sign in with Google. Never creates an account: a Google identity with
  /// no Klasify account gets ACCOUNT_NOT_FOUND, so the sign-in screen can
  /// point the user at Create account instead of silently provisioning one.
  Future<Map<String, dynamic>> signInWithGoogle() async {
    final response = await _api.signInWithGoogle();
    await _applySignIn(response);
    return response.user;
  }

  /// Create an account with Google. Name and department come from the
  /// create-account form, not from the Google profile, so the user always
  /// chooses what the school sees.
  Future<Map<String, dynamic>> signUpWithGoogle({
    required String displayName,
    required String department,
  }) async {
    final response = await _api.signUpWithGoogle(
      displayName: displayName,
      department: department,
    );
    await _applySignIn(response);
    return response.user;
  }

  /// Sign out: clear local session (server session expires naturally).
  Future<void> logout() async {
    await _session.clear();
    notifyListeners();
  }

  /// Admin: list users (scoped by caller's role/department on the server).
  Future<List<Map<String, dynamic>>> adminGetUsers() => _admin.getUsers();

  /// Admin: promote/demote a user (super_admin only).
  Future<void> adminSetRole(int userId, String role) =>
      _admin.setRole(userId, role);

  /// Admin: assign a user to a department (super_admin only).
  Future<void> adminSetDepartment(int userId, String? department) =>
      _admin.setDepartment(userId, department);

  /// Admin: list office statuses (scoped by caller's role/department).
  Future<List<Map<String, dynamic>>> adminGetOfficeStatuses() =>
      _admin.getOfficeStatuses();

  /// Admin: update an office's status.
  Future<void> adminSetOfficeStatus(
    String office,
    String status, {
    String? customMessage,
    String? department,
  }) => _admin.setOfficeStatus(
    office,
    status,
    customMessage: customMessage,
    department: department,
  );

  /// Admin: create a new school-wide office (super_admin only). Returns the
  /// created row (same shape as adminGetOfficeStatuses rows).
  Future<Map<String, dynamic>> adminAddOffice(String name) =>
      _admin.addOffice(name);

  /// Admin: rename an office (super_admin only). The old key disappears at
  /// every phone's next sync; availability and note carry over.
  Future<void> adminRenameOffice(String office, String newName) =>
      _admin.renameOffice(office, newName);

  /// Admin: retire an office (super_admin only). Soft delete: students lose
  /// it at their next sync; the record stays on the server.
  Future<void> adminRetireOffice(String office) => _admin.retireOffice(office);

  /// Local schedule data on the phone stays, as decided.
  Future<void> deleteAccount() async {
    try {
      await _api.deleteAccount();
    } finally {
      await _session.clear();
      notifyListeners();
    }
  }

  /// PATCH /auth/me — partial profile edit. Returns the updated user map.
  /// Throws [AuthApiException] with code EMAIL_EXISTS / VALIDATION_ERROR.
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? email,
  }) async {
    final user = await _api.updateProfile(
      displayName: displayName,
      email: email,
    );
    await _session.persistUser(user);
    notifyListeners();
    return user;
  }

  /// POST /auth/change-password — verifies the current password server-side.
  /// Throws AuthApiException (INVALID_CREDENTIALS / VALIDATION_ERROR).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    // The server bumps token_version, which revokes this token as well.
    // Drop the local session instead of leaving the UI in a half-signed-in
    // state that fails on the next request.
    await _session.clear();
    notifyListeners();
  }

  /// POST /auth/forgot-password — requests a 6-digit reset code. Responds
  /// 200 whether or not the email is registered, so the UI shows the same
  /// message either way. Throws AuthApiException (VALIDATION_ERROR 422,
  /// RATE_LIMITED 429).
  Future<void> requestPasswordReset({required String email}) =>
      _api.requestPasswordReset(email: email);

  /// POST /auth/reset-password — consumes the emailed code (single-use) and
  /// sets the new password. Throws with "invalid or expired" otherwise.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) => _api.confirmPasswordReset(
    email: email,
    code: code,
    newPassword: newPassword,
  );

  /// Silent /auth/refresh. Calls the refresh endpoint with the current
  /// token (the server accepts it within a grace window even when expired)
  /// and persists the new token. Returns true when a fresh token is in
  /// place; false (after clearing the session) when the token is rejected.
  Future<bool> refreshSession() async {
    final stored = await _session.readToken();
    if (stored == null) return false;
    final result = await _api.refreshToken(stored);
    switch (result.outcome) {
      case RefreshOutcome.unreachable:
        // Network hiccup or server down: keep the session, callers retry.
        return false;
      case RefreshOutcome.rejected:
        // Rejected (deleted user, revoked identity): end the local session.
        await _session.clear();
        notifyListeners();
        return false;
      case RefreshOutcome.refreshed:
        try {
          await _session.applyRefresh(
            token: result.token!,
            expiresIso: result.expiresAt,
            user: result.user,
          );
        } catch (_) {
          // Preserve the original contract: a storage failure is treated like
          // any other refresh failure and keeps the existing session.
          return false;
        }
        notifyListeners();
        return true;
    }
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
    _session.seed(user);
    notifyListeners();
  }

  /// Persists a successful sign-in and notifies once.
  Future<void> _applySignIn(AuthResponse response) async {
    await _session.save(
      token: response.token,
      user: response.user,
      expiresIso: response.expiresAt,
    );
    notifyListeners();
  }
}
