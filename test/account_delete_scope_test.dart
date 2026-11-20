import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/services/auth_service.dart';
import 'package:klasify/services/auto_backup_service.dart';
import 'package:klasify/services/local_scope_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'scope_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  late Directory databasesDir;
  late Directory backupDir;
  late MockClient okClient;
  late MockClient failClient;

  Future<void> loginAs(int id) async {
    AuthService.testClient = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'token': 'token-$id',
          'expires_at': '2030-01-01T00:00:00Z',
          'user': {
            'id': id,
            'display_name': 'User $id',
            'email': 'u$id@example.com',
            'role': 'user',
            'department': 'CCS',
          },
        }),
        200,
      ),
    );
    await AuthService.instance.login(
      email: 'u$id@example.com',
      password: 'secret-123',
    );
  }

  setUp(() async {
    databasesDir = await freshDatabasesPath('account_delete_');
    backupDir = await Directory.systemTemp.createTemp('account_delete_backup_');
    AutoBackupService.documentsDirectoryResolver = () async => backupDir;
    AutoBackupService.debounceDelay = Duration.zero;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthService.instance.logout();
    await LocalScopeService.instance.resetForTesting();
    await AutoBackupService.instance.notifyScopeChanged();

    okClient = MockClient(
      (request) async => http.Response('{"ok":true}', 200),
    );
    failClient = MockClient(
      (request) async => http.Response('{"error":"boom"}', 500),
    );
    AuthService.testClient = okClient;
  });

  tearDown(() async {
    AuthService.testClient = null;
    await AuthService.instance.logout();
    await LocalScopeService.instance.resetForTesting();
    await disposeDatabasesPath(databasesDir);
    if (await backupDir.exists()) await backupDir.delete(recursive: true);
  });

  test('a successful delete detaches the schedule to the anonymous file',
      () async {
    await loginAs(7);
    await DatabaseHelper.instance.insert(classOf('Algebra'));
    final deviceBefore = await DatabaseHelper.instance.syncDeviceId();

    await AuthService.instance.deleteAccount();

    expect(AuthService.instance.isLoggedIn, isFalse);
    // The file changed hands, so it must not carry the deleted account's
    // device id or cursors into the next scope.
    expect(await DatabaseHelper.instance.syncDeviceId(), isNot(deviceBefore));
    expect(await DatabaseHelper.instance.lastPushAt(), isNull);
    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule_u7.db'),
      isFalse,
    );
    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule.db'),
      isTrue,
    );
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
  });

  test('scoped backups and prefs are removed', () async {
    await loginAs(7);
    await DatabaseHelper.instance.insert(classOf('Algebra'));
    await AutoBackupService.instance.backupNow();
    final scopedBackup = p.join(
      backupDir.path,
      AutoBackupService.directoryName,
      'klasify-auto-backup-u7.json',
    );
    expect(await File(scopedBackup).exists(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_backup_enabled_u7', true);
    await prefs.setInt('auto_backup_last_count_u7', 1);

    await AuthService.instance.deleteAccount();

    expect(await File(scopedBackup).exists(), isFalse);
    expect(prefs.containsKey('auto_backup_enabled_u7'), isFalse);
    expect(prefs.containsKey('auto_backup_last_count_u7'), isFalse);
    // The safety net exists under the scope the schedule now lives in.
    expect(
      await File(
        p.join(
          backupDir.path,
          AutoBackupService.directoryName,
          'klasify-auto-backup.json',
        ),
      ).exists(),
      isTrue,
    );
  });

  test('a non-empty anonymous file is never overwritten', () async {
    await loginAs(7);
    await DatabaseHelper.instance.insert(classOf('Account'));

    // A local schedule already occupies the anonymous slot.
    DatabaseHelper.databaseName = 'class_schedule.db';
    await DatabaseHelper.instance.insert(classOf('Local'));
    await AppDatabase.instance.closeScope('class_schedule.db');
    await LocalScopeService.instance.resetForTesting();

    await AuthService.instance.deleteAccount();

    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule_u7.db'),
      isTrue,
    );
    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule.db'),
      isTrue,
    );

    await LocalScopeService.instance.ensureForUser(7);
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Account');
  });

  test('a failed server delete keeps the session and the file', () async {
    await loginAs(7);
    await DatabaseHelper.instance.insert(classOf('Algebra'));
    AuthService.testClient = failClient;

    await expectLater(
      AuthService.instance.deleteAccount(),
      throwsA(isA<AuthApiException>()),
    );

    expect(AuthService.instance.isLoggedIn, isTrue);
    expect(
      await AppDatabase.instance.scopeFileExists('class_schedule_u7.db'),
      isTrue,
    );
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
  });
}
