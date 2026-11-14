import 'package:sqflite/sqflite.dart';

import '../../models/class_item.dart';
import '../app_database.dart';
import '../db_timestamps.dart';
import '../validation/class_rules.dart';

/// Persistence for saved classes.
///
/// Status rows are tombstoned here as part of the class lifecycle: deleting,
/// replacing, or restoring a class must keep its dependent `class_status`
/// rows in step with it.
class ClassRepository {
  ClassRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<int> insert(ClassItem item) async {
    validateClass(item);
    final db = await _database.database;
    return db.transaction((txn) async {
      await _validateSchedule(txn, [item]);
      return txn.insert('classes', item.toMap()..['updated_at'] = utcStamp());
    });
  }

  Future<List<ClassItem>> getAll() async {
    final db = await _database.database;
    return _readAll(db);
  }

  Future<List<ClassItem>> getByDay(int day) async {
    final db = await _database.database;
    final rows = await db.query(
      'classes',
      where: 'day = ? AND deleted = 0',
      whereArgs: [day],
      orderBy: 'start_minutes',
    );
    return rows.map(ClassItem.fromMap).toList();
  }

  /// Inserts all imported classes atomically. If any insert fails, none are saved.
  Future<int> insertMany(List<ClassItem> classes) async {
    if (classes.isEmpty) return 0;
    for (final item in classes) {
      validateClass(item);
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      await _validateSchedule(txn, classes);
      var inserted = 0;
      for (final item in classes) {
        await txn.insert('classes', item.toMap()..['updated_at'] = utcStamp());
        inserted++;
      }
      return inserted;
    });
  }

  /// Replaces the full schedule in one transaction after validating every row.
  /// Used by explicit JSON restore; a failed import leaves the current data intact.
  Future<int> replaceAll(List<ClassItem> classes) async {
    for (final item in classes) {
      validateClass(item);
    }
    validateNoOverlaps(classes);
    final db = await _database.database;
    return db.transaction((txn) async {
      // Tombstone rather than hard-delete: rows the server already knows
      // must push their deletion, and purging only cleans them after the
      // server acknowledges it.
      await txn.update('classes', {
        'deleted': 1,
        'updated_at': utcStamp(),
      }, where: 'deleted = 0');
      var inserted = 0;
      for (final item in classes) {
        await txn.insert(
          'classes',
          item.toMap()
            ..remove('id')
            ..['updated_at'] = utcStamp(),
        );
        inserted++;
      }
      return inserted;
    });
  }

  /// Removes selected saved classes and imports replacements atomically.
  Future<int> replaceSelected(List<int> ids, List<ClassItem> classes) async {
    for (final item in classes) {
      validateClass(item);
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      await _validateSchedule(txn, classes, excludedIds: ids.toSet());
      if (ids.isNotEmpty) {
        final placeholders = List.filled(ids.length, '?').join(', ');
        await txn.update(
          'classes',
          {'deleted': 1, 'updated_at': utcStamp()},
          where: 'id IN ($placeholders) AND deleted = 0',
          whereArgs: ids,
        );
        await txn.update(
          'class_status',
          {'deleted': 1, 'updated_at': utcStamp()},
          where: 'class_id IN ($placeholders) AND deleted = 0',
          whereArgs: ids,
        );
      }
      var inserted = 0;
      for (final item in classes) {
        await txn.insert(
          'classes',
          item.toMap()
            ..remove('id')
            ..['updated_at'] = utcStamp(),
        );
        inserted++;
      }
      return inserted;
    });
  }

  Future<int> update(ClassItem item) async {
    validateClass(item);
    if (item.id == null) {
      throw ArgumentError('Cannot update a class without an ID.');
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      await _validateSchedule(txn, [item], excludedIds: {item.id!});
      return txn.update(
        'classes',
        item.toMap()..['updated_at'] = utcStamp(),
        where: 'id = ?',
        whereArgs: [item.id],
      );
    });
  }

  /// Restores a recently deleted class with its original ID. Validation is
  /// repeated because another class may have been added during the undo
  /// window. The class and every tombstoned status of its pre-delete snapshot
  /// come back live; the restored stamps re-assert both on the next push.
  Future<int> restoreDeleted(ClassItem item) async {
    validateClass(item);
    if (item.id == null) {
      throw ArgumentError('Cannot restore a class without its original ID.');
    }
    final db = await _database.database;
    // Another class may have taken the slot during the undo window: the
    // overlap check still applies against other live rows (the restoring
    // row itself is tombstoned, so it is invisible to the validator).
    await _validateSchedule(db, [item], excludedIds: {item.id!});
    final restored = await db.update(
      'classes',
      {'deleted': 0, 'updated_at': utcStamp()},
      where: 'id = ? AND deleted = 1',
      whereArgs: [item.id],
    );
    if (restored > 0) {
      await db.update(
        'class_status',
        {'deleted': 0, 'updated_at': utcStamp()},
        where: 'class_id = ? AND deleted = 1',
        whereArgs: [item.id],
      );
      // Contract preserved from the re-insert era: undo hands the original
      // ID back, not a row count. 0 means nothing was restored.
      return item.id!;
    }
    return 0;
  }

  /// Tombstones a class and its statuses (deleted = 1 + stamp) instead of
  /// hard-deleting: the tombstones ride the next push, the server
  /// acknowledges them, and purgeDeleted() removes them afterwards.
  /// Returns the count of affected class rows.
  Future<int> delete(int id) async {
    final db = await _database.database;
    final stamp = utcStamp();
    final deleted = await db.update(
      'classes',
      {'deleted': 1, 'updated_at': stamp},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    await db.update(
      'class_status',
      {'deleted': 1, 'updated_at': stamp},
      where: 'class_id = ? AND deleted = 0',
      whereArgs: [id],
    );
    return deleted;
  }

  /// Returns all classes modified since [since] (for sync push).
  /// Includes soft-deleted rows so deletions propagate.
  Future<List<ClassItem>> getChangedSince(DateTime since) async {
    final db = await _database.database;
    final rows = await db.query(
      'classes',
      where: 'updated_at IS NULL OR updated_at > ?',
      whereArgs: [since.toUtc().toIso8601String()],
      orderBy: 'updated_at',
    );
    return rows.map(ClassItem.fromMap).toList();
  }

  /// Upserts a class pulled from the server. Matching order: the stored
  /// server_id mapping first, then a still-unmapped local row whose id
  /// equals the server's remembered local_id (from when it was pushed).
  /// Conflicts are last-write-wins with a local edge: the server row
  /// overwrites the local row unless the local edit is strictly newer, in
  /// which case only the server mapping is stamped so the newer local edit
  /// re-pushes on the next cycle.
  Future<void> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _database.database;
    final serverId = data['id'] as int;
    final map = <String, Object?>{
      'subject': data['subject'],
      'room': data['room'],
      'professor': data['professor'],
      'day': data['day'],
      'start_minutes': data['start_minutes'],
      'end_minutes': data['end_minutes'],
      'deleted': (data['deleted'] as bool? ?? false) ? 1 : 0,
      'updated_at': data['updated_at'],
      'server_id': serverId,
    };

    var rows = await db.query(
      'classes',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) {
      final localFallback = data['local_id'];
      if (localFallback is int) {
        rows = await db.query(
          'classes',
          where: 'id = ? AND server_id IS NULL',
          whereArgs: [localFallback],
          limit: 1,
        );
      }
    }
    if (rows.isEmpty) {
      await db.insert('classes', map);
      return;
    }

    final local = rows.first;
    final localAt = parseInstant(local['updated_at']);
    final serverAt = parseInstant(data['updated_at']);
    if (localAt != null && serverAt != null && localAt.isAfter(serverAt)) {
      // Local is newer: keep it, but claim the mapping so this row stops
      // matching fresh pulls and re-pushes its newer timestamp.
      await db.update(
        'classes',
        {'server_id': serverId},
        where: 'id = ? AND server_id IS NULL',
        whereArgs: [local['id'] as int],
      );
    } else {
      await db.update(
        'classes',
        map,
        where: 'id = ?',
        whereArgs: [local['id'] as int],
      );
    }
  }

  /// Stores the server-assigned id for a pushed class, so future pushes
  /// match this local row to its remote twin instead of creating copies.
  Future<void> setServerId(int localId, int serverId) async {
    final db = await _database.database;
    await db.update(
      'classes',
      {'server_id': serverId},
      where: 'id = ? AND server_id IS NULL',
      whereArgs: [localId],
    );
  }

  Future<List<ClassItem>> _readAll(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'classes',
      where: 'deleted = 0',
      orderBy: 'day, start_minutes',
    );
    return rows.map(ClassItem.fromMap).toList();
  }

  Future<void> _validateSchedule(
    DatabaseExecutor executor,
    Iterable<ClassItem> additions, {
    Set<int> excludedIds = const {},
  }) async {
    final candidates = additions.toList();
    validateNoOverlaps(candidates);
    final existing = await _readAll(executor);
    for (final candidate in candidates) {
      for (final item in existing) {
        if (excludedIds.contains(item.id) || item.day != candidate.day) {
          continue;
        }
        if (candidate.startMinutes < item.endMinutes &&
            item.startMinutes < candidate.endMinutes) {
          throw ArgumentError('${candidate.subject} overlaps ${item.subject}.');
        }
      }
    }
  }
}
