/// Push-side sync entities.
///
/// These are values, not wire rows: the data layer owns the JSON keys and the
/// `deleted` / timestamp encodings.
library;

class SyncClassChange {
  const SyncClassChange({
    required this.localId,
    required this.serverId,
    required this.subject,
    required this.room,
    required this.professor,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    required this.deleted,
    required this.updatedAt,
  });

  final int localId;
  final int? serverId;
  final String subject;
  final String room;
  final String professor;
  final int day;
  final int startMinutes;
  final int endMinutes;
  final bool deleted;
  final DateTime? updatedAt;
}

class SyncEventChange {
  const SyncEventChange({
    required this.localId,
    required this.serverId,
    required this.title,
    required this.venue,
    required this.date,
    required this.startMinutes,
    required this.category,
    required this.department,
    required this.broadcast,
    required this.remindMe,
    required this.leadMinutes,
    required this.deleted,
    required this.updatedAt,
  });

  final int localId;
  final int? serverId;
  final String title;
  final String venue;
  final String date;
  final int startMinutes;
  final String category;
  final String? department;
  final bool broadcast;
  final bool remindMe;
  final int leadMinutes;
  final bool deleted;
  final DateTime? updatedAt;
}

class SyncStatusChange {
  const SyncStatusChange({
    required this.localId,
    required this.serverId,
    required this.localClassId,
    required this.serverClassId,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.deleted,
    required this.updatedAt,
  });

  final int localId;
  final int? serverId;
  final int localClassId;

  /// The class's server id when this device already knows it; null for a mark
  /// on a class created offline, which the server resolves by local id.
  final int? serverClassId;
  final String status;
  final String startDate;
  final String? endDate;
  final bool deleted;

  /// The local row's raw timestamp. Keeping the string preserves the exact
  /// value the status repository wrote, including its format.
  final String? updatedAt;

  SyncStatusChange withServerClassId(int? serverClassId) => SyncStatusChange(
    localId: localId,
    serverId: serverId,
    localClassId: localClassId,
    serverClassId: serverClassId,
    status: status,
    startDate: startDate,
    endDate: endDate,
    deleted: deleted,
    updatedAt: updatedAt,
  );
}

class SyncPushBatch {
  const SyncPushBatch({
    required this.deviceId,
    required this.lastPushAt,
    required this.classes,
    required this.events,
    required this.classStatuses,
  });

  final String deviceId;
  final DateTime? lastPushAt;
  final List<SyncClassChange> classes;
  final List<SyncEventChange> events;
  final List<SyncStatusChange> classStatuses;
}

class SyncServerMapping {
  const SyncServerMapping({required this.localId, required this.serverId});

  final int localId;
  final int serverId;
}

class SyncPushAck {
  const SyncPushAck({
    required this.serverTime,
    required this.classes,
    required this.events,
    required this.classStatuses,
  });

  final DateTime? serverTime;
  final List<SyncServerMapping> classes;
  final List<SyncServerMapping> events;
  final List<SyncServerMapping> classStatuses;
}
