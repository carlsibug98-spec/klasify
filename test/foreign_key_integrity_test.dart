import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';

/// Points the app's singleton at a private directory, so tests never touch the
/// developer's real schedule file.
Future<Directory> _freshDatabaseDirectory(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  await sqflite.databaseFactory.setDatabasesPath(dir.path);
  await DatabaseHelper.instance.resetForTesting();
  return dir;
}

ClassItem _class(String subject) => ClassItem(
  subject: subject,
  room: 'Room 1',
  professor: 'Prof Test',
  day: 3,
  startMinutes: 540,
  endMinutes: 600,
);

ClassStatusEntry _mark(int classId, String day) => ClassStatusEntry(
  classId: classId,
  status: DayStatus.cancelled,
  startDate: day,
  endDate: day,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('a fresh database enforces the mark foreign key', () async {
    final dir = await _freshDatabaseDirectory('klasify_fk_fresh_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    DatabaseHelper.databaseName =
        'fk_fresh_${DateTime.now().microsecondsSinceEpoch}.db';
    final db = DatabaseHelper.instance;
    final connection = await AppDatabase.instance.database;

    final pragma = await connection.rawQuery('PRAGMA foreign_keys');
    expect(
      pragma.single.values.single,
      1,
      reason: 'Every connection must enforce the declared foreign keys.',
    );

    // A real class still accepts its mark.
    final classId = await db.insert(_class('Mark owner'));
    await db.setClassStatus(_mark(classId, '2026-12-01'));
    expect((await db.getClassStatuses())[classId], hasLength(1));

    // A mark with no owning class is refused, and writes nothing.
    await expectLater(
      db.setClassStatus(_mark(4242, '2026-12-02')),
      throwsA(isA<sqflite.DatabaseException>()),
    );
    expect(
      await connection.query('class_status', where: 'class_id = ?', whereArgs: [4242]),
      isEmpty,
    );
    expect(await connection.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('purging a deleted class takes its marks with it', () async {
    final dir = await _freshDatabaseDirectory('klasify_fk_purge_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    DatabaseHelper.databaseName =
        'fk_purge_${DateTime.now().microsecondsSinceEpoch}.db';
    final db = DatabaseHelper.instance;

    final classId = await db.insert(_class('Purge me'));
    await db.setClassStatus(_mark(classId, '2026-12-03'));

    await db.delete(classId);
    // A successful push acknowledges everything up to now; the next cycle is
    // allowed to hard-delete the tombstones.
    await db.purgeDeleted(
      DateTime.now().toUtc().add(const Duration(minutes: 1)),
    );

    expect(await db.getAll(), isEmpty);
    final connection = await AppDatabase.instance.database;
    expect(await connection.query('class_status'), isEmpty);
    expect(await connection.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('a version 10 file keeps its marks, drops only orphans, and gains '
      'the foreign key', () async {
    final dir = await _freshDatabaseDirectory('klasify_fk_migration_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    final name = 'v10_fk_${DateTime.now().microsecondsSinceEpoch}.db';
    final path = p.join(await sqflite.getDatabasesPath(), name);

    // Build the file exactly as version 10 left it: no foreign key, both
    // indexes present, and one mark whose class is already gone.
    final old = await sqflite.openDatabase(
      path,
      version: 10,
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
            server_id INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE class_status (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT,
            updated_at TEXT,
            deleted INTEGER NOT NULL DEFAULT 0,
            server_id INTEGER,
            CHECK (end_date IS NULL OR end_date >= start_date)
          )
        ''');
        await db.execute('''
          CREATE TABLE events (
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
            server_id INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_class_status_class ON class_status (class_id)',
        );
        await db.execute(
          'CREATE UNIQUE INDEX idx_class_status_server_id '
          'ON class_status (server_id) WHERE server_id IS NOT NULL',
        );
        await db.execute('''
          INSERT INTO classes
            (id, subject, room, professor, day, start_minutes, end_minutes,
             deleted, updated_at, server_id)
          VALUES
            (1, 'Live class', '101', 'Prof Live', 1, 480, 540,
             0, '2026-10-01T00:00:00.000Z', 7),
            (2, 'Deleted class', '102', 'Prof Gone', 2, 600, 660,
             1, '2026-10-02T00:00:00.000Z', 8)
        ''');
        await db.execute('''
          INSERT INTO class_status
            (id, class_id, status, start_date, end_date, updated_at,
             deleted, server_id)
          VALUES
            (1, 1, 'finished', '2026-11-01', '2026-11-03',
             '2026-10-03T00:00:00.000Z', 0, 31),
            (2, 1, 'cancelled', '2026-11-04', '2026-11-04',
             '2026-10-04T00:00:00.000Z', 1, 32),
            (3, 999, 'cancelled', '2026-11-05', '2026-11-05',
             '2026-10-05T00:00:00.000Z', 0, 33),
            (4, 2, 'not_attending', '2026-11-06', NULL,
             '2026-10-06T00:00:00.000Z', 0, NULL)
        ''');
      },
    );
    await old.close();

    // Opening through the app runs the version 10 to 11 upgrade.
    DatabaseHelper.databaseName = name;
    final db = DatabaseHelper.instance;
    final statuses = await db.getChangedClassStatuses(DateTime.utc(1970));
    final byId = {for (final row in statuses) row['id']!: row};

    expect(byId.keys.toSet(), {1, 2, 4}, reason: 'Only the orphan goes away.');
    expect(byId[1]!['class_id'], 1);
    expect(byId[1]!['status'], 'finished');
    expect(byId[1]!['start_date'], '2026-11-01');
    expect(byId[1]!['end_date'], '2026-11-03');
    expect(byId[1]!['deleted'], 0);
    expect(byId[1]!['updated_at'], '2026-10-03T00:00:00.000Z');
    expect(byId[1]!['server_id'], 31);

    expect(byId[2]!['deleted'], 1, reason: 'Tombstones must survive the rebuild.');
    expect(byId[2]!['server_id'], 32);

    // A mark on a tombstoned class still has a parent row, so it stays.
    expect(byId[4]!['class_id'], 2);
    expect(byId[4]!['server_id'], isNull);

    final connection = await AppDatabase.instance.database;
    final fk = await connection.rawQuery('PRAGMA foreign_key_list(class_status)');
    expect(
      fk.any((row) => row['table'] == 'classes' && row['on_delete'] == 'CASCADE'),
      isTrue,
      reason: 'The rebuilt table must declare the cascade.',
    );

    // Rebuilding drops indexes, so they must be recreated afterwards.
    final indexes = await connection.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND tbl_name = 'class_status'",
    );
    final names = {for (final row in indexes) row['name']};
    expect(names, containsAll(['idx_class_status_class', 'idx_class_status_server_id']));

    final versionRow = (await connection.rawQuery('PRAGMA user_version')).single;
    expect(versionRow['user_version'], 11);

    await expectLater(
      db.setClassStatus(_mark(4242, '2026-12-04')),
      throwsA(isA<sqflite.DatabaseException>()),
    );
    expect(await connection.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
