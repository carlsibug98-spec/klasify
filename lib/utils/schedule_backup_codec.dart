import 'dart:convert';
import 'dart:typed_data';

import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../models/event_item.dart';

/// Result of decoding a Klasify backup file: the classes and (optionally)
/// the events it carried. Older backups without an `events` field decode to
/// an empty event list, so restores stay backward compatible.
class ScheduleBackup {
  const ScheduleBackup({required this.classes, required this.events});

  final List<ClassItem> classes;
  final List<EventItem> events;
}

/// Validates and writes the JSON format used by local schedule backups.
class ScheduleBackupCodec {
  ScheduleBackupCodec._();

  static const maxBytes = 2 * 1024 * 1024;
  static const maxClasses = 10000;
  static const maxEvents = 10000;

  /// Format marker written by Klasify exports.
  static const klasifyBackupFormat = 'klasify_backup';

  /// Format marker written by pre-rename ClassCue builds. Still accepted so
  /// backups exported before the Klasify rename restore cleanly.
  static const legacyBackupFormat = 'class_schedule_backup';

  /// Writes [classes] (and optionally [events]) in the payload shape the
  /// manual export has used since version 1, so the automatic backup and the
  /// manual export stay byte-compatible and every restore path accepts both.
  static Uint8List encode(
    List<ClassItem> classes, {
    List<EventItem> events = const [],
  }) {
    final payload = <String, Object?>{
      'format': klasifyBackupFormat,
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'classes': classes
          .map(
            (c) => {
              'subject': c.subject,
              'room': c.room,
              'professor': c.professor,
              'day': c.day,
              'start_minutes': c.startMinutes,
              'end_minutes': c.endMinutes,
            },
          )
          .toList(),
      'events': events
          .map(
            (e) => {
              'title': e.title,
              'venue': e.venue,
              'date': e.date,
              'start_minutes': e.startMinutes,
              'reminder_enabled': e.remindMe ? 1 : 0,
              'lead_minutes': e.leadMinutes,
              'category': e.category.name,
            },
          )
          .toList(),
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  static ScheduleBackup decode(List<int> bytes) {
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

    // Events are optional: older backups (and legacy ClassCue files) carry
    // none, and that's fine.
    final eventsRaw = decoded['events'];
    final events = <EventItem>[];
    if (eventsRaw is List) {
      if (eventsRaw.length > maxEvents) {
        throw const FormatException('Backup contains more than 10,000 events.');
      }
      for (final row in eventsRaw) {
        if (row is! Map) {
          throw const FormatException('An event entry is malformed.');
        }
        final title = row['title'];
        final venue = row['venue'];
        final date = row['date'];
        if (title is! String || venue is! String || date is! String) {
          throw const FormatException('Event text fields are missing.');
        }
        final categoryRaw = row['category'];
        final category = EventCategory.values.firstWhere(
          (c) => c.name == (categoryRaw is String ? categoryRaw : 'personal'),
          orElse: () => EventCategory.personal,
        );
        final remindMeRaw = row['reminder_enabled'];
        final remindMe = remindMeRaw is num ? remindMeRaw != 0 : true;
        final leadRaw = row['lead_minutes'];
        final leadMinutes = leadRaw is num ? leadRaw.toInt() : eventDefaultLeadMinutes;
        final item = EventItem(
          title: title,
          venue: venue,
          date: date,
          startMinutes: number(row, 'start_minutes'),
          remindMe: remindMe,
          leadMinutes: leadMinutes,
          category: category,
        );
        try {
          DatabaseHelper.validateEvent(item);
        } on ArgumentError catch (error) {
          throw FormatException(error.message?.toString() ?? 'Invalid event.');
        }
        events.add(item);
      }
    }

    return ScheduleBackup(classes: classes, events: events);
  }
}