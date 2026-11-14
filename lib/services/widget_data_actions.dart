import '../data/database_helper.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../models/event_item.dart';

/// Database operations the class delete/undo surface needs.
///
/// Widgets receive these as callbacks instead of reaching for
/// [DatabaseHelper] directly, so the UI layer stays out of the data layer and
/// tests can drive the same flow with a fake.
class ClassDeleteActions {
  const ClassDeleteActions({
    required this.marksForClass,
    required this.deleteClass,
    required this.restoreClass,
    required this.restoreMarks,
  });

  /// Statuses saved for a class, read before deleting so Undo can restore them.
  final Future<List<ClassStatusEntry>> Function(int classId) marksForClass;

  /// Tombstones the class; returns the affected class row count.
  final Future<int> Function(int id) deleteClass;

  /// Restores a deleted class with its original id.
  final Future<int> Function(ClassItem item) restoreClass;

  /// Puts back the marks read by [marksForClass].
  final Future<void> Function(int classId, List<ClassStatusEntry> marks)
  restoreMarks;

  /// Real database-backed actions.
  static final ClassDeleteActions database = ClassDeleteActions(
    marksForClass: DatabaseHelper.instance.statusesForClass,
    deleteClass: DatabaseHelper.instance.delete,
    restoreClass: DatabaseHelper.instance.restoreDeleted,
    restoreMarks: DatabaseHelper.instance.restoreClassStatuses,
  );
}

/// Database operations the Mark class sheet needs.
class DayStatusActions {
  const DayStatusActions({required this.setStatus, required this.clearStatus});

  /// Applies a status to its class, replacing any days it overlaps.
  final Future<List<ClassStatusEntry>> Function(ClassStatusEntry entry)
  setStatus;

  /// Clears the status for one day only.
  final Future<List<ClassStatusEntry>> Function(
    ClassStatusEntry entry, {
    required String day,
  })
  clearStatus;

  /// Real database-backed actions.
  static final DayStatusActions database = DayStatusActions(
    setStatus: DatabaseHelper.instance.setClassStatus,
    clearStatus: DatabaseHelper.instance.clearClassStatus,
  );
}

/// Database operations the event sheet and event delete/undo need.
class EventActions {
  const EventActions({
    required this.insert,
    required this.update,
    required this.delete,
    required this.restore,
  });

  /// Inserts one event and returns its new id.
  final Future<int> Function(EventItem event) insert;

  /// Updates one event; returns the changed row count.
  final Future<int> Function(EventItem event) update;

  /// Tombstones one event; returns the affected row count.
  final Future<int> Function(int id) delete;

  /// Restores a recently deleted event with its original id.
  final Future<int> Function(EventItem event) restore;

  /// Real database-backed actions.
  static final EventActions database = EventActions(
    insert: DatabaseHelper.instance.insertEvent,
    update: DatabaseHelper.instance.updateEvent,
    delete: DatabaseHelper.instance.deleteEvent,
    restore: DatabaseHelper.instance.restoreDeletedEvent,
  );
}
