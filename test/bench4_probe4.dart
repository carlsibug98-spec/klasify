// Throwaway diagnostic: isolate which line flips the covered-court row to d4.
// ignore_for_file: avoid_print

import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';

const base = '''
FIRE DRILL PTA MEETING
Friday 10:00 AM e Thursday 4:00 PM - Anne
GRADE 8 - SCHEDULE
MON 7:30-8:30 Homeroom
MON 8:30-10:00 Math
TUE 9:00-10:30 Science e
WED 8:00-9:30 English
Black jacket near Mon Chicken rice
-
the covered court. THU 10:00-11:30 Music Tue Fish fillet
-
Claim at the office. FRI 8:30-10:00 Social Studies Wed - Palabok
''';

void show(String name, String text) {
  final rows = SectionedScheduleParser.parse(text);
  print('== $name');
  for (final r in rows) {
    print('  d${r.day} ${r.startMinutes}-${r.endMinutes} [${r.subject}]');
  }
}

void main() {
  show('base', base);
  show('no black jacket', base.replaceFirst('Black jacket near Mon Chicken rice\n', ''));
  show('MMMM header before covered', base.replaceFirst(
      'Black jacket near Mon Chicken rice\n-\n',
      'MMMM header before covered\nTHURSDAY\n'));
  show('covered without Tue junk', base.replaceAll(' Tue Fish fillet', ''));
  show('no dash-only lines', base.replaceAll('\n-\n', '\n'));
}
