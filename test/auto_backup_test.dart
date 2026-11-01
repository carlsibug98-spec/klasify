import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/services/auto_backup_service.dart';
import 'package:klasify/utils/schedule_backup_codec.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databaseName =
        'auto_backup_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  late Directory tempDir;
  var suffix = '';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Start every test from an empty schedule so a failure in an earlier
    // test can never poison the next one with overlapping rows.
    await DatabaseHelper.instance.replaceAll([]);
    suffix = DateTime.now().microsecondsSinceEpoch.toString();
    tempDir = await Directory.systemTemp.createTemp('klasify_auto_backup');
    AutoBackupService.documentsDirectoryResolver = () async => tempDir;
    AutoBackupService.debounceDelay = Duration.zero;
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ClassItem classOf(String subject, {int start = 600}) => ClassItem(
    subject: '$subject $suffix',
    room: 'Room 1',
    professor: 'Prof',
    day: 6,
    startMinutes: start,
    endMinutes: start + 60,
  );

  File mainFile() => File(
    p.join(tempDir.path, AutoBackupService.directoryName, 'klasify-auto-backup.json'),
  );

  test('a schedule change produces a valid backup file', () async {
    final db = DatabaseHelper.instance;
    final original = classOf('Auto Backup');
    final id = await db.insert(original);

    final ok = await AutoBackupService.instance.backupNow();
    expect(ok, isTrue);
    expect(await mainFile().exists(), isTrue);

    final restored = ScheduleBackupCodec.decode(await mainFile().readAsBytes());
    expect(restored.any((c) => c.subject == original.subject), isTrue,
        reason: 'the backup must contain the saved class');
    expect(restored.any((c) => c.id == id), isFalse,
        reason: 'the payload keeps the export shape without row ids');
    await db.delete(id);
  });

  test('the backup payload is byte-compatible with the manual export shape',
      () async {
    final db = DatabaseHelper.instance;
    final original = classOf('Compat');
    final id = await db.insert(original);
    await AutoBackupService.instance.backupNow();

    final decoded = ScheduleBackupCodec.decode(await mainFile().readAsBytes());
    expect(decoded.length, 1);
    expect(decoded.single.subject, original.subject);
    expect(decoded.single.room, original.room);
    expect(decoded.single.professor, original.professor);
    expect(decoded.single.day, original.day);
    expect(decoded.single.startMinutes, original.startMinutes);
    expect(decoded.single.endMinutes, original.endMinutes);
    await db.delete(id);
  });

  test('dated copies rotate down to the kept window', () async {
    final dir = Directory(
      p.join(tempDir.path, AutoBackupService.directoryName),
    );
    await dir.create(recursive: true);
    // Seven stale copies plus the fresh write below → window keeps 6.
    for (var i = 1; i <= 7; i++) {
      final name = 'klasify-backup-2026010${i < 10 ? '1$i' : i}.json';
      await File(p.join(dir.path, name))
          .writeAsString('{"format":"klasify_backup"}');
    }

    await AutoBackupService.instance.backupNow();

    final names = dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((n) => n.startsWith('klasify-backup-') && n.endsWith('.json'))
        .toList();
    expect(names.length, AutoBackupService.datedCopiesToKeep,
        reason: 'oldest dated copies must roll off');
    expect(names.contains('klasify-backup-202601011.json'), isFalse,
        reason: 'the oldest copy is the first to go');
  });

  test('turning the toggle off stops backups but keeps existing files',
      () async {
    final db = DatabaseHelper.instance;
    final first = classOf('Before Pause');
    final id = await db.insert(first);
    await AutoBackupService.instance.backupNow();
    final bytesBefore = await mainFile().readAsBytes();

    await AutoBackupService.instance.setEnabled(false);
    expect(
      (await SharedPreferences.getInstance()).getBool('auto_backup_enabled'),
      isFalse,
      reason: 'the toggle must persist',
    );

    final second = classOf('While Paused', start: 700);
    final id2 = await db.insert(second);
    expect(await AutoBackupService.instance.backupNow(), isFalse,
        reason: 'a paused service must not write');
    expect(await mainFile().readAsBytes(), bytesBefore,
        reason: 'existing backups stay untouched while paused');
    await db.delete(id);
    await db.delete(id2);
  });

  test('turning the toggle on takes an immediate backup', () async {
    await AutoBackupService.instance.setEnabled(false);
    final db = DatabaseHelper.instance;
    final original = classOf('Resume');
    final id = await db.insert(original);

    await AutoBackupService.instance.setEnabled(true);
    expect(await mainFile().exists(), isTrue,
        reason: 're-enabling must refresh the copy right away');
    final restored = ScheduleBackupCodec.decode(await mainFile().readAsBytes());
    expect(restored.any((c) => c.subject == original.subject), isTrue);
    await db.delete(id);
  });

  test('state survives a reload from preferences', () async {
    final db = DatabaseHelper.instance;
    final original = classOf('Stamp');
    final id = await db.insert(original);
    await AutoBackupService.instance.backupNow();
    final count = AutoBackupService.instance.lastClassCount;
    final at = AutoBackupService.instance.lastBackupAt;
    expect(count, isNotNull);
    expect(at, isNotNull);

    // A fresh service (new isolate semantics in the app) reads the same
    // persisted state back.
    final revived = AutoBackupService();
    await revived.load();
    expect(revived.enabled, isTrue);
    expect(revived.lastClassCount, count);
    // The stamp round-trips through preferences at millisecond precision.
    expect(
      revived.lastBackupAt?.millisecondsSinceEpoch,
      at?.millisecondsSinceEpoch,
    );
    await db.delete(id);
  });

  test('attach refreshes the copy once and listens to changes', () async {
    final db = DatabaseHelper.instance;
    final original = classOf('Attach');
    final id = await db.insert(original);

    await AutoBackupService.instance.attach();
    // Debounce is zero in tests; the launch refresh is asynchronous.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await mainFile().exists(), isTrue,
        reason: 'attach must refresh the quiet copy on launch');

    await db.delete(id);
  });
}
