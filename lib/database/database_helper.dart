import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../models/event_item.dart';

class DatabaseHelper extends ChangeNotifier {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  /// File name of the database. Tests set their own name so they never share a file.
  // Deliberately NOT renamed to klasify.db: existing installs keep their data
  // because the SQLite file name is unchanged across the Klasify rename.
  static String databaseName = 'class_schedule.db';

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), databaseName);
    return openDatabase(
      path,
      version: 9,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject TEXT NOT NULL,
            room TEXT NOT NULL,
            professor TEXT NOT NULL,
            day INTEGER NOT NULL,
            start_minutes INTEGER NOT NULL,
            end_minutes INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT,
            server_id INTEGER,
            CHECK (day BETWEEN 1 AND 7),
            CHECK (start_minutes BETWEEN 0 AND 1439),
            CHECK (end_minutes BETWEEN 1 AND 1440),
            CHECK (end_minutes > start_minutes),
            CHECK (length(trim(subject)) > 0),
            CHECK (length(trim(room)) > 0),
            CHECK (length(trim(professor)) > 0)
          )
        ''');
        await _createValidationTriggers(db);
        await _createClassStatusTable(db);
        await _createEventTable(db);
        await _createOfficeStatusTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Do not rebuild or delete the existing table: users' saved classes
        // must survive upgrades. Triggers apply validation to legacy databases.
        if (oldVersion < 2) {
          await _createValidationTriggers(db);
        }
        // Version 3: the placeholder room is now "Room to confirm" everywhere.
        if (oldVersion < 3) {
          await db.execute(
            "UPDATE classes SET room = 'Room to confirm' "
            "WHERE lower(trim(room)) = 'unknown room'",
          );
        }
        // Version 4: per-class statuses (not attending / cancelled).
        if (oldVersion < 4) {
          await _createClassStatusTable(db);
        }
        // Version 5: 'finished' status, and several date ranges per class.
        if (oldVersion < 5) {
          await _rebuildClassStatusTable(db);
        }
        // Version 6: school events, phone-local until accounts arrive.
        // A new table, so no existing data can be touched.
        if (oldVersion < 6) {
          await _createEventTable(db);
        }
        // Version 7: sync metadata (category, deleted, updated_at, server_id)
        // on both classes and events. Existing rows get sensible defaults so
        // no data is lost; sync columns are nullable for offline-only users.
        if (oldVersion < 7) {
          await _migrateToSyncSchema(db);
        }
        // Version 8: re-run the idempotent sync migration. A dev-era database
        // minted class_status without the sync columns under the version-7
        // claim, and same-version drift never heals — openDatabase skips both
        // onCreate and onUpgrade when the version matches. The bump forces the
        // additive columns (and the updated_at backfill) back onto any file
        // that opened a schema like that.
        if (oldVersion < 8) {
          await _migrateToSyncSchema(db);
        }
        // Version 9: department scoping + broadcast events, and the
        // last-known office availability cache (offline shows the value
        // from the last successful sync).
        if (oldVersion < 9) {
          await _addColumnIfMissing(db, 'events', 'department', 'TEXT');
          await _addColumnIfMissing(db, 'events', 'broadcast', 'INTEGER NOT NULL DEFAULT 0');
          await _createOfficeStatusTable(db);
        }
      },
    );
  }

  /// Test-only: forget the cached connection so a suite can point the
  /// singleton at a different file. Production code never calls this.
  @visibleForTesting
  Future<void> resetForTesting() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  /// The events table. CHECK constraints carry validation for fresh and
  /// upgraded databases alike — event rows exist only since version 6, so
  /// there is no legacy data for triggers to police.
  Future<void> _createEventTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        venue TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        start_minutes INTEGER NOT NULL,
        reminder_enabled INTEGER NOT NULL DEFAULT 1,
        lead_minutes INTEGER NOT NULL DEFAULT 30,
        category TEXT NOT NULL DEFAULT 'personal',
        department TEXT,
        broadcast INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        server_id INTEGER,
        CHECK (length(trim(title)) >= 2),
        CHECK (length(date) = 10),
        CHECK (start_minutes BETWEEN 0 AND 1439),
        CHECK (reminder_enabled IN (0, 1)),
        CHECK (lead_minutes IN (5, 10, 15, 30)),
        CHECK (category IN ('personal', 'school'))
      )
    ''');
  }

  /// The last-known office availability cache. School-wide offices only
  /// (guidance / clinic / registrar), one row each, overwritten by sync.
  /// Kept separate from events so the Today strip always has a value to
  /// show offline.
  Future<void> _createOfficeStatusTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS office_statuses (
        office_name TEXT PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'open',
        custom_message TEXT,
        updated_at TEXT NOT NULL,
        CHECK (status IN ('open', 'closed', 'break'))
      )
    ''');
  }

  /// Cached office availability, one row per office, in display order.
  Future<List<Map<String, Object?>>> getOfficeStatuses() async {
    final db = await _database;
    return db.query('office_statuses', orderBy: 'office_name');
  }

  /// Upserts one office row pulled from the server. Office statuses have no
  /// local mutations, so the server value always wins.
  Future<void> upsertOfficeStatusFromServer(Map<String, dynamic> data) async {
    final office = data['office_name'];
    if (office is! String || office.isEmpty) return;
    final db = await _database;
    await db.insert(
      'office_statuses',
      {
        'office_name': office,
        'status': data['status'] ?? 'open',
        'custom_message': data['custom_message'],
        'updated_at': data['updated_at'] ?? _stampNow,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  /// Version 7 migration: add sync metadata columns to classes and events.
  /// Uses ALTER TABLE (additive, non-destructive) so existing data survives.
  Future<void> _migrateToSyncSchema(DatabaseExecutor db) async {
    // Classes: add deleted, updated_at, server_id
    await _addColumnIfMissing(db, 'classes', 'deleted', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'classes', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'classes', 'server_id', 'INTEGER');

    // Events: add category, deleted, updated_at, server_id
    await _addColumnIfMissing(db, 'events', 'category', "TEXT NOT NULL DEFAULT 'personal'");
    await _addColumnIfMissing(db, 'events', 'deleted', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'events', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'events', 'server_id', 'INTEGER');

    // Class statuses: add updated_at, deleted, server_id
    await _addColumnIfMissing(db, 'class_status', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'class_status', 'deleted', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'class_status', 'server_id', 'INTEGER');

    // Stamp once so legacy rows qualify as 'changed' exactly once on the
    // next successful sync instead of on every sync forever (a null
    // updated_at always matches the delta query).
    final stamp = DateTime.now().toUtc().toIso8601String();
    await db.execute("UPDATE classes SET updated_at = ? WHERE updated_at IS NULL", [stamp]);
    await db.execute("UPDATE events SET updated_at = ? WHERE updated_at IS NULL", [stamp]);
    await db.execute("UPDATE class_status SET updated_at = ? WHERE updated_at IS NULL", [stamp]);
  }

  /// Helper: add a column only if it doesn't already exist (idempotent).
  Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  static String _classStatusSchema(String table) =>
      '''
      CREATE TABLE IF NOT EXISTS $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('finished', 'not_attending', 'cancelled')),
        start_date TEXT NOT NULL,
        end_date TEXT,
        updated_at TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        server_id INTEGER,
        CHECK (end_date IS NULL OR end_date >= start_date)
      )
    ''';

  Future<void> _createClassStatusTable(DatabaseExecutor db) async {
    await db.execute(_classStatusSchema('class_status'));
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_class_status_class ON class_status (class_id)',
    );
  }

  /// Copies existing rows into a table with the current schema. Rows are kept as they are.
  Future<void> _rebuildClassStatusTable(DatabaseExecutor db) async {
    await db.execute(_classStatusSchema('class_status_v5'));
    // Version 4 rows have no id column (class_id was the key), so ids are assigned here.
    await db.execute('''
      INSERT INTO class_status_v5 (class_id, status, start_date, end_date)
      SELECT class_id, status, start_date, end_date FROM class_status
    ''');
    await db.execute('DROP TABLE class_status');
    await db.execute('ALTER TABLE class_status_v5 RENAME TO class_status');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_class_status_class ON class_status (class_id)',
    );
  }

  Future<ClassStatuses> getClassStatuses() async {
    final db = await _database;
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

  /// Applies [incoming] to its class, replacing any days it overlaps.
  /// Returns the class's statuses from before the change, so it can be undone.
  Future<List<ClassStatusEntry>> setClassStatus(
    ClassStatusEntry incoming,
  ) async {
    final db = await _database;
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
        await txn.insert('class_status', entry.toMap()..['updated_at'] = _stampNow);
      }
      // Re-attach tombstones whose ids the fresh state does not reuse;
      // unpushed deletions must survive the edit.
      final liveIds = {for (final e in after) e.id}.whereType<int>().toSet();
      for (final map in dead) {
        if (liveIds.contains(map['id'])) continue;
        await txn.insert('class_status', map);
      }
    });
    notifyListeners();
    return before;
  }

  /// Clears the status for [day] only. Other days in a longer range keep their status.
  /// Returns the class's statuses from before, so it can be undone.
  Future<List<ClassStatusEntry>> clearClassStatus(
    ClassStatusEntry entry, {
    required String day,
  }) async {
    final db = await _database;
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
        await txn.insert('class_status', kept.toMap()..['updated_at'] = _stampNow);
      }
      final liveIds = {for (final e in after) e.id}.whereType<int>().toSet();
      for (final map in dead) {
        if (liveIds.contains(map['id'])) continue;
        await txn.insert('class_status', map);
      }
    });
    notifyListeners();
    return before;
  }

  /// Puts back the statuses a change replaced. [before] comes from setClassStatus or clearClassStatus.
  Future<void> restoreClassStatuses(
    int classId,
    List<ClassStatusEntry> before,
  ) async {
    final db = await _database;
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
        await txn.insert('class_status', entry.toMap()..['updated_at'] = _stampNow);
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
    notifyListeners();
  }

  Future<void> _createValidationTriggers(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS classes_validate_insert
      BEFORE INSERT ON classes
      BEGIN
        SELECT CASE WHEN length(trim(NEW.subject)) < 2
          THEN RAISE(ABORT, 'Subject must contain at least 2 characters') END;
        SELECT CASE WHEN length(trim(NEW.room)) < 1
          THEN RAISE(ABORT, 'Room is required') END;
        SELECT CASE WHEN length(trim(NEW.professor)) < 2
          THEN RAISE(ABORT, 'Professor must contain at least 2 characters') END;
        SELECT CASE WHEN NEW.day < 1 OR NEW.day > 7
          THEN RAISE(ABORT, 'Day must be between 1 and 7') END;
        SELECT CASE WHEN NEW.start_minutes < 0 OR NEW.start_minutes >= 1440
          THEN RAISE(ABORT, 'Start time is invalid') END;
        SELECT CASE WHEN NEW.end_minutes < 1 OR NEW.end_minutes > 1440 OR NEW.end_minutes <= NEW.start_minutes
          THEN RAISE(ABORT, 'End time must be after start time and within the day') END;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS classes_validate_update
      BEFORE UPDATE ON classes
      BEGIN
        SELECT CASE WHEN length(trim(NEW.subject)) < 2
          THEN RAISE(ABORT, 'Subject must contain at least 2 characters') END;
        SELECT CASE WHEN length(trim(NEW.room)) < 1
          THEN RAISE(ABORT, 'Room is required') END;
        SELECT CASE WHEN length(trim(NEW.professor)) < 2
          THEN RAISE(ABORT, 'Professor must contain at least 2 characters') END;
        SELECT CASE WHEN NEW.day < 1 OR NEW.day > 7
          THEN RAISE(ABORT, 'Day must be between 1 and 7') END;
        SELECT CASE WHEN NEW.start_minutes < 0 OR NEW.start_minutes >= 1440
          THEN RAISE(ABORT, 'Start time is invalid') END;
        SELECT CASE WHEN NEW.end_minutes < 1 OR NEW.end_minutes > 1440 OR NEW.end_minutes <= NEW.start_minutes
          THEN RAISE(ABORT, 'End time must be after start time and within the day') END;
      END
    ''');
  }

  // CREATE
  Future<int> insert(ClassItem c) async {
    validateClass(c);
    final db = await _database;
    final id = await db.transaction((txn) async {
      await _validateSchedule(txn, [c]);
      return txn.insert('classes', c.toMap()..['updated_at'] = _stampNow);
    });
    notifyListeners();
    return id;
  }

  static void validateClass(ClassItem c) {
    if (c.subject.trim().length < 2) {
      throw ArgumentError('Subject must contain at least 2 characters.');
    }
    if (c.room.trim().isEmpty) throw ArgumentError('Room is required.');
    if (c.professor.trim().length < 2) {
      throw ArgumentError('Professor must contain at least 2 characters.');
    }
    if (c.day < 1 || c.day > 7) throw ArgumentError('Day must be 1–7.');
    if (c.startMinutes < 0 || c.startMinutes >= 1440) {
      throw ArgumentError('Start time is invalid.');
    }
    if (c.endMinutes <= c.startMinutes || c.endMinutes > 1440) {
      throw ArgumentError(
        'End time must be after start time and within the day.',
      );
    }
  }

  static void validateNoOverlaps(Iterable<ClassItem> classes) {
    final ordered = classes.toList()
      ..sort((a, b) {
        final day = a.day.compareTo(b.day);
        return day == 0 ? a.startMinutes.compareTo(b.startMinutes) : day;
      });
    var day = 0;
    var latestEnd = 0;
    var latestClass = '';
    for (final item in ordered) {
      if (item.day != day) {
        day = item.day;
        latestEnd = item.endMinutes;
        latestClass = item.subject;
      } else if (item.startMinutes < latestEnd) {
        throw ArgumentError('${item.subject} overlaps $latestClass.');
      } else if (item.endMinutes > latestEnd) {
        latestEnd = item.endMinutes;
        latestClass = item.subject;
      }
    }
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

  // READ
  Future<List<ClassItem>> getAll() async {
    final db = await _database;
    return _readAll(db);
  }

  Future<List<ClassItem>> getByDay(int day) async {
    final db = await _database;
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
    final db = await _database;
    final inserted = await db.transaction((txn) async {
      await _validateSchedule(txn, classes);
      var inserted = 0;
      for (final item in classes) {
        await txn.insert('classes', item.toMap()..['updated_at'] = _stampNow);
        inserted++;
      }
      return inserted;
    });
    notifyListeners();
    return inserted;
  }

  /// Replaces the full schedule in one transaction after validating every row.
  /// Used by explicit JSON restore; a failed import leaves the current data intact.
  Future<int> replaceAll(List<ClassItem> classes) async {
    for (final item in classes) {
      validateClass(item);
    }
    validateNoOverlaps(classes);
    final db = await _database;
    final inserted = await db.transaction((txn) async {
      // Tombstone rather than hard-delete: rows the server already knows
      // must push their deletion, and purging only cleans them after the
      // server acknowledges it.
      await txn.update(
        'classes',
        {'deleted': 1, 'updated_at': _stampNow},
        where: 'deleted = 0',
      );
      var inserted = 0;
      for (final item in classes) {
        await txn.insert(
          'classes',
          item.toMap()..remove('id')..['updated_at'] = _stampNow,
        );
        inserted++;
      }
      return inserted;
    });
    notifyListeners();
    return inserted;
  }

  /// Replaces the full event set atomically. Used by JSON restore; a failed
  /// import leaves the current events intact.
  Future<int> replaceAllEvents(List<EventItem> events) async {
    for (final item in events) {
      validateEvent(item);
    }
    final db = await _database;
    final inserted = await db.transaction((txn) async {
      await txn.update(
        'events',
        {'deleted': 1, 'updated_at': _stampNow},
        where: 'deleted = 0',
      );
      var inserted = 0;
      for (final item in events) {
        await txn.insert(
          'events',
          item.toMap()..remove('id')..['updated_at'] = _stampNow,
        );
        inserted++;
      }
      return inserted;
    });
    notifyListeners();
    return inserted;
  }

  /// Removes selected saved classes and imports replacements atomically.
  Future<int> replaceSelected(List<int> ids, List<ClassItem> classes) async {
    for (final item in classes) {
      validateClass(item);
    }
    final db = await _database;
    final inserted = await db.transaction((txn) async {
      await _validateSchedule(txn, classes, excludedIds: ids.toSet());
      if (ids.isNotEmpty) {
        final placeholders = List.filled(ids.length, '?').join(', ');
        await txn.update(
          'classes',
          {'deleted': 1, 'updated_at': _stampNow},
          where: 'id IN ($placeholders) AND deleted = 0',
          whereArgs: ids,
        );
        await txn.update(
          'class_status',
          {'deleted': 1, 'updated_at': _stampNow},
          where: 'class_id IN ($placeholders) AND deleted = 0',
          whereArgs: ids,
        );
      }
      var inserted = 0;
      for (final item in classes) {
        await txn.insert(
          'classes',
          item.toMap()..remove('id')..['updated_at'] = _stampNow,
        );
        inserted++;
      }
      return inserted;
    });
    notifyListeners();
    return inserted;
  }

  // UPDATE
  Future<int> update(ClassItem c) async {
    validateClass(c);
    if (c.id == null) {
      throw ArgumentError('Cannot update a class without an ID.');
    }
    final db = await _database;
    final changed = await db.transaction((txn) async {
      await _validateSchedule(txn, [c], excludedIds: {c.id!});
      return txn.update(
        'classes',
        c.toMap()..['updated_at'] = _stampNow,
        where: 'id = ?',
        whereArgs: [c.id],
      );
    });
    if (changed > 0) notifyListeners();
    return changed;
  }

  /// Restores a recently deleted class with its original ID. Validation is
  /// repeated because another class may have been added during the undo window.
  /// The class and every tombstoned status of its pre-delete snapshot come
  /// back live; the restored stamps re-assert both on the next push.
  Future<int> restoreDeleted(ClassItem c) async {
    validateClass(c);
    if (c.id == null) {
      throw ArgumentError('Cannot restore a class without its original ID.');
    }
    final db = await _database;
    // Another class may have taken the slot during the undo window: the
    // overlap check still applies against other live rows (the restoring
    // row itself is tombstoned, so it is invisible to the validator).
    await _validateSchedule(db, [c], excludedIds: {c.id!});
    final restored = await db.update(
      'classes',
      {'deleted': 0, 'updated_at': _stampNow},
      where: 'id = ? AND deleted = 1',
      whereArgs: [c.id],
    );
    if (restored > 0) {
      await db.update(
        'class_status',
        {'deleted': 0, 'updated_at': _stampNow},
        where: 'class_id = ? AND deleted = 1',
        whereArgs: [c.id],
      );
      notifyListeners();
      // Contract preserved from the re-insert era: undo hands the original
      // ID back, not a row count. 0 means nothing was restored.
      return c.id!;
    }
    return 0;
  }

  /// Removes a class's marks that start on or after [fromDateKey]. Used when the
  /// class moves to another weekday: those marks no longer match any of its
  /// dates. Past marks stay, as a record of what happened. Tombstones the
  /// removed marks so their deletion propagates through sync.
  Future<int> deleteStatusesFrom(int classId, String fromDateKey) async {
    final db = await _database;
    final removed = await db.update(
      'class_status',
      {'deleted': 1, 'updated_at': _stampNow},
      where: 'class_id = ? AND start_date >= ? AND deleted = 0',
      whereArgs: [classId, fromDateKey],
    );
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// The statuses one class has now. Read before a delete, so Undo can restore them.
  Future<List<ClassStatusEntry>> statusesForClass(int classId) async {
    final db = await _database;
    return _statusRowsFor(db, classId);
  }

  // DELETE
  /// Tombstones a class and its statuses (deleted = 1 + stamp) instead of
  /// hard-deleting: the tombstones ride the next push, the server
  /// acknowledges them, and purgeDeleted() removes them afterwards.
  /// Returns the count of affected class rows.
  Future<int> delete(int id) async {
    final db = await _database;
    final stamp = _stampNow;
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
    if (deleted > 0) notifyListeners();
    return deleted;
  }

  // ---- Events ----

  static void validateEvent(EventItem e) {
    if (e.title.trim().length < 2) {
      throw ArgumentError('Event name must contain at least 2 characters.');
    }
    // A malformed key must round-trip to itself: SQLite stores the string,
    // so "2026-02-30" would live on despite never being a real date.
    var dated = false;
    try {
      dated = dateKeyForEvent(e.date) == e.date;
    } catch (_) {
      dated = false;
    }
    if (!dated) throw ArgumentError('Event date is invalid.');
    if (e.startMinutes < 0 || e.startMinutes >= 1440) {
      throw ArgumentError('Event time is invalid.');
    }
    if (!eventLeadChoices.contains(e.leadMinutes)) {
      throw ArgumentError('Event lead time is invalid.');
    }
  }

  /// Parsed-with-validation equivalent of [dateKey]: throws on shape it
  /// cannot fully round-trip, because DateTime parses overflow silently
  /// ("2026-02-30" becomes March 2).
  static String dateKeyForEvent(String date) {
    final d = parseDateKey(date);
    return dateKey(d);
  }

  Future<List<EventItem>> getAllEvents() async {
    final db = await _database;
    final rows = await db.query(
      'events',
      where: 'deleted = 0',
      orderBy: 'date, start_minutes',
    );
    return rows.map(EventItem.fromMap).toList();
  }

  /// Inserts one event. Returns its new id.
  Future<int> insertEvent(EventItem e) async {
    validateEvent(e);
    final db = await _database;
    final id = await db.insert('events', e.toMap()..['updated_at'] = _stampNow);
    notifyListeners();
    return id;
  }

  Future<int> updateEvent(EventItem e) async {
    validateEvent(e);
    if (e.id == null) {
      throw ArgumentError('Cannot update an event without an ID.');
    }
    final db = await _database;
    final changed = await db.update(
      'events',
      e.toMap()..['updated_at'] = _stampNow,
      where: 'id = ?',
      whereArgs: [e.id],
    );
    if (changed > 0) notifyListeners();
    return changed;
  }

  /// Restores a recently deleted event with its original ID. Returns that ID
  /// when the row was tombstoned (contract from the re-insert era), or 0 when
  /// there was nothing to restore.
  Future<int> restoreDeletedEvent(EventItem e) async {
    validateEvent(e);
    if (e.id == null) {
      throw ArgumentError('Cannot restore an event without its original ID.');
    }
    final db = await _database;
    final restored = await db.update(
      'events',
      {'deleted': 0, 'updated_at': _stampNow},
      where: 'id = ? AND deleted = 1',
      whereArgs: [e.id],
    );
    notifyListeners();
    return restored > 0 ? e.id! : 0;
  }

  /// Returns all classes modified since [since] (for sync push).
  /// Includes soft-deleted rows so deletions propagate.
  Future<List<ClassItem>> getChangedClasses(DateTime since) async {
    final db = await _database;
    final rows = await db.query(
      'classes',
      where: 'updated_at IS NULL OR updated_at > ?',
      whereArgs: [since.toUtc().toIso8601String()],
      orderBy: 'updated_at',
    );
    return rows.map(ClassItem.fromMap).toList();
  }

  /// Returns all events modified since [since] (for sync push).
  Future<List<EventItem>> getChangedEvents(DateTime since) async {
    final db = await _database;
    final rows = await db.query(
      'events',
      where: 'updated_at IS NULL OR updated_at > ?',
      whereArgs: [since.toUtc().toIso8601String()],
      orderBy: 'updated_at',
    );
    return rows.map(EventItem.fromMap).toList();
  }

  /// Parses a sync timestamp (ISO-8601 in UTC) for last-write-wins checks.
  /// Returns null when there is no usable timestamp, meaning the guard is
  /// inactive and the incoming server row should win.
  DateTime? _instant(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// The sync bookkeeping instant for local writes, UTC to the millisecond.
  /// Every local mutation stamps this so the delta queries
  /// (`updated_at > lastPushAt`) and the last-write-wins guard see real,
  /// comparable timestamps instead of permanently-null legacy values.
  static String get _stampNow => DateTime.now().toUtc().toIso8601String();

  /// Upserts a class pulled from the server. Matching order: the stored
  /// server_id mapping first, then a still-unmapped local row whose id
  /// equals the server's remembered local_id (from when it was pushed).
  /// Conflicts are last-write-wins with a local edge: the server row
  /// overwrites the local row unless the local edit is strictly newer, in
  /// which case only the server mapping is stamped so the newer local edit
  /// re-pushes on the next cycle.
  Future<void> upsertClassFromServer(Map<String, dynamic> data) async {
    final db = await _database;
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
    } else {
      final local = rows.first;
      final localAt = _instant(local['updated_at']);
      final serverAt = _instant(data['updated_at']);
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
        await db.update('classes', map, where: 'id = ?', whereArgs: [local['id'] as int]);
      }
    }
    notifyListeners();
  }

  /// Upserts an event from the server. Same matching and last-write-wins
  /// rules as [upsertClassFromServer].
  Future<void> upsertEventFromServer(Map<String, dynamic> data) async {
    final db = await _database;
    final serverId = data['id'] as int;
    final map = <String, Object?>{
      'title': data['title'],
      'venue': data['venue'] ?? '',
      'date': data['event_date'],
      'start_minutes': data['start_minutes'],
      'category': data['category'] ?? 'personal',
      'department': data['department'],
      'broadcast': (data['broadcast'] as bool? ?? false) ? 1 : 0,
      'reminder_enabled': (data['reminder_enabled'] as bool? ?? true) ? 1 : 0,
      'lead_minutes': data['lead_minutes'] ?? 30,
      'deleted': (data['deleted'] as bool? ?? false) ? 1 : 0,
      'updated_at': data['updated_at'],
      'server_id': serverId,
    };

    var rows = await db.query(
      'events',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) {
      // A broadcast row's local_id belongs to the admin who posted it, so
      // it must never be matched against this device's unrelated local
      // rows. Only rows this device pushed use the id fallback.
      final isBroadcast = data['broadcast'] as bool? ?? false;
      final localFallback = data['local_id'];
      if (!isBroadcast && localFallback is int) {
        rows = await db.query(
          'events',
          where: 'id = ? AND server_id IS NULL',
          whereArgs: [localFallback],
          limit: 1,
        );
      }
    }
    if (rows.isEmpty) {
      await db.insert('events', map);
    } else {
      final local = rows.first;
      final localAt = _instant(local['updated_at']);
      final serverAt = _instant(data['updated_at']);
      if (localAt != null && serverAt != null && localAt.isAfter(serverAt)) {
        await db.update(
          'events',
          {'server_id': serverId},
          where: 'id = ? AND server_id IS NULL',
          whereArgs: [local['id'] as int],
        );
      } else {
        await db.update('events', map, where: 'id = ?', whereArgs: [local['id'] as int]);
      }
    }
    notifyListeners();
  }

  /// Upserts a class status pulled from the server. Its owning class is
  /// resolved through the server_id class mapping first, then through the
  /// pushed local_class_id. Rows whose class is not known locally (its row
  /// has not arrived yet) are skipped: they are re-delivered by the delta
  /// cursor whenever the class becomes visible.
  Future<void> upsertClassStatusFromServer(Map<String, dynamic> data) async {
    final db = await _database;
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
      return;
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
      return;
    }

    final local = rows.first;
    final localAt = _instant(local['updated_at']);
    final serverAt = _instant(data['updated_at']);
    if (localAt != null && serverAt != null && localAt.isAfter(serverAt)) {
      await db.update(
        'class_status',
        {'server_id': serverId},
        where: 'id = ? AND server_id IS NULL',
        whereArgs: [local['id'] as int],
      );
      return;
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
    notifyListeners();
  }

  /// Stores the server-assigned id for a pushed class, so future pushes
  /// match this local row to its remote twin instead of creating copies.
  Future<void> setClassServerId(int localId, int serverId) async {
    final db = await _database;
    await db.update(
      'classes',
      {'server_id': serverId},
      where: 'id = ? AND server_id IS NULL',
      whereArgs: [localId],
    );
  }

  /// Stores the server-assigned id for a pushed event.
  Future<void> setEventServerId(int localId, int serverId) async {
    final db = await _database;
    await db.update(
      'events',
      {'server_id': serverId},
      where: 'id = ? AND server_id IS NULL',
      whereArgs: [localId],
    );
  }

  /// Stores the server-assigned id for a pushed class status.
  Future<void> setClassStatusServerId(int localId, int serverId) async {
    final db = await _database;
    await db.update(
      'class_status',
      {'server_id': serverId},
      where: 'id = ? AND server_id IS NULL',
      whereArgs: [localId],
    );
  }

  /// Removes one event. Tombstones rather than hard-deletes so the deletion
  /// syncs. Returns rows affected. Events have no dependents (unlike classes
  /// and their marks), so there is nothing else to clean up.
  Future<int> deleteEvent(int id) async {
    final db = await _database;
    final deleted = await db.update(
      'events',
      {'deleted': 1, 'updated_at': _stampNow},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (deleted > 0) notifyListeners();
    return deleted;
  }

  /// Returns all class statuses modified since [since] (for sync push).
  Future<List<Map<String, Object?>>> getChangedClassStatuses(DateTime since) async {
    final db = await _database;
    final rows = await db.query(
      'class_status',
      where: 'updated_at IS NULL OR updated_at > ?',
      whereArgs: [since.toUtc().toIso8601String()],
      orderBy: 'updated_at',
    );
    return rows;
  }

  /// Hard-deletes soft-deleted rows. Only tombstones that were already
  /// pushed ([pushedBefore] cutoff, i.e. everything the last successful
  /// push covered) are safe to purge: purging an unpushed tombstone would
  /// erase the deletion locally before the server ever learns of it and
  /// the row would resurrect on the next pull.
  Future<void> purgeDeleted(DateTime? pushedBefore) async {
    if (pushedBefore == null) return;
    final db = await _database;
    final cutoff = pushedBefore.toUtc().toIso8601String();
    await db.delete(
      'classes',
      where: 'deleted = 1 AND updated_at IS NOT NULL AND updated_at <= ?',
      whereArgs: [cutoff],
    );
    await db.delete(
      'events',
      where: 'deleted = 1 AND updated_at IS NOT NULL AND updated_at <= ?',
      whereArgs: [cutoff],
    );
    await db.delete(
      'class_status',
      where: 'deleted = 1 AND updated_at IS NOT NULL AND updated_at <= ?',
      whereArgs: [cutoff],
    );
  }
}
