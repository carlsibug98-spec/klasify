import 'dart:async';

import 'package:flutter/foundation.dart';

import '../application/pull_sync.dart';
import '../application/push_sync.dart';
import '../application/sync_now.dart';
import '../domain/entities/sync_result.dart';
import '../domain/repositories/sync_ports.dart';

/// Owns the sync cadence and the observable state screens can watch.
///
/// It depends only on application use cases and the session port. The concrete
/// HTTP, SQLite, and auth adapters are wired by the composition root in
/// `services/sync_service.dart`.
class SyncController extends ChangeNotifier {
  factory SyncController({
    required PushSync push,
    required PullSync pull,
    required SyncNow syncNow,
    required SyncSession session,
    required bool Function() autoStart,
  }) => SyncController._(push, pull, syncNow, session, autoStart);

  SyncController._(
    this._push,
    this._pull,
    this._syncNow,
    this._session,
    this._autoStart,
  ) {
    _session.addSessionListener(_onSessionChanged);
    _onSessionChanged();
  }

  final PushSync _push;
  final PullSync _pull;
  final SyncNow _syncNow;
  final SyncSession _session;
  final bool Function() _autoStart;

  bool _syncing = false;
  bool get syncing => _syncing;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Server rows skipped in the last successful pull because this phone had
  /// a newer edit. Reset to zero on the next clean run.
  int _lastConflictCount = 0;
  int get lastConflictCount => _lastConflictCount;

  Timer? _backgroundTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _sessionActive = false;

  Future<bool> push() => _run(_push.call);

  Future<bool> pull() => _run(_pull.call);

  Future<bool> syncNow() => _run(_syncNow.call);

  Future<bool> _run(Future<SyncResult> Function() operation) async {
    // A signed-out session never changes the visible sync state; this is the
    // common path when a timer fires just after logout.
    if (!_session.isLoggedIn) {
      return (await operation()).isSuccess;
    }

    _syncing = true;
    notifyListeners();
    try {
      final result = await operation();
      if (result.isSuccess) {
        _lastError = null;
        _lastSyncAt = DateTime.now();
        _lastConflictCount = result.conflicts;
      } else if (result.isFailure) {
        _lastError = result.message;
      }
      return result.isSuccess;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Boot hook: constructing the controller wires the auth listener so a
  /// restored session starts the timer without opening Settings.
  void ensureStarted() {}

  void _onSessionChanged() {
    final loggedIn = _session.isLoggedIn;
    // Auth notifies on every profile refresh; only session transitions should
    // restart the cadence.
    if (loggedIn == _sessionActive) return;
    _sessionActive = loggedIn;
    if (loggedIn) {
      if (_autoStart()) {
        _startBackgroundTimer();
        unawaited(syncNow());
      }
    } else {
      _stopBackgroundTimer();
    }
  }

  void _startBackgroundTimer() {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_session.isLoggedIn && !_syncing) {
        unawaited(_backgroundSync());
      }
    });
  }

  void _stopBackgroundTimer() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  Future<void> _backgroundSync() async {
    final ok = await syncNow();
    if (ok) {
      _retryAttempt = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    } else {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final seconds = (30 * (1 << _retryAttempt)).clamp(30, 300);
    _retryAttempt = (_retryAttempt + 1).clamp(0, 4);
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (_session.isLoggedIn && !_syncing) {
        unawaited(_backgroundSync());
      }
    });
  }

  @override
  void dispose() {
    _session.removeSessionListener(_onSessionChanged);
    _stopBackgroundTimer();
    super.dispose();
  }
}
