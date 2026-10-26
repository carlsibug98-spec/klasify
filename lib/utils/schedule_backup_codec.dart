import 'dart:convert';

import '../database/database_helper.dart';
import '../models/class_item.dart';

/// Validates the JSON format used by local schedule backups.
class ScheduleBackupCodec {
  ScheduleBackupCodec._();

  static const maxBytes = 2 * 1024 * 1024;
  static const maxClasses = 10000;

  /// Format marker written by Klasify exports.
  static const klasifyBackupFormat = 'klasify_backup';

  /// Format marker written by pre-rename ClassCue builds. Still accepted so
  /// backups exported before the Klasify rename restore cleanly.
  static const legacyBackupFormat = 'class_schedule_backup';

  static List<ClassItem> decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Backup file exceeds the 2 MB limit.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        (decoded['format'] != klasifyBackupFormat &&
            decoded['format'] != legacyBackupFormat) ||
        decoded['version'] != 1 ||
        decoded['classes'] is! List) {
      throw const FormatException(
        'This is not a supported class schedule backup.',
      );
    }

    final rows = decoded['classes'] as List;
    if (rows.length > maxClasses) {
      throw const FormatException('Backup contains more than 10,000 classes.');
    }

    int number(Map row, String key) {
      final value = row[key];
      if (value is! num || !value.isFinite || value != value.round()) {
        throw FormatException('Invalid $key in a class entry.');
      }
      return value.toInt();
    }

    final classes = <ClassItem>[];
    for (final row in rows) {
      if (row is! Map) {
        throw const FormatException('A class entry is malformed.');
      }
      final subject = row['subject'];
      final room = row['room'];
      final professor = row['professor'];
      if (subject is! String || room is! String || professor is! String) {
        throw const FormatException('Class text fields are missing.');
      }

      final item = ClassItem(
        subject: subject,
        room: room,
        professor: professor,
        day: number(row, 'day'),
        startMinutes: number(row, 'start_minutes'),
        endMinutes: number(row, 'end_minutes'),
      );
      try {
        DatabaseHelper.validateClass(item);
      } on ArgumentError catch (error) {
        throw FormatException(error.message?.toString() ?? 'Invalid class.');
      }
      classes.add(item);
    }
    try {
      DatabaseHelper.validateNoOverlaps(classes);
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? 'Classes overlap.');
    }
    return classes;
  }
}
