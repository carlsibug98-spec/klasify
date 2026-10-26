// Throwaway diagnostic: compare sectioned vs list parser on bench4 texts.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';

String fmtSectioned(SectionedRow r) =>
    'd${r.day} ${r.startMinutes}-${r.endMinutes} [${r.subject}] room=[${r.room}]';

String fmtList(ParsedTimetableRow r) =>
    'd${r.day} ${r.startMinutes}-${r.endMinutes} [${r.subject}] room=[${r.room}]';

void main() {
  final truth =
      jsonDecode(File('test/fixtures/bench4_truth.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final photo in truth.keys) {
    final text = (truth[photo]['text_lines'] as List).join('\n');
    final sec = SectionedScheduleParser.parse(text);
    final list = TimetableParser.parse(text);
    print('\n######## $photo  sectioned=${sec.length} list=${list.length}');
    print('-- sectioned');
    for (final r in sec) {
      print('  ${fmtSectioned(r)}');
    }
    print('-- list');
    for (final r in list) {
      print('  ${fmtList(r)}');
    }
  }
}
