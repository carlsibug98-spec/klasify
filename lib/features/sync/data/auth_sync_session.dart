import 'package:flutter/foundation.dart';

import '../../../data/app_database.dart';
import '../../../services/auth_service.dart';
import '../../../services/local_scope_service.dart';
import '../domain/repositories/sync_ports.dart';

/// The auth and account-scope implementation of [SyncSession].
///
/// The ordering in [writeIfCurrent] is the data-loss guard: check the
/// generation, wait out a switch in progress, check again, then write.
class AuthSyncSession implements SyncSession {
  @override
  int? get userId {
    final id = AuthService.instance.currentUser?['id'];
    return id is int ? id : null;
  }

  @override
  bool get isLoggedIn => AuthService.instance.isLoggedIn;

  @override
  Future<String?> freshToken() async {
    if (!AuthService.instance.isLoggedIn) return null;
    // Silent refresh when the JWT is expired or close to it, so the request
    // does not bounce on TOKEN_EXPIRED.
    await AuthService.instance.ensureFreshToken();
    return AuthService.instance.token;
  }

  @override
  Future<bool> pinScope(int? userId) async {
    final scope = LocalScopeService.instance;
    try {
      await scope.ensureForUser(userId);
    } catch (error) {
      debugPrint('Sync could not open the local scope: $error');
      return false;
    }
    if (scope.switching) {
      debugPrint('Sync skipped: the local scope is changing.');
      return false;
    }
    if (scope.syncBlocked) {
      debugPrint('Sync skipped: the local scope is blocked.');
      return false;
    }
    return true;
  }

  @override
  int get scopeGeneration => LocalScopeService.instance.generation;

  @override
  Future<bool> writeIfCurrent(
    int generation,
    Future<void> Function() write,
  ) async {
    final scope = LocalScopeService.instance;
    if (scope.generation != generation) return false;
    await AppDatabase.instance.database;
    if (scope.generation != generation) return false;
    await write();
    return true;
  }

  @override
  void addSessionListener(void Function() listener) =>
      AuthService.instance.addListener(listener);

  @override
  void removeSessionListener(void Function() listener) =>
      AuthService.instance.removeListener(listener);
}
