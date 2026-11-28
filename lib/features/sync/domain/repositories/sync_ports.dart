import '../entities/sync_change.dart';
import '../entities/sync_record.dart';

/// Local persistence the sync use cases need. Implemented by SQLite.
abstract interface class SyncLocalStore {
  Future<String> deviceId();
  Future<DateTime?> lastPushAt();
  Future<DateTime?> lastPullAt();
  Future<List<SyncClassChange>> changedClasses(DateTime since);
  Future<List<SyncEventChange>> changedEvents(DateTime since);
  Future<List<SyncStatusChange>> changedStatuses(DateTime since);
  Future<Map<int, int>> classServerIds();

  Future<void> setClassServerId(int localId, int serverId);
  Future<void> setEventServerId(int localId, int serverId);
  Future<void> setClassStatusServerId(int localId, int serverId);

  Future<void> applyClass(SyncClassRecord row);
  Future<void> applyEvent(SyncEventRecord row);
  Future<void> applyStatus(SyncStatusRecord row);
  Future<void> applyOfficeStatus(SyncOfficeRecord row);
  Future<void> pruneUnadoptedOfficeStatuses();

  Future<void> purgeDeleted(DateTime? pushedBefore);
  Future<void> setLastPushAt(DateTime value);
  Future<void> setLastPullAt(DateTime value);
}

/// The sync backend. Implemented over HTTP.
abstract interface class SyncRemoteGateway {
  Future<SyncPushAck> push({
    required String token,
    required SyncPushBatch batch,
  });

  Future<SyncPullBatch> pull({
    required String token,
    required String deviceId,
    required DateTime? since,
  });
}

/// The signed-in session and the active local scope.
abstract interface class SyncSession {
  int? get userId;
  bool get isLoggedIn;

  /// Refreshes an expiring JWT and returns the current token, or null when
  /// there is no usable session.
  Future<String?> freshToken();

  /// Aligns the local database file with [userId] and reports whether sync may
  /// touch it.
  Future<bool> pinScope(int? userId);

  int get scopeGeneration;

  /// Runs [write] only while the scope is still [generation]. The adapter
  /// checks the generation, waits out a switch in progress, checks again, then
  /// writes. Returns false when the scope moved and nothing was written.
  Future<bool> writeIfCurrent(int generation, Future<void> Function() write);

  void addSessionListener(void Function() listener);
  void removeSessionListener(void Function() listener);
}

/// A transport failure with an optional HTTP status code.
///
/// The use cases turn a status code into the existing "Push failed: N" /
/// "Pull failed: N" messages; other errors keep the "Push error" form.
class SyncGatewayException implements Exception {
  const SyncGatewayException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
