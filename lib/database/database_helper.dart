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
      version: 6,
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
        CHECK (length(trim(title)) >= 2),
        CHECK (length(date) = 10),
        CHECK (start_minutes BETWEEN 0 AND 1439),
        CHECK (reminder_enabled IN (0, 1)),
        CHECK (lead_minutes IN (5, 10, 15, 30))
      )
    ''');
  }

  static String _classStatusSchema(String table) =>
      '''
      CREATE TABLE IF NOT EXISTS $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('finished', 'not_attending', 'cancelled')),
        start_date TEXT NOT NULL,
        end_date TEXT,
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
    final rows = await db.query('class_status', orderBy: 'start_date, id');
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
      where: 'class_id = ?',
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
      final after = replaceStatusRange(before, incoming);
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [incoming.classId],
      );
      for (final entry in after) {
        await txn.insert('class_status', entry.toMap());
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
      final after = clearStatusOnDay(before, entry, day);
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [entry.classId],
      );
      for (final kept in after) {
        await txn.insert('class_status', kept.toMap());
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
      await txn.delete(
        'class_status',
        where: 'class_id = ?',
        whereArgs: [classId],
      );
      for (final entry in before) {
        await txn.insert('class_status', entry.toMap());
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
      return txn.insert('classes', c.toMap());
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
    final rows = await executor.query('classes', orderBy: 'day, start_minutes');
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
      where: 'day = ?',
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
        await txn.insert('classes', item.toMap());
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
      await txn.delete('classes');
      var inserted = 0;
      for (final item in classes) {
        await txn.insert('classes', item.toMap()..remove('id'));
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
        await txn.delete(
          'classes',
          where: 'id IN ($placeholders)',
          whereArgs: ids,
        );
      }
      var inserted = 0;
      for (final item in classes) {
        await txn.insert('classes', item.toMap()..remove('id'));
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
        c.toMap(),
        where: 'id = ?',
        whereArgs: [c.id],
      );
    });
    if (changed > 0) notifyListeners();
    return changed;
  }

  /// Restores a recently deleted class with its original ID. Validation is
  /// repeated because another class may have been added during the undo window.
  Future<int> restoreDeleted(ClassItem c) async {
    validateClass(c);
    if (c.id == null) {
      throw ArgumentError('Cannot restore a class without its original ID.');
    }
    final db = await _database;
    final restored = await db.transaction((txn) async {
      await _validateSchedule(txn, [c]);
      return txn.insert('classes', c.toMap());
    });
    notifyListeners();
    return restored;
  }

  /// Removes a class's marks that start on or after [fromDateKey]. Used when the
  /// class moves to another weekday: those marks no longer match any of its
  /// dates. Past marks stay, as a record of what happened.
  Future<int> deleteStatusesFrom(int classId, String fromDateKey) async {
    final db = await _database;
    return db.delete(
      'class_status',
      where: 'class_id = ? AND start_date >= ?',
      whereArgs: [classId, fromDateKey],
    );
  }

  /// The statuses one class has now. Read before a delete, so Undo can restore them.
  Future<List<ClassStatusEntry>> statusesForClass(int classId) async {
    final db = await _database;
    return _statusRowsFor(db, classId);
  }

  // DELETE
  Future<int> delete(int id) async {
    final db = await _database;
    final deleted = await db.delete(
      'classes',
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete('class_status', where: 'class_id = ?', whereArgs: [id]);
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
    final rows = await db.query('events', orderBy: 'date, start_minutes');
    return rows.map(EventItem.fromMap).toList();
  }

  /// Inserts one event. Returns its new id.
  Future<int> insertEvent(EventItem e) async {
    validateEvent(e);
    final db = await _database;
    final id = await db.insert('events', e.toMap());
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
      e.toMap(),
      where: 'id = ?',
      whereArgs: [e.id],
    );
    if (changed > 0) notifyListeners();
    return changed;
  }

  /// Restores a recently deleted event with its original ID.
  Future<int> restoreDeletedEvent(EventItem e) async {
    validateEvent(e);
    if (e.id == null) {
      throw ArgumentError('Cannot restore an event without its original ID.');
    }
    final db = await _database;
    final restored = await db.insert('events', e.toMap());
    notifyListeners();
    return restored;
  }

  /// Removes one event. Returns rows affected. Events have no dependents
  /// (unlike classes and their marks), so there is nothing else to clean up.
  Future<int> deleteEvent(int id) async {
    final db = await _database;
    final deleted = await db.delete('events', where: 'id = ?', whereArgs: [id]);
    if (deleted > 0) notifyListeners();
    return deleted;
  }
}
