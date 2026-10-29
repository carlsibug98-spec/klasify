// Throwaway diagnostic: trace sectioned parser on exact t2a texts.
// ignore_for_file: avoid_print

import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';

const chatSingle = '''
Math Department
Faculty group | 12 members
Today 9:12 AM
Here is the final room schedule for
next week, please share with students:
Mon - Math 8:00-9:00 Room 5 / Science
10:30-12:00 Lab 3
Tue - English 9:00-10:30 Room 2 /
History 1:00 PM-2:30 PM Room 7
Wed - Physics 8:00-9:30 Lab 1 / Art
11:00-12:30 Studio 1
Thu - Music 10:00-11:00 Room 4
Fri - PE 7:30-9:00 Gym / Computer
10:00-11:30 IT Lab
9:14 AM
Copy, thanks! Sharing now.
Lab 3 projector fixed btw
''';

const noticeMixed = '''
e e
FIRE DRILL PTA MEETING
Friday 10:00 AM e Thursday 4:00 PM - Anne
GRADE 8 - SCHEDULE
MON 7:30-8:30 Homeroom
MON 8:30-10:00 Math
TUE 9:00-10:30 Science e
LOST CANTEEN MENU
WED 8:00-9:30 English
Black jacket near Mon Chicken rice
-
the covered court. THU 10:00-11:30 Music Tue Fish fillet
-
Claim at the office. FRI 8:30-10:00 Social Studies Wed - Palabok
Thu - Mac soup
Fri - Spaghetti
''';

void show(String name, List<SectionedRow> rows) {
  print('== $name  (${rows.length} rows)');
  for (final r in rows) {
    print('  d${r.day} ${r.startMinutes}-${r.endMinutes} [${r.subject}] room=[${r.room}]');
  }
}

void main() {
  show('chat single sectioned', SectionedScheduleParser.parse(chatSingle));
  show('chat single list', SectionedScheduleParser.parse(chatSingle)); // placeholder
  show('notice mixed sectioned', SectionedScheduleParser.parse(noticeMixed));
  final list = TimetableParser.parse(noticeMixed);
  print('== notice mixed list (${list.length} rows)');
  for (final r in list) {
    print('  d${r.day} ${r.startMinutes}-${r.endMinutes} [${r.subject}] room=[${r.room}]');
  }
}
