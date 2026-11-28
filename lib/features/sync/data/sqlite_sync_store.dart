import '../../../data/database_helper.dart';
import '../domain/entities/sync_change.dart';
import '../domain/entities/sync_record.dart';
import '../domain/repositories/sync_ports.dart';

/// The SQLite implementation of [SyncLocalStore].
///
/// This is the only sync file that knows the app's models or `DatabaseHelper`.
class SqliteSyncStore implements SyncLocalStore {
  SqliteSyncStore({DatabaseHelper? database})
    : _database = database ?? DatabaseHelper.instance;

  final DatabaseHelper _database;

  @override
  Future<String> deviceId() => _database.syncDeviceId();

  @override
  Future<DateTime?> lastPushAt() => _database.lastPushAt();

  @override
  Future<DateTime?> lastPullAt() => _database.lastPullAt();

  @override
  Future<List<SyncClassChange>> changedClasses(DateTime since) async {
    final rows = await _database.getChangedClasses(since);
    return rows
        .map(
          (row) => SyncClassChange(
            localId: row.id!,
            serverId: row.serverId,
            subject: row.subject,
            room: row.room,
            professor: row.professor,
            day: row.day,
            startMinutes: row.startMinutes,
            endMinutes: row.endMinutes,
            deleted: row.deleted,
            updatedAt: row.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<SyncEventChange>> changedEvents(DateTime since) async {
    final rows = await _database.getChangedEvents(since);
    return rows
        .map(
          (row) => SyncEventChange(
            localId: row.id!,
            serverId: row.serverId,
            title: row.title,
            venue: row.venue,
            date: row.date,
            startMinutes: row.startMinutes,
            category: row.category.name,
            department: row.department,
            broadcast: row.broadcast,
            remindMe: row.remindMe,
            leadMinutes: row.leadMinutes,
            deleted: row.deleted,
            updatedAt: row.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<SyncStatusChange>> changedStatuses(DateTime since) async {
    final rows = await _database.getChangedClassStatuses(since);
    return rows
        .map(
          (row) => SyncStatusChange(
            localId: row['id'] as int,
            serverId: row['server_id'] as int?,
            localClassId: row['class_id'] as int,
            serverClassId: null,
            status: row['status'] as String,
            startDate: row['start_date'] as String,
            endDate: row['end_date'] as String?,
            deleted: (row['deleted'] as int? ?? 0) != 0,
            updatedAt: row['updated_at'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<Map<int, int>> classServerIds() => _database.getClassServerIds();

  @override
  Future<void> setClassServerId(int localId, int serverId) =>
      _database.setClassServerId(localId, serverId);

  @override
  Future<void> setEventServerId(int localId, int serverId) =>
      _database.setEventServerId(localId, serverId);

  @override
  Future<void> setClassStatusServerId(int localId, int serverId) =>
      _database.setClassStatusServerId(localId, serverId);

  @override
  Future<void> applyClass(SyncClassRecord row) =>
      _database.upsertClassFromServer({
        'id': row.serverId,
        'local_id': row.localId,
        'subject': row.subject,
        'room': row.room,
        'professor': row.professor,
        'day': row.day,
        'start_minutes': row.startMinutes,
        'end_minutes': row.endMinutes,
        'deleted': row.deleted,
        'updated_at': row.updatedAt,
      });

  @override
  Future<void> applyEvent(SyncEventRecord row) =>
      _database.upsertEventFromServer({
        'id': row.serverId,
        'local_id': row.localId,
        'title': row.title,
        'venue': row.venue,
        'event_date': row.eventDate,
        'start_minutes': row.startMinutes,
        'category': row.category,
        'department': row.department,
        'broadcast': row.broadcast,
        'reminder_enabled': row.reminderEnabled,
        'lead_minutes': row.leadMinutes,
        'deleted': row.deleted,
        'updated_at': row.updatedAt,
      });

  @override
  Future<void> applyStatus(SyncStatusRecord row) =>
      _database.upsertClassStatusFromServer({
        'id': row.serverId,
        'local_id': row.localId,
        'class_id': row.classId,
        'local_class_id': row.localClassId,
        'status': row.status,
        'start_date': row.startDate,
        'end_date': row.endDate,
        'deleted': row.deleted,
        'updated_at': row.updatedAt,
      });

  @override
  Future<void> applyOfficeStatus(SyncOfficeRecord row) =>
      _database.upsertOfficeStatusFromServer({
        'id': row.serverId,
        'office_name': row.officeName,
        'department': row.department,
        'status': row.status,
        'custom_message': row.customMessage,
        'deleted': row.deleted,
        'updated_at': row.updatedAt,
      });

  @override
  Future<void> pruneUnadoptedOfficeStatuses() =>
      _database.pruneUnadoptedOfficeStatuses();

  @override
  Future<void> purgeDeleted(DateTime? pushedBefore) =>
      _database.purgeDeleted(pushedBefore);

  @override
  Future<void> setLastPushAt(DateTime value) => _database.setLastPushAt(value);

  @override
  Future<void> setLastPullAt(DateTime value) => _database.setLastPullAt(value);
}
