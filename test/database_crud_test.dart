import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    // Fresh directory per run: the fixture database starts empty, so no
    // leftover row from an aborted earlier run (a crash between the insert
    // and the final delete) can collide with what this test inserts.
    // Without this, the overlap validator correctly rejects an insert whose
    // slot a run from a previous day is still occupying.
    final dir = await Directory.systemTemp.createTemp('klasify_crud_db_');
    await sqflite.databaseFactory.setDatabasesPath(dir.path);
    await DatabaseHelper.instance.resetForTesting();
  });

  test(
    'local SQLite database supports create, read, update and delete',
    () async {
      final db = DatabaseHelper.instance;
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final original = ClassItem(
        subject: 'CRUD Test $suffix',
        room: 'Test Room',
        professor: 'Test Professor',
        day: 6,
        startMinutes: 600,
        endMinutes: 660,
      );

      final id = await db.insert(original);
      expect(id, greaterThan(0));

      final found = (await db.getByDay(6)).singleWhere((item) => item.id == id);
      expect(found.subject, original.subject);

      final updated = ClassItem(
        id: id,
        subject: 'Updated Test $suffix',
        room: original.room,
        professor: original.professor,
        day: original.day,
        startMinutes: original.startMinutes,
        endMinutes: original.endMinutes,
      );
      expect(await db.update(updated), 1);
      expect(
        (await db.getByDay(6)).singleWhere((item) => item.id == id).subject,
        updated.subject,
      );

      expect(await db.delete(id), 1);
      expect((await db.getByDay(6)).any((item) => item.id == id), isFalse);

      final restoredId = await db.restoreDeleted(updated);
      expect(restoredId, id, reason: 'Undo should preserve the original ID.');
      final restored = (await db.getByDay(
        6,
      )).singleWhere((item) => item.id == id);
      expect(restored.subject, updated.subject);
      expect(restored.startMinutes, updated.startMinutes);

      expect(await db.delete(id), 1);
      expect(
        await db.delete(id),
        0,
        reason: 'Deleting a missing row must be detectable.',
      );
    },
  );

  test(
    'replaceAll validates every row before changing the saved schedule',
    () async {
      final db = DatabaseHelper.instance;
      final before = (await db.getAll()).map((item) => item.toMap()).toList();
      const invalid = ClassItem(
        subject: 'Invalid day',
        room: '101',
        professor: 'Prof. Cruz',
        day: 8,
        startMinutes: 480,
        endMinutes: 540,
      );

      await expectLater(db.replaceAll([invalid]), throwsArgumentError);

      expect((await db.getAll()).map((item) => item.toMap()).toList(), before);
    },
  );

  test(
    'replaceAll rejects overlapping classes without changing saved data',
    () async {
      final db = DatabaseHelper.instance;
      final before = (await db.getAll()).map((item) => item.toMap()).toList();
      const first = ClassItem(
        subject: 'First overlap test',
        room: '101',
        professor: 'Prof. Cruz',
        day: 1,
        startMinutes: 480,
        endMinutes: 600,
      );
      const second = ClassItem(
        subject: 'Second overlap test',
        room: '102',
        professor: 'Prof. Lee',
        day: 1,
        startMinutes: 540,
        endMinutes: 660,
      );

      await expectLater(db.replaceAll([first, second]), throwsArgumentError);
      expect((await db.getAll()).map((item) => item.toMap()).toList(), before);
    },
  );

  test('replaceAll rolls back if inserting any backup row fails', () async {
    final db = DatabaseHelper.instance;
    final before = (await db.getAll()).map((item) => item.toMap()).toList();
    final triggerDb = await sqflite.openDatabase(
      p.join(await sqflite.getDatabasesPath(), 'class_schedule.db'),
    );
    try {
      await triggerDb.execute('''
        CREATE TRIGGER fail_backup_test
        BEFORE INSERT ON classes
        WHEN NEW.subject = 'Rollback Trigger'
        BEGIN
          SELECT RAISE(ABORT, 'forced test failure');
        END
      ''');
      await expectLater(
        db.replaceAll([
          const ClassItem(
            subject: 'Valid replacement',
            room: '101',
            professor: 'Prof. Cruz',
            day: 1,
            startMinutes: 480,
            endMinutes: 540,
          ),
          const ClassItem(
            subject: 'Rollback Trigger',
            room: '102',
            professor: 'Prof. Cruz',
            day: 2,
            startMinutes: 600,
            endMinutes: 660,
          ),
        ]),
        throwsA(isA<Exception>()),
      );
      expect((await db.getAll()).map((item) => item.toMap()).toList(), before);
    } finally {
      await triggerDb.execute('DROP TRIGGER IF EXISTS fail_backup_test');
      await triggerDb.close();
    }
  });
}
