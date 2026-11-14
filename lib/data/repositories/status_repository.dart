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
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [incoming.classId],
      );
      for (final entry in after) {
        await txn.insert(
          'class_status',
          entry.toMap()..['updated_at'] = utcStamp(),
        );
      }
      // Re-attach tombstones whose ids the fresh state does not reuse;
      // unpushed deletions must survive the edit.
      final liveIds = {for (final e in after) e.id}.whereType<int>().toSet();
      for (final map in dead) {
        if (liveIds.contains(map['id'])) continue;
        await txn.insert('class_status', map);
      }
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
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [entry.classId],
      );
      for (final kept in after) {
        await txn.insert(
          'class_status',
          kept.toMap()..['updated_at'] = utcStamp(),
        );
      }
      final liveIds = {for (final e in after) e.id}.whereType<int>().toSet();
      for (final map in dead) {
        if (liveIds.contains(map['id'])) continue;
        await txn.insert('class_status', map);
      }
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
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [classId],
      );
      for (final entry in before) {
        await txn.insert(
          'class_status',
          entry.toMap()..['updated_at'] = utcStamp(),
        );
      }
      // Rows the snapshot did not cover (earlier deletions still awaiting
      // their push) keep their tombstones; rows the snapshot revives are
      // skipped, the revived inserts cover them.
      final liveIds = {for (final e in before) e.id}.whereType<int>().toSet();
      for (final map in dead) {
        if (liveIds.contains(map['id'])) continue;
        await txn.insert('class_status', map);
      }
    });
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

  /// Upserts a class status pulled from the server. Its owning class is
  /// resolved through the server_id class mapping first, then through the
  /// pushed local_class_id. Rows whose class is not known locally (its row
  /// has not arrived yet) are skipped: they are re-delivered by the delta
  /// cursor whenever the class becomes visible.
  ///
  /// Returns true when the server row was applied and listeners should be
  /// notified; skipped and locally-newer rows return false.
  Future<bool> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _database.database;
    final serverId = data['id'] as int;

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
      // Would be a brand-new local row with no class to attach to.
      return false;
    }

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
