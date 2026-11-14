import 'package:flutter/foundation.dart';

import '../models/class_item.dart';
import '../models/class_status.dart';
import '../models/event_item.dart';
import 'app_database.dart';
import 'repositories/class_repository.dart';
import 'repositories/event_repository.dart';
import 'repositories/office_repository.dart';
import 'repositories/status_repository.dart';
import 'repositories/sync_repository.dart';
import 'validation/class_rules.dart' as class_rules;
import 'validation/event_rules.dart' as event_rules;

/// Change-notifying facade over the Klasify data layer.
///
/// Schema and connection ownership live in [AppDatabase]; SQL lives in
/// `lib/data/repositories/`. This class keeps the existing public API and the
/// exact `notifyListeners()` semantics every screen and test already relies
/// on, so call sites do not need to change.
class DatabaseHelper extends ChangeNotifier {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  final _classes = ClassRepository();
  final _events = EventRepository();
  final _statuses = StatusRepository();
  final _offices = OfficeRepository();
  final _sync = SyncRepository();

  /// File name of the database. Tests set their own name so they never share a file.
  // Deliberately NOT renamed to klasify.db: existing installs keep their data
  // because the SQLite file name is unchanged across the Klasify rename.
  static String get databaseName => AppDatabase.databaseName;
  static set databaseName(String value) => AppDatabase.databaseName = value;

  /// Test-only: forget the cached connection so a suite can point the
  /// singleton at a different file. Production code never calls this.
  @visibleForTesting
  Future<void> resetForTesting() => AppDatabase.instance.resetForTesting();

  // ---- Office availability ----

  /// Cached office availability, one row per office, in display order.
  Future<List<Map<String, Object?>>> getOfficeStatuses() => _offices.getAll();

  /// Upserts one office row pulled from the server.
  Future<void> upsertOfficeStatusFromServer(Map<String, dynamic> data) async {
    if (await _offices.upsertFromServer(data)) notifyListeners();
  }

  // ---- Class statuses ----

  Future<ClassStatuses> getClassStatuses() => _statuses.getAll();

  /// Applies [incoming] to its class, replacing any days it overlaps.
  /// Returns the class's statuses from before the change, so it can be undone.
  Future<List<ClassStatusEntry>> setClassStatus(
    ClassStatusEntry incoming,
  ) async {
    final before = await _statuses.setStatus(incoming);
    notifyListeners();
    return before;
  }

  /// Clears the status for [day] only. Other days in a longer range keep their status.
  /// Returns the class's statuses from before, so it can be undone.
  Future<List<ClassStatusEntry>> clearClassStatus(
    ClassStatusEntry entry, {
    required String day,
  }) async {
    final before = await _statuses.clearStatus(entry, day: day);
    notifyListeners();
    return before;
  }

  /// Puts back the statuses a change replaced. [before] comes from
  /// setClassStatus or clearClassStatus.
  Future<void> restoreClassStatuses(
    int classId,
    List<ClassStatusEntry> before,
  ) async {
    await _statuses.restore(classId, before);
    notifyListeners();
  }

  /// Removes a class's marks that start on or after [fromDateKey].
  Future<int> deleteStatusesFrom(int classId, String fromDateKey) async {
    final removed = await _statuses.deleteFrom(classId, fromDateKey);
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// The statuses one class has now. Read before a delete, so Undo can restore them.
  Future<List<ClassStatusEntry>> statusesForClass(int classId) =>
      _statuses.forClass(classId);

  // ---- Classes ----

  static void validateClass(ClassItem c) => class_rules.validateClass(c);

  static void validateNoOverlaps(Iterable<ClassItem> classes) =>
      class_rules.validateNoOverlaps(classes);

  Future<int> insert(ClassItem c) async {
    final id = await _classes.insert(c);
    notifyListeners();
    return id;
  }

  Future<List<ClassItem>> getAll() => _classes.getAll();

  Future<List<ClassItem>> getByDay(int day) => _classes.getByDay(day);

  /// Inserts all imported classes atomically. If any insert fails, none are saved.
  Future<int> insertMany(List<ClassItem> classes) async {
    if (classes.isEmpty) return 0;
    final inserted = await _classes.insertMany(classes);
    notifyListeners();
    return inserted;
  }

  /// Replaces the full schedule in one transaction after validating every row.
  /// Used by explicit JSON restore; a failed import leaves the current data intact.
  Future<int> replaceAll(List<ClassItem> classes) async {
    final inserted = await _classes.replaceAll(classes);
    notifyListeners();
    return inserted;
  }

  /// Removes selected saved classes and imports replacements atomically.
  Future<int> replaceSelected(List<int> ids, List<ClassItem> classes) async {
    final inserted = await _classes.replaceSelected(ids, classes);
    notifyListeners();
    return inserted;
  }

  Future<int> update(ClassItem c) async {
    final changed = await _classes.update(c);
    if (changed > 0) notifyListeners();
    return changed;
  }

  /// Restores a recently deleted class with its original ID.
  Future<int> restoreDeleted(ClassItem c) async {
    final restored = await _classes.restoreDeleted(c);
    if (restored > 0) notifyListeners();
    return restored;
  }

  /// Tombstones a class and its statuses. Returns the count of affected class rows.
  Future<int> delete(int id) async {
    final deleted = await _classes.delete(id);
    if (deleted > 0) notifyListeners();
    return deleted;
  }

  // ---- Events ----

  static void validateEvent(EventItem e) => event_rules.validateEvent(e);

  /// Parsed-with-validation equivalent of [dateKey].
  static String dateKeyForEvent(String date) =>
      event_rules.dateKeyForEvent(date);

  Future<List<EventItem>> getAllEvents() => _events.getAll();

  /// Inserts one event. Returns its new id.
  Future<int> insertEvent(EventItem e) async {
    final id = await _events.insert(e);
    notifyListeners();
    return id;
  }

  Future<int> updateEvent(EventItem e) async {
    final changed = await _events.update(e);
    if (changed > 0) notifyListeners();
    return changed;
  }

  /// Restores a recently deleted event with its original ID.
  Future<int> restoreDeletedEvent(EventItem e) async {
    final restored = await _events.restoreDeleted(e);
    notifyListeners();
    return restored;
  }

  /// Removes one event. Tombstones rather than hard-deletes so the deletion syncs.
  Future<int> deleteEvent(int id) async {
    final deleted = await _events.delete(id);
    if (deleted > 0) notifyListeners();
    return deleted;
  }

  /// Replaces the full event set atomically.
  Future<int> replaceAllEvents(List<EventItem> events) async {
    final inserted = await _events.replaceAll(events);
    notifyListeners();
    return inserted;
  }

  // ---- Sync ----

  /// Returns all classes modified since [since] (for sync push).
  Future<List<ClassItem>> getChangedClasses(DateTime since) =>
      _classes.getChangedSince(since);

  /// Returns all events modified since [since] (for sync push).
  Future<List<EventItem>> getChangedEvents(DateTime since) =>
      _events.getChangedSince(since);

  /// Returns all class statuses modified since [since] (for sync push).
  Future<List<Map<String, Object?>>> getChangedClassStatuses(DateTime since) =>
      _statuses.getChangedSince(since);

  /// Upserts a class pulled from the server.
  Future<void> upsertClassFromServer(Map<String, dynamic> data) async {
    await _classes.upsertFromServer(data);
    notifyListeners();
  }

  /// Upserts an event from the server.
  Future<void> upsertEventFromServer(Map<String, dynamic> data) async {
    await _events.upsertFromServer(data);
    notifyListeners();
  }

  /// Upserts a class status pulled from the server.
  Future<void> upsertClassStatusFromServer(Map<String, dynamic> data) async {
    if (await _statuses.upsertFromServer(data)) notifyListeners();
  }

  /// Stores the server-assigned id for a pushed class.
  Future<void> setClassServerId(int localId, int serverId) =>
      _classes.setServerId(localId, serverId);

  /// Stores the server-assigned id for a pushed event.
  Future<void> setEventServerId(int localId, int serverId) =>
      _events.setServerId(localId, serverId);

  /// Stores the server-assigned id for a pushed class status.
  Future<void> setClassStatusServerId(int localId, int serverId) =>
      _statuses.setServerId(localId, serverId);

  /// Hard-deletes already-pushed tombstones.
  Future<void> purgeDeleted(DateTime? pushedBefore) =>
      _sync.purgeDeleted(pushedBefore);
}
