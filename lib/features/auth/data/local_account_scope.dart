import '../../../services/local_scope_service.dart';
import '../domain/repositories/auth_ports.dart';

/// Adapts the app-wide scope service to the auth port.
///
/// Kept here so `LocalScopeService` does not have to depend on a feature
/// folder, and auth tests can swap a fake scope without touching files.
class LocalAccountScope implements AccountScope {
  const LocalAccountScope(this._scope);

  final LocalScopeService _scope;

  @override
  Future<void> ensureForUser(int userId) => _scope.ensureForUser(userId);

  @override
  Future<void> detachAccount(int userId) => _scope.detachAccount(userId);
}
