/// Pull-side sync records.
///
/// Fields are nullable where the backend row is nullable. Timestamps stay as
/// the server's raw strings so the local repositories parse and compare the
/// exact value they received.
library;

class SyncClassRecord {
  const SyncClassRecord({
    required this.serverId,
    required this.localId,
    required this.subject,
    required this.room,
    required this.professor,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    required this.deleted,
    required this.updatedAt,
  });

  final int serverId;
  final int? localId;
  final String? subject;
  final String? room;
  final String? professor;
  final int? day;
  final int? startMinutes;
  final int? endMinutes;
  final bool deleted;
  final String? updatedAt;
}

class SyncEventRecord {
  const SyncEventRecord({
    required this.serverId,
    required this.localId,
    required this.title,
    required this.venue,
    required this.eventDate,
    required this.startMinutes,
    required this.category,
    required this.department,
    required this.broadcast,
    required this.reminderEnabled,
    required this.leadMinutes,
    required this.deleted,
    required this.updatedAt,
  });

  final int serverId;
  final int? localId;
  final String? title;
  final String? venue;
  final String? eventDate;
  final int? startMinutes;
  final String? category;
  final String? department;
  final bool broadcast;
  final bool reminderEnabled;
  final int? leadMinutes;
  final bool deleted;
  final String? updatedAt;
}

class SyncStatusRecord {
  const SyncStatusRecord({
    required this.serverId,
    required this.localId,
    required this.classId,
    required this.localClassId,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.deleted,
    required this.updatedAt,
  });

  final int serverId;
  final int? localId;

  /// The owning class's server id, when the server knows it.
  final int? classId;

  /// The owning class's local id from the device that pushed the mark.
  final int? localClassId;
  final String? status;
  final String? startDate;
  final String? endDate;
  final bool deleted;
  final String? updatedAt;
}

class SyncOfficeRecord {
  const SyncOfficeRecord({
    required this.serverId,
    required this.officeName,
    required this.department,
    required this.status,
    required this.customMessage,
    required this.deleted,
    required this.updatedAt,
  });

  final int serverId;
  final String? officeName;
  final String? department;
  final String? status;
  final String? customMessage;
  final bool deleted;
  final String? updatedAt;
}

class SyncPullBatch {
  const SyncPullBatch({
    required this.serverTime,
    required this.classes,
    required this.events,
    required this.classStatuses,
    required this.officeStatuses,
  });

  final DateTime? serverTime;
  final List<SyncClassRecord> classes;
  final List<SyncEventRecord> events;
  final List<SyncStatusRecord> classStatuses;

  /// Null means the response did not describe offices at all (an older
  /// backend), so the local cache must be kept. An empty list means the
  /// response described none, so unadopted rows may be pruned.
  final List<SyncOfficeRecord>? officeStatuses;
}
