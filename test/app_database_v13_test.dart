import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'scope_test_support.dart';

/// Builds the file the way a version 12 install left it.
///
/// The only thing version 13 adds is `sync_state`, so a genuine v12 file is
/// the v13 fresh schema with that one table removed and the version marker set
/// back to 12. Deriving it keeps this test honest about the migration: the
/// upgrade path is exercised from version 12, not from the code under test's
/// own `onCreate`.
Future<void> _buildV12FileWithOneClass(String name) async {
  DatabaseHelper.databaseName = name;
  final db = await AppDatabase.instance.database;
  await db.insert('classes', {
    'subject': 'Pre-upgrade Algebra',
    'room': 'Room 1',
    'professor': 'Prof',
    'day': 1,
    'start_minutes': 480,
    'end_minutes': 540,
  });
  // Before v13 ships there is nothing to drop; after it ships this removes the
  // only v13 addition so the file is a real v12 one again.
  final hasSyncState = await db.query(
    'sqlite_master',
    where: "type = 'table' AND name = 'sync_state'",
  );
  if (hasSyncState.isNotEmpty) {
    await db.execute('DROP TABLE sync_state');
  }
  await db.execute('PRAGMA user_version = 12');
  await AppDatabase.instance.closeScope(name);
}

Future<List<Map<String, Object?>>> _schemaOf(String name) async {
  final path = await AppDatabase.instance.scopePath(name);
  final db = await sqflite.openDatabase(path, readOnly: true);
  try {
    return await db.rawQuery(
      "SELECT type, name, sql FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
  } finally {
    await db.close();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('a version 12 file gains sync_state and keeps every row', () async {
    final dir = await freshDatabasesPath('klasify_v13_upgrade_');
    addTearDown(() => disposeDatabasesPath(dir));
    await resetLocalData();
    final name = 'v12_to_v13_${DateTime.now().microsecondsSinceEpoch}.db';

    await _buildV12FileWithOneClass(name);

    // Sanity: the fixture really is a version 12 file with no sync_state.
    final before = await _schemaOf(name);
    expect(before.where((r) => r['name'] == 'sync_state'), isEmpty);

    DatabaseHelper.databaseName = name;
    final rows = await DatabaseHelper.instance.getAll();
    expect(rows.single.subject, 'Pre-upgrade Algebra');

    final db = await AppDatabase.instance.database;
    final tables = await db.query(
      'sqlite_master',
      where: "type = 'table' AND name = 'sync_state'",
    );
    expect(tables, hasLength(1));

    final columns = await db.rawQuery('PRAGMA table_info(sync_state)');
    expect(
      columns.map((c) => c['name']),
      containsAll(<String>['id', 'device_id', 'last_push_at', 'last_pull_at']),
    );
  });

  test('fresh and migrated v13 schemas are identical', () async {
    final dir = await freshDatabasesPath('klasify_v13_schema_');
    addTearDown(() => disposeDatabasesPath(dir));
    await resetLocalData();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final oldName = 'v12_schema_$stamp.db';
    await _buildV12FileWithOneClass(oldName);
    DatabaseHelper.databaseName = oldName;
    await DatabaseHelper.instance.getAll(); // runs the 12 -> 13 upgrade
    final migrated = await _schemaOf(oldName);

    final freshName = 'v13_fresh_$stamp.db';
    DatabaseHelper.databaseName = freshName;
    await DatabaseHelper.instance.getAll();
    final fresh = await _schemaOf(freshName);

    expect(migrated, equals(fresh));
  });
}
