// This is a throwaway probe: printing the parse results is the whole point.
// ignore_for_file: avoid_print

import 'package:klasify/features/schedule_import/utils/schedule_text_parser.dart';
import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';

void main() {
  for (final s in ['Library', 'Gym', 'Library 11-12']) {
    final d = ScheduleTextDetails.parse(s);
    print('details("$s"): subject="${d.subject}" room="${d.room}"');
  }
  const casual =
      'week of jan 12\n'
      'MON\n'
      'Math quiz review - 8:00-9:30\n'
      'English essay  10-11:30\n'
      'TUES + WEDS\n'
      'Science fair prep  1-3pm (both days)\n'
      'THURSDAY\n'
      'Geometry  9-10:30\n'
      'Library  11-12\n'
      'FRIDAY\n'
      'Assembly  8-9\n'
      'Chess club  2pm-3:30pm\n'
      'SATURDAY\n'
      'Basketball  9-11';
  final sec = SectionedScheduleParser.parse(casual);
  print('--- sectioned: ${sec.length} rows');
  for (final r in sec) {
    print(
      '  ${r.subject} day=${r.day} '
      '${(r.startMinutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(r.startMinutes % 60).toString().padLeft(2, '0')}-'
      '${(r.endMinutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(r.endMinutes % 60).toString().padLeft(2, '0')} '
      'assumptions=${r.assumptions}',
    );
  }
  final list = TimetableParser.parse(casual);
  print('--- list: ${list.length} rows');
  for (final r in list) {
    print('  ${r.subject} day=${r.day} ${r.startMinutes}-${r.endMinutes}');
  }

  // isolate: does a plain second entry under a day header survive?
  const twoEntries =
      'THURSDAY\n'
      'Geometry  9-10:30\n'
      'Library  11-12\n';
  final secTwo = SectionedScheduleParser.parse(twoEntries);
  print(
    '--- two entries under one header: '
    'sectioned=${secTwo.length} list=${TimetableParser.parse(twoEntries).length}',
  );
  for (final r in secTwo) {
    print('  sec: ${r.subject} day=${r.day} ${r.startMinutes}-${r.endMinutes}');
  }
  for (final r in TimetableParser.parse(twoEntries)) {
    print('  lst: ${r.subject} day=${r.day} ${r.startMinutes}-${r.endMinutes}');
  }
  const libOnly =
      'THURSDAY\n'
      'Library  11-12\n';
  for (final r in TimetableParser.parse(libOnly)) {
    print(
      '  lib-only lst: ${r.subject} day=${r.day} '
      '${r.startMinutes}-${r.endMinutes}',
    );
  }
  const geoOnly =
      'THURSDAY\n'
      'Geometry  9-10:30\n';
  for (final r in TimetableParser.parse(geoOnly)) {
    print(
      '  geo-only lst: ${r.subject} day=${r.day} '
      '${r.startMinutes}-${r.endMinutes}',
    );
  }

  // isolate: TUES + WEDS header line
  const abbr =
      'TUES + WEDS\n'
      'Science fair prep  1-3pm\n';
  final secAbbr = SectionedScheduleParser.parse(abbr);
  print('--- TUES + WEDS header: sectioned=${secAbbr.length}');
  for (final r in secAbbr) {
    print('  ${r.subject} day=${r.day} ${r.startMinutes}-${r.endMinutes}');
  }
  const wedsOnly =
      'WEDS\n'
      'Science fair prep  1-3pm\n';
  print(
    '--- WEDS header: sectioned=${SectionedScheduleParser.parse(wedsOnly).length} '
    'list=${TimetableParser.parse(wedsOnly).length}',
  );
  const tuesOnly =
      'TUES\n'
      'Science fair prep  1-3pm\n';
  print(
    '--- TUES header: sectioned=${SectionedScheduleParser.parse(tuesOnly).length} '
    'list=${TimetableParser.parse(tuesOnly).length}',
  );

  const tuesStd =
      'TUES\n'
      'Science fair prep 1:00 PM-3:00 PM\n';
  for (final r in SectionedScheduleParser.parse(tuesStd)) {
    print(
      '  tues-std sec: ${r.subject} day=${r.day} '
      '${r.startMinutes}-${r.endMinutes}',
    );
  }
  const monBare =
      'MON\n'
      'Math 8-9\n';
  for (final r in SectionedScheduleParser.parse(monBare)) {
    print(
      '  mon-bare sec: ${r.subject} day=${r.day} '
      '${r.startMinutes}-${r.endMinutes}',
    );
  }
  const monBare2 =
      'MONDAY\n'
      'Math 8:00-9:00\n';
  for (final r in SectionedScheduleParser.parse(monBare2)) {
    print(
      '  mon-std sec: ${r.subject} day=${r.day} '
      '${r.startMinutes}-${r.endMinutes}',
    );
  }
  const wedsHdr =
      'WEDS\n'
      'Math 8:00-9:00\n';
  for (final r in SectionedScheduleParser.parse(wedsHdr)) {
    print(
      '  weds-std sec: ${r.subject} day=${r.day} '
      '${r.startMinutes}-${r.endMinutes}',
    );
  }
}
