import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../features/auth/application/change_password.dart';
import '../features/auth/application/delete_account.dart';
import '../features/auth/application/refresh_session.dart';
import '../features/auth/application/sign_in.dart';
import '../features/auth/application/update_profile.dart';
import '../features/auth/data/admin_api.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/local_account_scope.dart';
import '../features/auth/data/session_store.dart';
import '../features/auth/domain/entities/auth_policy.dart';
import '../features/auth/domain/entities/auth_types.dart';
import 'local_scope_service.dart';

export '../features/auth/domain/entities/auth_types.dart' show AuthApiException;

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
    final scope = LocalAccountScope(LocalScopeService.instance);
    _signIn = SignIn(gateway: _api, session: _session, scope: scope);
    _refresh = RefreshSession(gateway: _api, session: _session);
    _delete = DeleteAccount(gateway: _api, session: _session, scope: scope);
    _updateProfile = UpdateProfile(gateway: _api, session: _session);
    _changePassword = ChangePassword(gateway: _api, session: _session);
  }
  static final AuthService instance = AuthService._();

  final _session = SessionStore();
  late final AuthApi _api;
  late final AdminApi _admin;
  late final SignIn _signIn;
  late final RefreshSession _refresh;
  late final DeleteAccount _delete;
  late final UpdateProfile _updateProfile;
  late final ChangePassword _changePassword;

  /// Test hook: when set, every HTTP call the service makes goes through
  /// this client instead of a fresh default one. Null in production.
  @visibleForTesting
  static http.Client? get testClient => AuthApi.testClient;
  static set testClient(http.Client? client) => AuthApi.testClient = client;

  /// Base URL of the sync API. Override at build time:
  ///   flutter run --dart-define=KLASIFY_API_URL=https://api.klasify.app/v1
  static String get baseUrl => AuthApi.baseUrl;

  /// Test hook: routes requests to a local HTTP server. Null in production.
  @visibleForTesting
  static String? get baseUrlOverride => AuthApi.baseUrlOverride;
  @visibleForTesting
  static set baseUrlOverride(String? value) => AuthApi.baseUrlOverride = value;

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
  }) => _completeSignIn(
    () => _signIn.register(
      email: email,
      password: password,
      displayName: displayName,
      department: department,
    ),
  );

  /// Sign in with email + password.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) => _completeSignIn(
    () => _signIn.login(email: email, password: password),
  );

  /// Sign in with Google. Never creates an account: a Google identity with
  /// no Klasify account gets ACCOUNT_NOT_FOUND, so the sign-in screen can
  /// point the user at Create account instead of silently provisioning one.
  Future<Map<String, dynamic>> signInWithGoogle() =>
      _completeSignIn(_signIn.signInWithGoogle);

  /// Create an account with Google. Name and department come from the
  /// create-account form, not from the Google profile, so the user always
  /// chooses what the school sees.
  Future<Map<String, dynamic>> signUpWithGoogle({
    required String displayName,
    required String department,
  }) => _completeSignIn(
    () => _signIn.signUpWithGoogle(
      displayName: displayName,
      department: department,
    ),
  );

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

  /// Deletes the server account, then returns its schedule to the local
  /// scope.
  ///
  /// The local schedule stays, as decided. On a failed delete nothing changes
  /// locally and the session is kept, so the user can retry.
  Future<void> deleteAccount() async {
    final userId = await _delete.deleteServerAccount();
    notifyListeners();

    if (userId != null) {
      try {
        await _delete.detach(userId);
      } catch (error, stack) {
        debugPrint('Local detach after account deletion failed: $error\n$stack');
      }
    }
  }

  /// PATCH /auth/me — partial profile edit. Returns the updated user map.
  /// Throws [AuthApiException] with code EMAIL_EXISTS / VALIDATION_ERROR.
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? email,
  }) async {
    final user = await _updateProfile(displayName: displayName, email: email);
    notifyListeners();
    return user;
  }

  /// POST /auth/change-password — verifies the current password server-side.
  /// Throws AuthApiException (INVALID_CREDENTIALS / VALIDATION_ERROR).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
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
    final status = await _refresh();

    switch (status) {
      case SessionRefreshStatus.refreshed:
        notifyListeners();
        return true;
      case SessionRefreshStatus.rejected:
        notifyListeners();
        return false;
      case SessionRefreshStatus.noSession:
      case SessionRefreshStatus.unreachable:
      case SessionRefreshStatus.superseded:
      case SessionRefreshStatus.storageFailed:
        return false;
    }
  }

  /// Refresh-on-expiry for callers about to send an authorized request.
  Future<void> ensureFreshToken() async {
    if (!isLoggedIn ||
        !shouldRefreshSession(_session.expiresAt, DateTime.now())) {
      return;
    }
    await refreshSession();
  }

  /// Widget-test hook: plants a session in memory only (nothing persists),
  /// so screens can render and respond to the signed-in state.
  @visibleForTesting
  void debugSeedSession({required Map<String, dynamic> user}) {
    _session.seed(user);
    notifyListeners();
  }

  /// Runs a sign-in use case, converts a scope failure, and notifies once.
  Future<Map<String, dynamic>> _completeSignIn(
    Future<Map<String, dynamic>> Function() run,
  ) async {
    try {
      final user = await run();
      notifyListeners();
      return user;
    } on AuthScopeException catch (error) {
      debugPrint(
        'Local scope switch failed: ${error.error}\n${error.stack}',
      );
      throw const AuthApiException(
        "Couldn't open the local schedule on this phone. Try again.",
        code: 'LOCAL_SCOPE_FAILED',
      );
    }
  }
}
