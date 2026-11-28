import 'package:flutter/foundation.dart';

import '../features/sync/application/pull_sync.dart';
import '../features/sync/application/push_sync.dart';
import '../features/sync/application/sync_now.dart';
import '../features/sync/data/auth_sync_session.dart';
import '../features/sync/data/http_sync_gateway.dart';
import '../features/sync/data/sqlite_sync_store.dart';
import '../features/sync/presentation/sync_controller.dart';
import 'auth_service.dart';

export '../features/sync/data/sync_wire_mapper.dart' show buildStatusPushRow;

/// Configurable sync backend client.
///
/// This class is the composition root and the compatibility facade for the
/// sync feature. The rules live in `features/sync/application`, the adapters in
/// `features/sync/data`, and the cadence in `features/sync/presentation`.
/// Screens keep calling the same API they always have.
class SyncService extends ChangeNotifier {
  SyncService._() {
    final session = AuthSyncSession();
    final store = SqliteSyncStore();
    _queue = store;
    final gateway = HttpSyncGateway(baseUrl: () => AuthService.baseUrl);
    final push = PushSync(store: store, gateway: gateway, session: session);
    final pull = PullSync(store: store, gateway: gateway, session: session);
    _controller = SyncController(
      push: push,
      pull: pull,
      syncNow: SyncNow(push: push, pull: pull),
      session: session,
      autoStart: () => SyncService.autoStartEnabled,
    );
    _controller.addListener(_forward);
  }

  static final SyncService instance = SyncService._();

  static String get baseUrl => AuthService.baseUrl;

  /// Test hook: when false, signing in does not start the background cadence
  /// or trigger an immediate sync.
  @visibleForTesting
  static bool autoStartEnabled = true;

  late final SqliteSyncStore _queue;

  late final SyncController _controller;

  void _forward() => notifyListeners();

  bool get syncing => _controller.syncing;
  String? get lastError => _controller.lastError;
  DateTime? get lastSyncAt => _controller.lastSyncAt;

  /// Older server rows skipped by the last pull in favour of newer local edits.
  int get lastConflictCount => _controller.lastConflictCount;

  /// Local rows waiting for the next push.
  Future<int> pendingChangeCount() => _queue.pendingChangeCount();

  Future<bool> push() => _controller.push();

  Future<bool> pull() => _controller.pull();

  /// Full sync: push then pull. The pull is skipped when the push fails.
  Future<bool> syncNow() => _controller.syncNow();

  /// Boot hook: constructing the singleton wires the auth listener so a
  /// restored session starts the timer without opening Settings.
  void ensureStarted() {}

  @override
  void dispose() {
    _controller.removeListener(_forward);
    _controller.dispose();
    super.dispose();
  }
}
