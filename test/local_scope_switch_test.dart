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

  test('two file names keep separate rows', () async {
    final dir = await freshDatabasesPath('scope_files_');
    addTearDown(() => disposeDatabasesPath(dir));
    await resetLocalData();

    DatabaseHelper.databaseName = 'a.db';
    await DatabaseHelper.instance.insert(classOf('Algebra'));

    DatabaseHelper.databaseName = 'b.db';
    expect(await DatabaseHelper.instance.getAll(), isEmpty);
    await DatabaseHelper.instance.insert(classOf('Biology'));

    DatabaseHelper.databaseName = 'a.db';
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
  });

  test('generation increments when the active name changes', () {
    final before = AppDatabase.instance.scopeGeneration;
    DatabaseHelper.databaseName = 'next.db';
    expect(AppDatabase.instance.scopeGeneration, before + 1);
  });

  test('closeScope forgets the handle and keeps other scopes open', () async {
    final dir = await freshDatabasesPath('scope_close_');
    addTearDown(() => disposeDatabasesPath(dir));
    await resetLocalData();

    DatabaseHelper.databaseName = 'one.db';
    await DatabaseHelper.instance.getAll();
    DatabaseHelper.databaseName = 'two.db';
    await DatabaseHelper.instance.getAll();

    await AppDatabase.instance.closeScope('one.db');

    // The file survives; only the cached handle is gone.
    expect(await AppDatabase.instance.scopeFileExists('one.db'), isTrue);
    // The other scope's handle still works without reopening from scratch.
    expect(await DatabaseHelper.instance.getAll(), isEmpty);
  });
}
