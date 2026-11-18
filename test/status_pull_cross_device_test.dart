import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/services/sync_service.dart';

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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('a mark pulled for a class this device knows is inserted', () async {
    final dir = await _freshDatabaseDirectory('klasify_status_pull_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    DatabaseHelper.databaseName =
        'status_pull_${DateTime.now().microsecondsSinceEpoch}.db';

    final localId = await DatabaseHelper.instance.insert(_class('Shared'));
    await DatabaseHelper.instance.setClassServerId(localId, 5);

    // Device B marked the class; this device pulled the class but never had
    // that mark, so the mark arrives as a new local row.
    await DatabaseHelper.instance.upsertClassStatusFromServer({
      'id': 60,
      'local_id': null,
      'class_id': 5,
      'status': 'cancelled',
      'start_date': '2026-11-18',
      'end_date': '2026-11-18',
      'deleted': false,
      'updated_at': '2026-11-18T08:00:00.000Z',
    });

    final marks = (await DatabaseHelper.instance.getClassStatuses())[localId];
    expect(marks, hasLength(1));
    expect(marks!.single.status, DayStatus.cancelled);
    expect(marks.single.startDate, '2026-11-18');
    expect(marks.single.serverId, 60);
  });

  test('a mark whose class is unknown is skipped', () async {
    final dir = await _freshDatabaseDirectory('klasify_status_unknown_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    DatabaseHelper.databaseName =
        'status_unknown_${DateTime.now().microsecondsSinceEpoch}.db';

    await DatabaseHelper.instance.upsertClassStatusFromServer({
      'id': 61,
      'local_id': null,
      'class_id': 404,
      'status': 'finished',
      'start_date': '2026-11-18',
      'end_date': null,
      'deleted': false,
      'updated_at': '2026-11-18T08:00:00.000Z',
    });

    expect(await DatabaseHelper.instance.getClassStatuses(), isEmpty);
    final db = await AppDatabase.instance.database;
    expect(await db.query('class_status'), isEmpty);
  });

  test('a pushed mark names its class by server id when it has one', () async {
    final row = buildStatusPushRow({
      'id': 40,
      'server_id': null,
      'class_id': 3,
      'status': 'cancelled',
      'start_date': '2026-11-18',
      'end_date': null,
      'deleted': 0,
      'updated_at': '2026-11-18T08:00:00.000Z',
    }, 9);

    expect(row['local_id'], 40);
    expect(row['local_class_id'], 3);
    expect(row['server_class_id'], 9);
  });

  test('an offline-created mark falls back to the local class id', () async {
    final row = buildStatusPushRow({
      'id': 41,
      'server_id': null,
      'class_id': 4,
      'status': 'finished',
      'start_date': '2026-11-18',
      'end_date': null,
      'deleted': 0,
      'updated_at': '2026-11-18T08:00:00.000Z',
    }, null);

    expect(row['local_class_id'], 4);
    expect(row['server_class_id'], isNull);
  });
}
