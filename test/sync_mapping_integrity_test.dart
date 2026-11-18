import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/models/event_item.dart';

/// Points the app's singleton at a private directory, so tests never touch the
/// developer's real schedule file.
Future<Directory> _freshDatabaseDirectory(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  await sqflite.databaseFactory.setDatabasesPath(dir.path);
  await DatabaseHelper.instance.resetForTesting();
  return dir;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test(
    'a version 9 file keeps every row and collapses duplicate server mappings',
    () async {
      final dir = await _freshDatabaseDirectory('klasify_v10_migration_');
      addTearDown(() async {
        await DatabaseHelper.instance.resetForTesting();
        await dir.delete(recursive: true);
      });

      final name = 'v9_migration_${DateTime.now().microsecondsSinceEpoch}.db';
      final path = p.join(await sqflite.getDatabasesPath(), name);

      // Build the database exactly as version 9 left it, including the
      // duplicate mappings the old sync code could produce.
      final old = await sqflite.openDatabase(
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
              server_id INTEGER
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
          await db.execute('''
            CREATE TABLE class_status (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              class_id INTEGER NOT NULL,
              status TEXT NOT NULL,
              start_date TEXT NOT NULL,
              end_date TEXT,
              updated_at TEXT,
              deleted INTEGER NOT NULL DEFAULT 0,
              server_id INTEGER
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_class_status_class ON class_status (class_id)',
          );

          // Two live classes share server row 7: the newer one keeps it.
          // A live class and its newer tombstone share server row 8: the
          // live row wins, because the server row still exists.
          await db.execute('''
            INSERT INTO classes
              (id, subject, room, professor, day, start_minutes, end_minutes,
               deleted, updated_at, server_id)
            VALUES
              (1, 'Older live copy', '101', 'Prof Old', 1, 480, 540,
               0, '2026-01-01T00:00:00.000Z', 7),
              (2, 'Newest live copy', '102', 'Prof New', 1, 600, 660,
               0, '2026-02-01T00:00:00.000Z', 7),
              (3, 'Live beats tombstone', '103', 'Prof Live', 2, 480, 540,
               0, '2026-01-01T00:00:00.000Z', 8),
              (4, 'Tombstone loses mapping', '104', 'Prof Gone', 2, 600, 660,
               1, '2026-03-01T00:00:00.000Z', 8),
              (5, 'Never pushed', '105', 'Prof Offline', 3, 480, 540,
               0, '2026-04-01T00:00:00.000Z', NULL)
          ''');
          await db.execute('''
            INSERT INTO events
              (id, title, venue, date, start_minutes, reminder_enabled,
               lead_minutes, category, department, broadcast, deleted,
               updated_at, server_id)
            VALUES
              (1, 'Older event', 'Hall', '2026-12-01', 540, 1,
               30, 'personal', NULL, 0, 0,
               '2026-01-01T00:00:00.000Z', 11),
              (2, 'Newer deleted event', 'Gym', '2026-12-02', 600, 1,
               30, 'personal', NULL, 0, 1,
               '2026-03-01T00:00:00.000Z', 11),
              (3, 'Never pushed event', 'Room 1', '2026-12-03', 660, 1,
               30, 'personal', NULL, 0, 0,
               '2026-04-01T00:00:00.000Z', NULL)
          ''');
          await db.execute('''
            INSERT INTO class_status
              (id, class_id, status, start_date, end_date, updated_at,
               deleted, server_id)
            VALUES
              (1, 1, 'cancelled', '2026-11-01', '2026-11-01',
               '2026-01-01T00:00:00.000Z', 1, 21),
              (2, 1, 'cancelled', '2026-11-02', '2026-11-02',
               '2026-03-01T00:00:00.000Z', 1, 21),
              (3, 2, 'finished', '2026-11-03', '2026-11-03',
               '2026-04-01T00:00:00.000Z', 1, NULL)
          ''');
        },
      );
      await old.close();

      // Opening through the app runs the version 9 to 10 upgrade.
      DatabaseHelper.databaseName = name;
      final db = DatabaseHelper.instance;

      final classes = await db.getChangedClasses(DateTime.utc(1970));
      expect(classes, hasLength(5), reason: 'The upgrade must keep every row.');
      final classById = {for (final c in classes) c.id!: c};
      expect(classById[2]!.serverId, 7);
      expect(classById[1]!.serverId, isNull);
      expect(classById[3]!.serverId, 8);
      expect(classById[4]!.serverId, isNull);
      expect(classById[5]!.serverId, isNull);
      expect(classById[2]!.subject, 'Newest live copy');

      final events = await db.getChangedEvents(DateTime.utc(1970));
      expect(events, hasLength(3));
      final eventById = {for (final e in events) e.id!: e};
      expect(eventById[1]!.serverId, 11);
      expect(eventById[2]!.serverId, isNull);
      expect(eventById[3]!.serverId, isNull);

      final statuses = await db.getChangedClassStatuses(DateTime.utc(1970));
      expect(statuses, hasLength(3));
      final statusById = {for (final s in statuses) s['id']!: s};
      expect(statusById[2]!['server_id'], 21);
      expect(statusById[1]!['server_id'], isNull);
      expect(statusById[3]!['server_id'], isNull);

      final check = await sqflite.openDatabase(path, readOnly: true);
      final versionRow = (await check.rawQuery('PRAGMA user_version')).single;
      expect(versionRow['user_version'], 10);
      await check.close();

      // The new indexes reject any future duplicate mapping.
      await expectLater(
        db.insert(
          const ClassItem(
            subject: 'Duplicate mapping',
            room: '999',
            professor: 'Prof Duplicate',
            day: 7,
            startMinutes: 480,
            endMinutes: 540,
            serverId: 7,
          ),
        ),
        throwsA(isA<sqflite.DatabaseException>()),
      );
      await expectLater(
        db.insertEvent(
          const EventItem(
            title: 'Duplicate mapping',
            venue: 'Hall',
            date: '2026-12-20',
            startMinutes: 600,
            serverId: 11,
          ),
        ),
        throwsA(isA<sqflite.DatabaseException>()),
      );
      await expectLater(
        db.setClassStatus(
          const ClassStatusEntry(
            classId: 2,
            status: DayStatus.finished,
            startDate: '2026-12-20',
            endDate: '2026-12-20',
            serverId: 21,
          ),
        ),
        throwsA(isA<sqflite.DatabaseException>()),
      );
    },
  );

  test('fresh installs reject a second row with the same server id', () async {
    final dir = await _freshDatabaseDirectory('klasify_server_ids_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    DatabaseHelper.databaseName =
        'fresh_ids_${DateTime.now().microsecondsSinceEpoch}.db';
    final db = DatabaseHelper.instance;

    final mappedClassId = await db.insert(
      const ClassItem(
        subject: 'Mapped class',
        room: '101',
        professor: 'Prof Map',
        day: 1,
        startMinutes: 480,
        endMinutes: 540,
        serverId: 100,
      ),
    );
    await expectLater(
      db.insert(
        const ClassItem(
          subject: 'Duplicate class',
          room: '102',
          professor: 'Prof Dup',
          day: 2,
          startMinutes: 480,
          endMinutes: 540,
          serverId: 100,
        ),
      ),
      throwsA(isA<sqflite.DatabaseException>()),
    );

    // Unmapped rows are not limited: offline users can add any number before
    // their first successful push.
    await db.insert(
      const ClassItem(
        subject: 'Offline class one',
        room: '103',
        professor: 'Prof Offline',
        day: 3,
        startMinutes: 480,
        endMinutes: 540,
      ),
    );
    final unmappedClassId = await db.insert(
      const ClassItem(
        subject: 'Offline class two',
        room: '104',
        professor: 'Prof Offline',
        day: 4,
        startMinutes: 480,
        endMinutes: 540,
      ),
    );

    await db.insertEvent(
      const EventItem(
        title: 'Mapped event',
        venue: 'Hall',
        date: '2026-12-01',
        startMinutes: 540,
        serverId: 200,
      ),
    );
    await expectLater(
      db.insertEvent(
        const EventItem(
          title: 'Duplicate event',
          venue: 'Gym',
          date: '2026-12-02',
          startMinutes: 600,
          serverId: 200,
        ),
      ),
      throwsA(isA<sqflite.DatabaseException>()),
    );

    await db.setClassStatus(
      ClassStatusEntry(
        classId: mappedClassId,
        status: DayStatus.finished,
        startDate: '2026-12-01',
        endDate: '2026-12-01',
        serverId: 300,
      ),
    );
    await expectLater(
      db.setClassStatus(
        ClassStatusEntry(
          classId: unmappedClassId,
          status: DayStatus.finished,
          startDate: '2026-12-02',
          endDate: '2026-12-02',
          serverId: 300,
        ),
      ),
      throwsA(isA<sqflite.DatabaseException>()),
    );
  });

  test('replaceAll tombstones the marks of the classes it replaces', () async {
    final dir = await _freshDatabaseDirectory('klasify_replace_all_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    DatabaseHelper.databaseName =
        'replace_all_${DateTime.now().microsecondsSinceEpoch}.db';
    final db = DatabaseHelper.instance;

    final oldClassId = await db.insert(
      const ClassItem(
        subject: 'Old class',
        room: '101',
        professor: 'Prof Old',
        day: 3,
        startMinutes: 480,
        endMinutes: 540,
      ),
    );
    await db.setClassStatus(
      ClassStatusEntry(
        classId: oldClassId,
        status: DayStatus.cancelled,
        startDate: '2026-11-18',
        endDate: '2026-11-18',
      ),
    );
    expect((await db.getClassStatuses())[oldClassId], hasLength(1));

    await db.replaceAll(const [
      ClassItem(
        subject: 'Replacement class',
        room: '202',
        professor: 'Prof New',
        day: 3,
        startMinutes: 600,
        endMinutes: 660,
      ),
    ]);

    // The live view loses the old mark; the sync view keeps its tombstone so
    // the deletion still reaches the server.
    expect((await db.getClassStatuses())[oldClassId], isNull);
    final statuses = await db.getChangedClassStatuses(DateTime.utc(1970));
    final oldMark = statuses.singleWhere(
      (row) => row['class_id'] == oldClassId,
    );
    expect(oldMark['deleted'], 1);

    final live = await db.getAll();
    expect(live, hasLength(1));
    expect(live.single.subject, 'Replacement class');
    expect(await db.getClassStatuses(), isEmpty);
  });
}
