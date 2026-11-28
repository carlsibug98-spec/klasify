import '../domain/entities/sync_change.dart';
import '../domain/entities/sync_record.dart';

/// The one place that knows the sync wire contract.
///
/// Push bodies keep the exact keys, `deleted` encodings, and timestamp
/// fallbacks the backend has always received. Pull rows keep raw timestamps so
/// the local repositories compare exactly what the server sent.
class SyncWireMapper {
  const SyncWireMapper._();

  static Map<String, dynamic> pushBody(SyncPushBatch batch) => {
    'device_id': batch.deviceId,
    'last_push_at': batch.lastPushAt?.toUtc().toIso8601String(),
    'classes': batch.classes.map(_classRow).toList(growable: false),
    'events': batch.events.map(_eventRow).toList(growable: false),
    'class_statuses': batch.classStatuses
        .map(_statusRow)
        .toList(growable: false),
  };

  static Map<String, dynamic> buildStatusPushRow(
    Map<String, Object?> status,
    int? serverClassId,
  ) => {
    'local_id': status['id'],
    'server_id': status['server_id'],
    'local_class_id': status['class_id'],
    'server_class_id': serverClassId,
    'status': status['status'],
    'start_date': status['start_date'],
    'end_date': status['end_date'],
    'deleted': (status['deleted'] as int? ?? 0) != 0,
    'updated_at':
        status['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
  };

  static SyncPushAck parsePushAck(Map<String, dynamic> data) => SyncPushAck(
    serverTime: DateTime.tryParse(data['server_time'] as String),
    classes: _mappings(data['classes']),
    events: _mappings(data['events']),
    classStatuses: _mappings(data['class_statuses']),
  );

  static SyncPullBatch parsePullBatch(Map<String, dynamic> data) {
    final officeRaw = data['office_statuses'];
    return SyncPullBatch(
      serverTime: DateTime.tryParse(data['server_time'] as String),
      classes: (data['classes'] as List? ?? const [])
          .map(_classRecord)
          .toList(growable: false),
      events: (data['events'] as List? ?? const [])
          .map(_eventRecord)
          .toList(growable: false),
      classStatuses: (data['class_statuses'] as List? ?? const [])
          .map(_statusRecord)
          .toList(growable: false),
      officeStatuses: officeRaw is List ? _officeRecords(officeRaw) : null,
    );
  }

  static Map<String, dynamic> _classRow(SyncClassChange change) => {
    'local_id': change.localId,
    'server_id': change.serverId,
    'subject': change.subject,
    'room': change.room,
    'professor': change.professor,
    'day': change.day,
    'start_minutes': change.startMinutes,
    'end_minutes': change.endMinutes,
    'deleted': change.deleted,
    'updated_at':
        change.updatedAt?.toUtc().toIso8601String() ??
        DateTime.now().toUtc().toIso8601String(),
  };

  static Map<String, dynamic> _eventRow(SyncEventChange change) => {
    'local_id': change.localId,
    'server_id': change.serverId,
    'title': change.title,
    'venue': change.venue,
    'event_date': change.date,
    'start_minutes': change.startMinutes,
    'category': change.category,
    'department': change.department,
    'broadcast': change.broadcast,
    'reminder_enabled': change.remindMe,
    'lead_minutes': change.leadMinutes,
    'deleted': change.deleted,
    'updated_at':
        change.updatedAt?.toUtc().toIso8601String() ??
        DateTime.now().toUtc().toIso8601String(),
  };

  static Map<String, dynamic> _statusRow(SyncStatusChange status) => {
    'local_id': status.localId,
    'server_id': status.serverId,
    'local_class_id': status.localClassId,
    'server_class_id': status.serverClassId,
    'status': status.status,
    'start_date': status.startDate,
    'end_date': status.endDate,
    'deleted': status.deleted,
    'updated_at': status.updatedAt ?? DateTime.now().toUtc().toIso8601String(),
  };

  static List<SyncServerMapping> _mappings(Object? raw) {
    final mappings = <SyncServerMapping>[];
    for (final item in raw as List? ?? const []) {
      if (item is Map && item['local_id'] is int && item['server_id'] is int) {
        mappings.add(
          SyncServerMapping(
            localId: item['local_id'] as int,
            serverId: item['server_id'] as int,
          ),
        );
      }
    }
    return mappings;
  }

  static SyncClassRecord _classRecord(Object? raw) {
    final row = raw as Map<String, dynamic>;
    return SyncClassRecord(
      serverId: row['id'] as int,
      localId: row['local_id'] as int?,
      subject: row['subject'] as String?,
      room: row['room'] as String?,
      professor: row['professor'] as String?,
      day: row['day'] as int?,
      startMinutes: row['start_minutes'] as int?,
      endMinutes: row['end_minutes'] as int?,
      deleted: row['deleted'] as bool? ?? false,
      updatedAt: row['updated_at'] as String?,
    );
  }

  static SyncEventRecord _eventRecord(Object? raw) {
    final row = raw as Map<String, dynamic>;
    return SyncEventRecord(
      serverId: row['id'] as int,
      localId: row['local_id'] as int?,
      title: row['title'] as String?,
      venue: row['venue'] as String?,
      eventDate: row['event_date'] as String?,
      startMinutes: row['start_minutes'] as int?,
      category: row['category'] as String?,
      department: row['department'] as String?,
      broadcast: row['broadcast'] as bool? ?? false,
      reminderEnabled: row['reminder_enabled'] as bool? ?? true,
      leadMinutes: row['lead_minutes'] as int?,
      deleted: row['deleted'] as bool? ?? false,
      updatedAt: row['updated_at'] as String?,
    );
  }

  static SyncStatusRecord _statusRecord(Object? raw) {
    final row = raw as Map<String, dynamic>;
    return SyncStatusRecord(
      serverId: row['id'] as int,
      localId: row['local_id'] as int?,
      classId: row['class_id'] as int?,
      localClassId: row['local_class_id'] as int?,
      status: row['status'] as String?,
      startDate: row['start_date'] as String?,
      endDate: row['end_date'] as String?,
      deleted: row['deleted'] as bool? ?? false,
      updatedAt: row['updated_at'] as String?,
    );
  }

  static List<SyncOfficeRecord> _officeRecords(List<dynamic> raw) {
    final rows = <SyncOfficeRecord>[];
    for (final item in raw) {
      final row = item as Map<String, dynamic>;
      final id = row['id'];
      final name = row['office_name'];
      // The office repository ignores rows without an id or a name; filtering
      // them here keeps the same visible behavior without a write call.
      if (id is! int || id <= 0 || name is! String || name.isEmpty) continue;
      rows.add(
        SyncOfficeRecord(
          serverId: id,
          officeName: name,
          department: row['department'] is String
              ? row['department'] as String
              : null,
          status: row['status'] is String ? row['status'] as String : null,
          customMessage: row['custom_message'] is String
              ? row['custom_message'] as String
              : null,
          deleted: row['deleted'] == true,
          updatedAt: row['updated_at'] is String
              ? row['updated_at'] as String
              : null,
        ),
      );
    }
    return rows;
  }
}

/// Compatibility entry point for the existing cross-device test.
Map<String, dynamic> buildStatusPushRow(
  Map<String, Object?> status,
  int? serverClassId,
) => SyncWireMapper.buildStatusPushRow(status, serverClassId);
