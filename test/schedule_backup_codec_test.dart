import 'dart:convert';

import 'package:klasify/utils/schedule_backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> backup(Object? classes) => {
  'format': ScheduleBackupCodec.klasifyBackupFormat,
  'version': 1,
  'classes': classes,
};

Map<String, Object?> legacyBackup(Object? classes) => {
  'format': ScheduleBackupCodec.legacyBackupFormat,
  'version': 1,
  'classes': classes,
};

Map<String, Object?> row({int day = 1, int start = 480, int end = 540}) => {
  'subject': 'Mathematics',
  'room': '101',
  'professor': 'Prof. Cruz',
  'day': day,
  'start_minutes': start,
  'end_minutes': end,
};

List<int> encode(Object? value) => utf8.encode(jsonEncode(value));

void main() {
  test('decodes and validates a supported backup', () {
    final classes = ScheduleBackupCodec.decode(encode(backup([row()])));

    expect(classes, hasLength(1));
    expect(classes.single.subject, 'Mathematics');
    expect(classes.single.startMinutes, 480);
  });

  test('rejects files above the byte limit before JSON decoding', () {
    expect(
      () => ScheduleBackupCodec.decode(
        List<int>.filled(ScheduleBackupCodec.maxBytes + 1, 0),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects backups with too many class records', () {
    final bytes = encode(
      backup(
        List<Map<String, Object?>>.filled(
          ScheduleBackupCodec.maxClasses + 1,
          row(),
        ),
      ),
    );

    expect(
      () => ScheduleBackupCodec.decode(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed and invalid class records', () {
    expect(
      () => ScheduleBackupCodec.decode(encode(backup(['bad row']))),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ScheduleBackupCodec.decode(encode(backup([row(day: 8)]))),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects overlapping classes before a backup can be restored', () {
    expect(
      () => ScheduleBackupCodec.decode(
        encode(backup([row(), row(start: 530, end: 600)])),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('restores backups exported before the Klasify rename', () {
    final classes = ScheduleBackupCodec.decode(encode(legacyBackup([row()])));

    expect(classes, hasLength(1));
    expect(classes.single.subject, 'Mathematics');
    expect(classes.single.startMinutes, 480);
  });

  test('rejects unknown backup formats', () {
    final foreign = backup([row()])..['format'] = 'some_other_app_backup';

    expect(
      () => ScheduleBackupCodec.decode(encode(foreign)),
      throwsA(isA<FormatException>()),
    );
  });
}
