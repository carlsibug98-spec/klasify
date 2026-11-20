import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/services/auto_backup_service.dart';
import 'package:klasify/services/local_scope_service.dart';
import 'package:klasify/utils/schedule_backup_codec.dart';
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

  late Directory tempDir;
  late Directory databasesDir;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('auto_backup_scope_');
    databasesDir = await freshDatabasesPath('auto_backup_scope_db_');
    AutoBackupService.documentsDirectoryResolver = () async => tempDir;
    AutoBackupService.debounceDelay = Duration.zero;
    await resetLocalData();
    await LocalScopeService.instance.resetForTesting();
    await AutoBackupService.instance.notifyScopeChanged();
  });

  tearDown(() async {
    await LocalScopeService.instance.resetForTesting();
    await AutoBackupService.instance.notifyScopeChanged();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await disposeDatabasesPath(databasesDir);
  });

  test('account backups use the scoped file name', () async {
    await LocalScopeService.instance.ensureForUser(7);
    await DatabaseHelper.instance.insert(classOf('Algebra'));

    expect(await AutoBackupService.instance.backupNow(), isTrue);

    final dir = p.join(tempDir.path, AutoBackupService.directoryName);
    expect(
      await File(p.join(dir, 'klasify-auto-backup-u7.json')).exists(),
      isTrue,
    );
    expect(
      await File(p.join(dir, 'klasify-auto-backup.json')).exists(),
      isFalse,
    );
  });

  test("rotation never deletes another scope's files", () async {
    final dir = Directory(p.join(tempDir.path, AutoBackupService.directoryName));
    await dir.create(recursive: true);
    for (var i = 0; i < AutoBackupService.datedCopiesToKeep + 2; i++) {
      await File(
        p.join(dir.path, 'klasify-backup-u7-20260101-100$i.json'),
      ).writeAsString('x');
    }
    const other = 'klasify-backup-u8-20260101-1000.json';
    await File(p.join(dir.path, other)).writeAsString('x');

    await LocalScopeService.instance.ensureForUser(7);
    expect(await AutoBackupService.instance.backupNow(), isTrue);

    expect(await File(p.join(dir.path, other)).exists(), isTrue);

    final own = await dir
        .list()
        .where((e) => p.basename(e.path).startsWith('klasify-backup-u7-'))
        .length;
    expect(own, AutoBackupService.datedCopiesToKeep);
  });

  test('loadMainBackupFile reads the active scope', () async {
    await LocalScopeService.instance.ensureForUser(7);
    await DatabaseHelper.instance.insert(classOf('Seven'));
    await AutoBackupService.instance.backupNow();

    await LocalScopeService.instance.ensureForUser(8);
    await DatabaseHelper.instance.insert(classOf('Eight'));
    await AutoBackupService.instance.backupNow();

    final eight = await AutoBackupService.instance.loadMainBackupFile();
    final decodedEight = ScheduleBackupCodec.decode(
      await eight!.readAsBytes(),
    );
    expect(decodedEight.classes.single.subject, 'Eight');

    await LocalScopeService.instance.ensureForUser(7);
    final seven = await AutoBackupService.instance.loadMainBackupFile();
    final decodedSeven = ScheduleBackupCodec.decode(
      await seven!.readAsBytes(),
    );
    expect(decodedSeven.classes.single.subject, 'Seven');
  });
}
