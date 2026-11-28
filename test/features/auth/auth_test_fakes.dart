import 'package:klasify/features/auth/domain/entities/auth_types.dart';
import 'package:klasify/features/auth/domain/repositories/auth_ports.dart';

Map<String, dynamic> authUser(
  int id, {
  String name = 'Ana Reyes',
  String role = 'user',
  String department = 'CCS',
}) => {
  'id': id,
  'display_name': name,
  'email': 'u$id@example.com',
  'role': role,
  'department': department,
};

AuthResponse authResponse(int id, {String token = 'token-1'}) => AuthResponse(
  token: token,
  user: authUser(id),
  expiresAt: '2030-01-01T00:00:00Z',
);

/// Records every gateway call in a shared log so tests can assert ordering.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway(this.log);

  final List<String> log;
  AuthResponse response = authResponse(1);
  RefreshResult refresh = RefreshResult.unreachable();
  Object? deleteError;
  Object? updateError;
  Object? changePasswordError;
  void Function()? onRefresh;

  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    String displayName = '',
    String? department,
  }) async {
    log.add('gateway.register:$email:$displayName:$department');
    return response;
  }

  @override
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    log.add('gateway.login:$email');
    return response;
  }

  @override
  Future<AuthResponse> signInWithGoogle() async {
    log.add('gateway.google-signin');
    return response;
  }

  @override
  Future<AuthResponse> signUpWithGoogle({
    required String displayName,
    required String department,
  }) async {
    log.add('gateway.google-signup:$displayName:$department');
    return response;
  }

  @override
  Future<RefreshResult> refreshToken(String token) async {
    log.add('gateway.refresh:$token');
    onRefresh?.call();
    return refresh;
  }

  @override
  Future<void> deleteAccount() async {
    log.add('gateway.delete');
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? email,
  }) async {
    log.add('gateway.update:$displayName:$email');
    if (updateError != null) throw updateError!;
    return authUser(1, name: displayName ?? 'Ana Reyes');
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    log.add('gateway.change-password');
    if (changePasswordError != null) throw changePasswordError!;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    log.add('gateway.forgot:$email');
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    log.add('gateway.reset:$email:$code');
  }
}

/// In-memory session with failure switches and an optional mid-refresh hook.
class FakeSessionStorage implements SessionStorage {
  FakeSessionStorage(this.log);

  final List<String> log;
  Map<String, dynamic>? user;
  @override
  DateTime? expiresAt;
  String? storedToken;
  bool failSave = false;
  bool failApply = false;
  bool failRestore = false;
  bool failPersistUser = false;
  bool failClear = false;

  @override
  Map<String, dynamic>? get currentUser => user;

  @override
  String? get token => storedToken;

  @override
  Future<bool> restore() async {
    log.add('session.restore');
    if (failRestore) throw StateError('restore failed');
    return storedToken != null;
  }

  @override
  Future<String?> readToken() async {
    log.add('session.read-token');
    return storedToken;
  }

  @override
  Future<void> save({
    required String token,
    required Map<String, dynamic> user,
    String? expiresIso,
  }) async {
    log.add('session.save');
    if (failSave) throw StateError('save failed');
    storedToken = token;
    this.user = {...user, 'token': token};
    expiresAt = expiresIso == null ? null : DateTime.tryParse(expiresIso);
  }

  @override
  Future<void> applyRefresh({
    required String token,
    String? expiresIso,
    Map<String, dynamic>? user,
  }) async {
    log.add('session.apply-refresh');
    if (failApply) throw StateError('apply failed');
    storedToken = token;
    if (user != null) this.user = {...user, 'token': token};
    expiresAt = expiresIso == null ? null : DateTime.tryParse(expiresIso);
  }

  @override
  Future<void> persistUser(Map<String, dynamic> user) async {
    log.add('session.persist-user');
    if (failPersistUser) throw StateError('persist failed');
    this.user = {...user, 'token': storedToken};
  }

  @override
  Future<void> clear() async {
    log.add('session.clear');
    if (failClear) throw StateError('clear failed');
    storedToken = null;
    user = null;
    expiresAt = null;
  }

  @override
  void seed(Map<String, dynamic> user) {
    log.add('session.seed');
    this.user = {...user, 'token': 'test-token'};
    storedToken = 'test-token';
    expiresAt = DateTime.now().add(const Duration(days: 1));
  }
}

class FakeAccountScope implements AccountScope {
  FakeAccountScope(this.log);

  final List<String> log;
  Object? ensureError;
  Object? detachError;

  @override
  Future<void> ensureForUser(int userId) async {
    log.add('scope.ensure:$userId');
    if (ensureError != null) throw ensureError!;
  }

  @override
  Future<void> detachAccount(int userId) async {
    log.add('scope.detach:$userId');
    if (detachError != null) throw detachError!;
  }
}
