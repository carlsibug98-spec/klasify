import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/data/local_scope.dart';
import 'package:klasify/services/local_scope_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'scope_test_support.dart';

/// Leaves a pre-login schedule in `class_schedule.db`.
Future<void> _seedAnonymous([String subject = 'Algebra']) async {
  DatabaseHelper.databaseName = 'class_schedule.db';
  await DatabaseHelper.instance.insert(classOf(subject));
  await AppDatabase.instance.closeScope('class_schedule.db');
}

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await freshDatabasesPath('legacy_claim_');
    await resetLocalData();
    await LocalScopeService.instance.resetForTesting();
  });
  tearDown(() => disposeDatabasesPath(dir));

  test('the first account adopts the anonymous file by rename', () async {
    await _seedAnonymous();

    await LocalScopeService.instance.ensureForUser(7);

    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule.db'),
      isFalse,
    );
    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule_u7.db'),
      isTrue,
    );
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
  });

  test('an existing account file is never overwritten', () async {
    await LocalScopeService.instance.ensureForUser(7);
    await DatabaseHelper.instance.insert(classOf('Account'));

    // Recreate a local file, then simulate a cold start that has to switch.
    await _seedAnonymous('Local');
    await LocalScopeService.instance.resetForTesting();
    SharedPreferences.setMockInitialValues({'klasify_last_scope': 'anon'});

    await LocalScopeService.instance.ensureForUser(7);

    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Account');
    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule.db'),
      isTrue,
    );
  });

  test('a pending claim for 7 blocks 8', () async {
    SharedPreferences.setMockInitialValues({'klasify_legacy_claim': '7'});
    await _seedAnonymous();

    await LocalScopeService.instance.ensureForUser(8);

    expect(await DatabaseHelper.instance.getAll(), isEmpty);
    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule.db'),
      isTrue,
    );
  });

  group('startup recovery', () {
    test('legacy exists, target absent: adopts for the claimed id', () async {
      SharedPreferences.setMockInitialValues({'klasify_legacy_claim': '7'});
      await _seedAnonymous();

      await LocalScopeService.instance.initialise();

      expect(LocalScopeService.instance.current, const LocalScope.account(7));
      expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
      expect(
        await AppDatabase.instance.scopeFileExists('class_schedule.db'),
        isFalse,
      );
      expect((await _prefs()).containsKey(LocalScopeService.legacyClaimKey),
          isFalse);
    });

    test('legacy absent, target exists: restores the claimed scope', () async {
      await LocalScopeService.instance.ensureForUser(7);
      await DatabaseHelper.instance.insert(classOf('Kept'));
      await LocalScopeService.instance.resetForTesting();
      SharedPreferences.setMockInitialValues({'klasify_legacy_claim': '7'});

      await LocalScopeService.instance.initialise();

      expect(LocalScopeService.instance.current, const LocalScope.account(7));
      // Recovery is about the data, not just the scope marker.
      expect((await DatabaseHelper.instance.getAll()).single.subject, 'Kept');
      final prefs = await _prefs();
      expect(prefs.getString(LocalScopeService.lastScopeKey), '7');
      expect(prefs.containsKey(LocalScopeService.legacyClaimKey), isFalse);
    });

    test('neither exists: clears the marker', () async {
      SharedPreferences.setMockInitialValues({'klasify_legacy_claim': '7'});

      await LocalScopeService.instance.initialise();

      expect(LocalScopeService.instance.current, const LocalScope.anonymous());
      expect((await _prefs()).containsKey(LocalScopeService.legacyClaimKey),
          isFalse);
    });

    test('both exist: keeps the target and clears the marker', () async {
      await _seedAnonymous('Legacy');
      await LocalScopeService.instance.ensureForUser(7);
      await DatabaseHelper.instance.getAll();

      // The collision the rename makes impossible; simulate it explicitly.
      DatabaseHelper.databaseName = 'class_schedule.db';
      await DatabaseHelper.instance.insert(classOf('Collision'));
      await AppDatabase.instance.closeScope('class_schedule.db');

      await LocalScopeService.instance.resetForTesting();
      SharedPreferences.setMockInitialValues({
        'klasify_legacy_claim': '7',
        'klasify_last_scope': 'anon',
      });

      await LocalScopeService.instance.initialise();

      final prefs = await _prefs();
      expect(prefs.containsKey(LocalScopeService.legacyClaimKey), isFalse);

      await LocalScopeService.instance.ensureForUser(7);
      expect((await DatabaseHelper.instance.getAll()).single.subject, 'Legacy');
    });
  });

  group('legacy prefs migration', () {
    test('a device id is reused only for the account that minted it', () async {
      const deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      SharedPreferences.setMockInitialValues({
        'klasify_device_id': deviceId,
        'klasify_device_owner_id': 7,
      });
      await _seedAnonymous();

      await LocalScopeService.instance.ensureForUser(7);

      expect(await DatabaseHelper.instance.syncDeviceId(), deviceId);
      final prefs = await _prefs();
      expect(prefs.containsKey('klasify_device_id'), isFalse);
      expect(prefs.containsKey('klasify_device_owner_id'), isFalse);
      expect(prefs.containsKey('klasify_last_push_at'), isFalse);
      expect(prefs.containsKey('klasify_last_pull_at'), isFalse);
    });

    test('a foreign device id is never reused', () async {
      const deviceId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      SharedPreferences.setMockInitialValues({
        'klasify_device_id': deviceId,
        'klasify_device_owner_id': 8,
        'klasify_last_push_at': '2026-01-01T00:00:00.000Z',
      });
      await _seedAnonymous();

      await LocalScopeService.instance.ensureForUser(7);

      expect(await DatabaseHelper.instance.syncDeviceId(), isNot(deviceId));
      final prefs = await _prefs();
      expect(prefs.containsKey('klasify_device_id'), isFalse);
      expect(prefs.containsKey('klasify_device_owner_id'), isFalse);
      expect(prefs.containsKey('klasify_last_push_at'), isFalse);
    });
  });
}
