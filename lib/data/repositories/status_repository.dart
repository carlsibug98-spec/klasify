import 'package:sqflite/sqflite.dart';

import '../../models/class_status.dart';
import '../app_database.dart';
import '../db_timestamps.dart';

/// Persistence for per-class status ranges (finished, not attending,
/// cancelled), including their server mappings and tombstones.
class StatusRepository {
  StatusRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<ClassStatuses> getAll() async {
    final db = await _database.database;
    final rows = await db.query(
      'class_status',
      where: 'deleted = 0',
      orderBy: 'start_date, id',
    );
    final result = <int, List<ClassStatusEntry>>{};
    for (final row in rows) {
      final entry = ClassStatusEntry.fromMap(row);
      result.putIfAbsent(entry.classId, () => []).add(entry);
    }
    return result;
  }

  /// Applies [incoming] to its class, replacing any days it overlaps.
  /// Returns the class's statuses from before the change, so it can be undone.
  Future<List<ClassStatusEntry>> setStatus(ClassStatusEntry incoming) async {
    final db = await _database.database;
    late List<ClassStatusEntry> before;
    await db.transaction((txn) async {
      before = await _statusRowsFor(txn, incoming.classId);
      // Keep tombstones waiting for their push: the wipe below must not
      // orphan server rows that already exist for them.
      final dead = await txn.query(
        'class_status',
        where: 'class_id = ? AND deleted = 1',
        whereArgs: [incoming.classId],
      );
      final after = replaceStatusRange(before, incoming);
      final stamp = utcStamp();
      final keptIds = {for (final e in after) e.id}.whereType<int>().toSet();
      // A row this edit drops still exists on the server: tombstone it, or
      // other devices keep pulling the un-narrowed range.
      final dropped = _tombstonesForDropped(before, keptIds, stamp);
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [incoming.classId],
      );
      for (final entry in after) {
        await txn.insert('class_status', entry.toMap()..['updated_at'] = stamp);
      }
      // Re-attach tombstones whose ids the fresh state does not reuse;
      // unpushed deletions must survive the edit.
      await _insertTombstones(txn, [...dropped, ...dead], keptIds);
    });
    return before;
  }

  /// Clears the status for [day] only. Other days in a longer range keep their status.
  /// Returns the class's statuses from before, so it can be undone.
  Future<List<ClassStatusEntry>> clearStatus(
    ClassStatusEntry entry, {
    required String day,
  }) async {
    final db = await _database.database;
    late List<ClassStatusEntry> before;
    await db.transaction((txn) async {
      before = await _statusRowsFor(txn, entry.classId);
      final dead = await txn.query(
        'class_status',
        where: 'class_id = ? AND deleted = 1',
        whereArgs: [entry.classId],
      );
      final after = clearStatusOnDay(before, entry, day);
      final stamp = utcStamp();
      final keptIds = {for (final e in after) e.id}.whereType<int>().toSet();
      final dropped = _tombstonesForDropped(before, keptIds, stamp);
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [entry.classId],
      );
      for (final kept in after) {
        await txn.insert(
          'class_status',
          kept.toMap()..['updated_at'] = stamp,
        );
      }
      await _insertTombstones(txn, [...dropped, ...dead], keptIds);
    });
    return before;
  }

  /// Puts back the statuses a change replaced. [before] comes from setStatus or clearStatus.
  Future<void> restore(int classId, List<ClassStatusEntry> before) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final dead = await txn.query(
        'class_status',
        where: 'class_id = ? AND deleted = 1',
        whereArgs: [classId],
      );
      // A mark another device added after the snapshot is about to be
      // removed: keep its server row in step with a tombstone.
      final live = await txn.query(
        'class_status',
        where: 'class_id = ? AND deleted = 0',
        whereArgs: [classId],
      );
      final keptIds = {for (final e in before) e.id}.whereType<int>().toSet();
      final stamp = utcStamp();
      final dropped = <Map<String, Object?>>[
        for (final map in live)
          if (map['server_id'] != null && !keptIds.contains(map['id']))
            {...map, 'deleted': 1, 'updated_at': stamp},
      ];
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [classId],
      );
      for (final entry in before) {
        await txn.insert(
          'class_status',
          entry.toMap()..['updated_at'] = stamp,
        );
      }
      // Rows the snapshot did not cover (earlier deletions still awaiting
      // their push) keep their tombstones; rows the snapshot revives are
      // skipped, the revived inserts cover them.
      await _insertTombstones(txn, [...dropped, ...dead], keptIds);
    });
  }

  /// Tombstones live rows the new state drops and the server already knows.
  ///
  /// A row without a server id has nothing to delete remotely: pushing a
  /// tombstone for it would insert a deleted row on the server.
  List<Map<String, Object?>> _tombstonesForDropped(
    List<ClassStatusEntry> before,
    Set<int> keptIds,
    String stamp,
  ) {
    final rows = <Map<String, Object?>>[];
    for (final entry in before) {
      if (entry.serverId == null || keptIds.contains(entry.id)) continue;
      rows.add(entry.copyWith(deleted: true).toMap()..['updated_at'] = stamp);
    }
    return rows;
  }

  /// Inserts tombstones, skipping any id the live state already uses.
  Future<void> _insertTombstones(
    DatabaseExecutor txn,
    Iterable<Map<String, Object?>> rows,
    Set<int> keptIds,
  ) async {
    final used = {...keptIds};
    for (final map in rows) {
      final id = map['id'] as int?;
      if (id != null && !used.add(id)) continue;
      await txn.insert('class_status', map);
    }
  }

  /// Removes a class's marks that start on or after [fromDateKey]. Used when
  /// the class moves to another weekday: those marks no longer match any of
  /// its dates. Past marks stay, as a record of what happened. Tombstones the
  /// removed marks so their deletion propagates through sync.
  Future<int> deleteFrom(int classId, String fromDateKey) async {
    final db = await _database.database;
    return db.update(
      'class_status',
      {'deleted': 1, 'updated_at': utcStamp()},
      where: 'class_id = ? AND start_date >= ? AND deleted = 0',
      whereArgs: [classId, fromDateKey],
    );
  }

  /// The statuses one class has now. Read before a delete, so Undo can restore them.
  Future<List<ClassStatusEntry>> forClass(int classId) async {
    final db = await _database.database;
    return _statusRowsFor(db, classId);
  }

  /// Returns all class statuses modified since [since] (for sync push).
  Future<List<Map<String, Object?>>> getChangedSince(DateTime since) async {
    final db = await _database.database;
    return db.query(
      'class_status',
      where: 'updated_at IS NULL OR updated_at > ?',
      whereArgs: [since.toUtc().toIso8601String()],
      orderBy: 'updated_at',
    );
  }

  /// Upserts a class status pulled from the server.
  ///
  /// The owning class is resolved by the server's class id first; a class
  /// created offline on this device falls back to [local_class_id] when the
  /// payload has one. When the class is known but this device has never seen
  /// the mark (another device created it), a local row is inserted so the
  /// mark shows up here too. Marks whose class is unknown locally are
  /// skipped: the delta cursor re-delivers them once the class arrives.
  ///
  /// Returns true when the server row was applied and listeners should be
  /// notified; skipped and locally-newer rows return false.
  Future<bool> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _database.database;
    final serverId = data['id'] as int;

    // Resolve the owning class first: a brand-new mark needs one to attach to.
    int? resolvedClassId;
    final serverClassId = data['class_id'];
    if (serverClassId is int) {
      final classRow = await db.query(
        'classes',
        where: 'server_id = ?',
        whereArgs: [serverClassId],
        limit: 1,
      );
      if (classRow.isNotEmpty) resolvedClassId = classRow.first['id'] as int;
    }
    if (resolvedClassId == null) {
      final localClassId = data['local_class_id'];
      if (localClassId is int) {
        final classRow = await db.query(
          'classes',
          where: 'id = ?',
          whereArgs: [localClassId],
          limit: 1,
        );
        if (classRow.isNotEmpty) resolvedClassId = classRow.first['id'] as int;
      }
    }
    if (resolvedClassId == null) {
      // Class unknown locally: keep the existing status untouched.
      return false;
    }

    var rows = await db.query(
      'class_status',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) {
      final localFallback = data['local_id'];
      if (localFallback is int) {
        rows = await db.query(
          'class_status',
          where: 'id = ? AND server_id IS NULL',
          whereArgs: [localFallback],
          limit: 1,
        );
      }
    }
    if (rows.isEmpty) {
      // A mark another device created: this device knows the class but has
      // no local row for the mark yet.
      await db.insert('class_status', {
        'class_id': resolvedClassId,
        'status': data['status'] ?? 'finished',
        'start_date': data['start_date'],
        'end_date': data['end_date'],
        'deleted': (data['deleted'] as bool? ?? false) ? 1 : 0,
        'updated_at': data['updated_at'],
        'server_id': serverId,
      });
      return true;
    }

    final local = rows.first;
    final localAt = parseInstant(local['updated_at']);
    final serverAt = parseInstant(data['updated_at']);
    if (localAt != null && serverAt != null && localAt.isAfter(serverAt)) {
      await db.update(
        'class_status',
        {'server_id': serverId},
        where: 'id = ? AND server_id IS NULL',
        whereArgs: [local['id'] as int],
      );
      return false;
    }

    await db.update(
      'class_status',
      {
        'class_id': resolvedClassId,
        'status': data['status'] ?? 'finished',
        'start_date': data['start_date'],
        'end_date': data['end_date'],
        'deleted': (data['deleted'] as bool? ?? false) ? 1 : 0,
        'updated_at': data['updated_at'],
        'server_id': serverId,
      },
      where: 'id = ?',
      whereArgs: [local['id'] as int],
    );
    return true;
  }

  /// Stores the server-assigned id for a pushed class status.
  Future<void> setServerId(int localId, int serverId) async {
    final db = await _database.database;
    await db.update(
      'class_status',
      {'server_id': serverId},
      where: 'id = ? AND server_id IS NULL',
      whereArgs: [localId],
    );
  }

  Future<List<ClassStatusEntry>> _statusRowsFor(
    DatabaseExecutor db,
    int classId,
  ) async {
    final rows = await db.query(
      'class_status',
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [classId],
      orderBy: 'start_date, id',
    );
    return [for (final row in rows) ClassStatusEntry.fromMap(row)];
  }
}
