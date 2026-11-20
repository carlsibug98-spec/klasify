import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'scope_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  setUp(() async {
    dir = await freshDatabasesPath('scope_identity_');
    await resetLocalData();
  });
  tearDown(() => disposeDatabasesPath(dir));

  test('a device id is minted once per file and stays stable', () async {
    final first = await DatabaseHelper.instance.syncDeviceId();

    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await DatabaseHelper.instance.syncDeviceId(), first);

    final db = await AppDatabase.instance.database;
    final rows = await db.query('sync_state');
    expect(rows, hasLength(1));
    expect(rows.single['device_id'], first);
  });

  test('another file gets a different device id', () async {
    final first = await DatabaseHelper.instance.syncDeviceId();

    DatabaseHelper.databaseName = 'b.db';

    expect(await DatabaseHelper.instance.syncDeviceId(), isNot(first));
  });

  test('cursors start null and are read back per file', () async {
    expect(await DatabaseHelper.instance.lastPushAt(), isNull);
    expect(await DatabaseHelper.instance.lastPullAt(), isNull);

    await DatabaseHelper.instance.setLastPushAt(DateTime.utc(2026, 1, 2, 3, 4));
    await DatabaseHelper.instance.setLastPullAt(DateTime.utc(2026, 1, 3));

    expect(
      await DatabaseHelper.instance.lastPushAt(),
      DateTime.utc(2026, 1, 2, 3, 4),
    );
    expect(await DatabaseHelper.instance.lastPullAt(), DateTime.utc(2026, 1, 3));

    DatabaseHelper.databaseName = 'b.db';
    expect(await DatabaseHelper.instance.lastPushAt(), isNull);
    expect(await DatabaseHelper.instance.lastPullAt(), isNull);
  });
}
