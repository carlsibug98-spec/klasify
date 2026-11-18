import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/database_helper.dart';

/// Points the app singleton at a private directory, so a test never touches
/// the developer's real schedule file.
Future<Directory> _freshDatabaseDirectory(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  await sqflite.databaseFactory.setDatabasesPath(dir.path);
  await DatabaseHelper.instance.resetForTesting();
  return dir;
}

/// Builds the file exactly as version 11 left it: office_name is the key and
/// the cache has no server identity of its own.
Future<void> _createV11File(String name) async {
  final path = p.join(await sqflite.getDatabasesPath(), name);
  final old = await sqflite.openDatabase(
    path,
    version: 11,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE office_statuses (
          office_name TEXT PRIMARY KEY,
          status TEXT NOT NULL DEFAULT 'open',
          custom_message TEXT,
          updated_at TEXT NOT NULL,
          CHECK (status IN ('open', 'closed', 'break'))
        )
      ''');
      await db.insert('office_statuses', {
        'office_name': 'guidance',
        'status': 'break',
        'custom_message': 'Back at 2pm',
        'updated_at': '2026-11-09T08:30:00.000Z',
      });
      await db.insert('office_statuses', {
        'office_name': 'clinic',
        'status': 'open',
        'custom_message': null,
        'updated_at': '2026-11-09T08:31:00.000Z',
      });
    },
  );
  await old.close();
}

Map<String, Object?> _guidance(List<Map<String, Object?>> rows) =>
    rows.firstWhere((r) => r['office_name'] == 'guidance');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('a version 11 cache upgrades to v12 with its rows intact', () async {
    final dir = await _freshDatabaseDirectory('klasify_office_v12_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    final name = 'v11_office_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseHelper.databaseName = name;
    await _createV11File(name);

    final rows = await DatabaseHelper.instance.getOfficeStatuses();
    expect(rows, hasLength(2));
    final guidance = _guidance(rows);
    expect(guidance['status'], 'break');
    expect(guidance['custom_message'], 'Back at 2pm');
    expect(guidance['updated_at'], '2026-11-09T08:30:00.000Z');
    expect(guidance['server_id'], isNull, reason: 'v11 rows have no identity');
    expect(guidance['id'], isA<int>(), reason: 'one local row key per cache row');

    final check = await sqflite.openDatabase(
      p.join(await sqflite.getDatabasesPath(), name),
      readOnly: true,
    );
    final info = await check.rawQuery('PRAGMA table_info(office_statuses)');
    await check.close();
    expect(
      info.map((c) => c['name']).toList(),
      containsAll(<String>['id', 'server_id', 'department']),
    );
  });

  test('a v11 row is adopted by server id on the first pull', () async {
    final dir = await _freshDatabaseDirectory('klasify_office_adopt_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    final name = 'v11_adopt_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseHelper.databaseName = name;
    await _createV11File(name);

    final before = _guidance(await DatabaseHelper.instance.getOfficeStatuses());
    await DatabaseHelper.instance.upsertOfficeStatusFromServer({
      'id': 7,
      'office_name': 'guidance',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': false,
    });

    final rows = await DatabaseHelper.instance.getOfficeStatuses();
    expect(rows, hasLength(2), reason: 'adoption must not duplicate the row');
    final after = _guidance(rows);
    expect(after['id'], before['id'], reason: 'the local row is reused');
    expect(after['server_id'], 7);
    expect(after['status'], 'open');
    expect(after['custom_message'], isNull);
  });

  test('a server rename updates the row in place', () async {
    final dir = await _freshDatabaseDirectory('klasify_office_rename_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    final name = 'v12_rename_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseHelper.databaseName = name;
    await DatabaseHelper.instance.getOfficeStatuses();

    await DatabaseHelper.instance.upsertOfficeStatusFromServer({
      'id': 9,
      'office_name': 'library',
      'department': null,
      'status': 'break',
      'custom_message': 'Back at 2pm',
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': false,
    });
    final before = (await DatabaseHelper.instance.getOfficeStatuses()).single;

    await DatabaseHelper.instance.upsertOfficeStatusFromServer({
      'id': 9,
      'office_name': 'learning-commons',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T10:00:00.000Z',
      'deleted': false,
    });

    final rows = await DatabaseHelper.instance.getOfficeStatuses();
    expect(rows, hasLength(1));
    expect(rows.single['id'], before['id']);
    expect(rows.single['office_name'], 'learning-commons');
    expect(rows.single['status'], 'open');
  });

  test('a tombstone deletes by server id even when the name changed', () async {
    final dir = await _freshDatabaseDirectory('klasify_office_tombstone_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    final name = 'v12_tomb_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseHelper.databaseName = name;
    await DatabaseHelper.instance.getOfficeStatuses();

    await DatabaseHelper.instance.upsertOfficeStatusFromServer({
      'id': 11,
      'office_name': 'guidance',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': false,
    });
    await DatabaseHelper.instance.upsertOfficeStatusFromServer({
      'id': 12,
      'office_name': 'clinic',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': false,
    });

    await DatabaseHelper.instance.upsertOfficeStatusFromServer({
      'id': 11,
      'office_name': 'registrar',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T10:00:00.000Z',
      'deleted': true,
    });

    final names = (await DatabaseHelper.instance.getOfficeStatuses())
        .map((r) => r['office_name']);
    expect(names, ['clinic']);
  });

  test('unadopted v11 rows are swept after a full pull', () async {
    final dir = await _freshDatabaseDirectory('klasify_office_sweep_');
    addTearDown(() async {
      await DatabaseHelper.instance.resetForTesting();
      await dir.delete(recursive: true);
    });
    final name = 'v11_sweep_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseHelper.databaseName = name;
    await _createV11File(name);

    // The server only knows about guidance now: clinic was retired while the
    // phone was offline and v11 rows carry no id we could tombstone by.
    await DatabaseHelper.instance.upsertOfficeStatusFromServer({
      'id': 7,
      'office_name': 'guidance',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': false,
    });
    await DatabaseHelper.instance.pruneUnadoptedOfficeStatuses();

    final rows = await DatabaseHelper.instance.getOfficeStatuses();
    expect(rows.map((r) => r['office_name']), ['guidance']);
    expect(rows.single['server_id'], 7);
  });
}
