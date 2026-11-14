import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection, schema, and migrations.
///
/// Feature queries live in `lib/data/repositories/`; this class knows only how
/// to open the database and keep its schema current.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  /// File name of the database. Tests set their own name so they never share a file.
  // Deliberately NOT renamed to klasify.db: existing installs keep their data
  // because the SQLite file name is unchanged across the Klasify rename.
  static String databaseName = 'class_schedule.db';

  Future<Database> get database async => _db ??= await _open();

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
          await _addColumnIfMissing(
            db,
            'events',
            'broadcast',
            'INTEGER NOT NULL DEFAULT 0',
          );
          await _createOfficeStatusTable(db);
        }
      },
    );
  }

  /// Test-only: forget the cached connection so a suite can point the
  /// singleton at a different file. Production code never calls this.
  /// (The annotation lives on [DatabaseHelper.resetForTesting], the public
  /// entry point tests use.)
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

  /// Version 7 migration: add sync metadata columns to classes and events.
  /// Uses ALTER TABLE (additive, non-destructive) so existing data survives.
  Future<void> _migrateToSyncSchema(DatabaseExecutor db) async {
    // Classes: add deleted, updated_at, server_id
    await _addColumnIfMissing(
      db,
      'classes',
      'deleted',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'classes', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'classes', 'server_id', 'INTEGER');

    // Events: add category, deleted, updated_at, server_id
    await _addColumnIfMissing(
      db,
      'events',
      'category',
      "TEXT NOT NULL DEFAULT 'personal'",
    );
    await _addColumnIfMissing(
      db,
      'events',
      'deleted',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'events', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'events', 'server_id', 'INTEGER');

    // Class statuses: add updated_at, deleted, server_id
    await _addColumnIfMissing(db, 'class_status', 'updated_at', 'TEXT');
    await _addColumnIfMissing(
      db,
      'class_status',
      'deleted',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'class_status', 'server_id', 'INTEGER');

    // Stamp once so legacy rows qualify as 'changed' exactly once on the
    // next successful sync instead of on every sync forever (a null
    // updated_at always matches the delta query).
    final stamp = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      "UPDATE classes SET updated_at = ? WHERE updated_at IS NULL",
      [stamp],
    );
    await db.execute(
      "UPDATE events SET updated_at = ? WHERE updated_at IS NULL",
      [stamp],
    );
    await db.execute(
      "UPDATE class_status SET updated_at = ? WHERE updated_at IS NULL",
      [stamp],
    );
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
}
