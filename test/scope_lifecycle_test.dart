import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/data/local_scope.dart';
import 'package:klasify/services/local_scope_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'scope_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await freshDatabasesPath('scope_lifecycle_');
    await resetLocalData();
    await LocalScopeService.instance.resetForTesting();
  });
  tearDown(() => disposeDatabasesPath(dir));

  test('a null user restores the persisted account scope', () async {
    SharedPreferences.setMockInitialValues({'klasify_last_scope': '7'});

    await LocalScopeService.instance.initialise();
    await LocalScopeService.instance.ensureForUser(null);

    expect(LocalScopeService.instance.current, const LocalScope.account(7));
  });

  test('signing in as another user switches files', () async {
    await LocalScopeService.instance.ensureForUser(7);
    await DatabaseHelper.instance.insert(classOf('Algebra'));

    await LocalScopeService.instance.ensureForUser(8);
    expect(await DatabaseHelper.instance.getAll(), isEmpty);

    await LocalScopeService.instance.ensureForUser(7);
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
  });

  test('a switch notifies database listeners exactly once', () async {
    var hits = 0;
    void listener() => hits++;
    DatabaseHelper.instance.addListener(listener);
    addTearDown(() => DatabaseHelper.instance.removeListener(listener));

    await LocalScopeService.instance.ensureForUser(7);

    expect(hits, 1);
  });

  test('the same user again does not bump the generation', () async {
    await LocalScopeService.instance.ensureForUser(7);
    final gen = LocalScopeService.instance.generation;

    await LocalScopeService.instance.ensureForUser(7);

    expect(LocalScopeService.instance.generation, gen);
  });

  test('a switch reconciles reminders', () async {
    var calls = 0;
    LocalScopeService.instance.reminderSyncOverride = () async => calls++;
    addTearDown(() => LocalScopeService.instance.reminderSyncOverride = null);

    await LocalScopeService.instance.ensureForUser(7);

    expect(calls, 1);
  });
}
