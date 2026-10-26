import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';

/// Non-timetable schedule import (bench4 patterns): handwritten planners,
/// chat screenshots, emails/memos, notice boards. Each failing pattern in
/// the round-4 benchmark is pinned here as a parser-level expectation, with
/// the exact rendered fixture text (bench4_truth.json text_lines) for the
/// full-photo cases.
void main() {
  group('bench4 planner casual (multi-day header + both-days)', () {
    final text = [
      'week of jan 12',
      'MON',
      'Math quiz review - 8:00-9:30',
      'English essay  10-11:30',
      'TUES + WEDS',
      'Science fair prep  1-3pm (both days)',
      'THURSDAY',
      'Geometry  9-10:30',
      'Library  11-12',
      'FRIDAY',
      'Assembly  8-9',
      'Chess club  2pm-3:30pm',
      'SATURDAY',
      'Basketball  9-11',
    ].join('\n');

    test('parses all 9 truth entries', () {
      final rows = SectionedScheduleParser.parse(text);
      expect(
        describeRows(rows),
        [
          'Math quiz review|1|480|570|Room to confirm',
          'English essay|1|600|690|Room to confirm',
          'Science fair prep|2|780|900|Room to confirm',
          'Science fair prep|3|780|900|Room to confirm',
          'Geometry|4|540|630|Room to confirm',
          'Library|4|660|720|Room to confirm',
          'Assembly|5|480|540|Room to confirm',
          'Chess club|5|840|930|Room to confirm',
          'Basketball|6|540|660|Room to confirm',
        ],
      );
    });

    test('the row above a multi-day header keeps its own section day', () {
      final rows = SectionedScheduleParser.parse(
        'MON\n'
        'English essay 10-11:30\n'
        'TUES + WEDS\n'
        'Science fair prep 1-3pm (both days)',
      );
      // "TUES + WEDS" must flush the open cell BEFORE any of its day
      // tokens reach it; the English essay row stays Monday.
      expect(rows[0].subject, 'English essay');
      expect(rows[0].day, 1);
    });

    test('multi-day header expands a "(both days)" row to every header day', () {
      final rows = SectionedScheduleParser.parse(
        'TUES + WEDS\n'
        'Science fair prep 1-3pm (both days)',
      );
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row.subject, 'Science fair prep');
        expect(row.startMinutes, 13 * 60);
        expect(row.endMinutes, 15 * 60);
      }
      expect(rows[0].day, 2);
      expect(rows[1].day, 3);
      expect(rows.map((r) => r.subject), everyElement(isNot(contains('both'))));
    });

    test('slashed pair header expands the same way', () {
      final rows = SectionedScheduleParser.parse(
        'MON/WED\n'
        'Review 2-4pm (both days)',
      );
      expect(rows, hasLength(2));
      expect(rows[0].day, 1);
      expect(rows[1].day, 3);
      expect(rows.every((r) => r.subject == 'Review'), isTrue);
    });

    test('a plain row under a pair header takes the later header day', () {
      final rows = SectionedScheduleParser.parse(
        'MON + TUE\n'
        'Math 8-9',
      );
      expect(rows, hasLength(1));
      expect(rows.single.day, 2); // matches the single-header convention
      expect(rows.single.subject, 'Math');
      expect(rows.single.startMinutes, 8 * 60);
    });
  });

  group('bench4 chat single msg (day prefix across wrapped multi-class)', () {
    final text = [
      'Here is the final room schedule for',
      'next week, please share with students:',
      ' ',
      'Mon - Math 8:00-9:00 Room 5 / Science',
      '10:30-12:00 Lab 3',
      ' ',
      'Tue - English 9:00-10:30 Room 2 /',
      'History 1:00 PM-2:30 PM Room 7',
      ' ',
      'Wed - Physics 8:00-9:30 Lab 1 / Art',
      '11:00-12:30 Studio 1',
      ' ',
      'Thu - Music 10:00-11:00 Room 4',
      ' ',
      'Fri - PE 7:30-9:00 Gym / Computer',
      '10:00-11:30 IT Lab',
    ].join('\n');

    test('produces the 9 truth rows', () {
      final rows = SectionedScheduleParser.parse(text);
      expect(
        describeRows(rows),
        [
          'Math|1|480|540|Room 5',
          'Science|1|630|720|Lab 3',
          'English|2|540|630|Room 2',
          'History|2|780|870|Room 7',
          'Physics|3|480|570|Lab 1',
          'Art|3|660|750|Studio 1',
          'Music|4|600|660|Room 4',
          'PE|5|450|540|Gym',
          'Computer|5|600|690|IT Lab',
        ],
      );
    });

    test('a day prefix governs every segment after a slash split', () {
      final rows = SectionedScheduleParser.parse(
        'Fri - PE 7:30-9:00 Gym / Computer\n'
        '10:00-11:30 IT Lab',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'PE');
      expect(rows[0].day, 5);
      expect(rows[0].room, 'Gym');
      expect(rows[1].subject, 'Computer');
      expect(rows[1].day, 5);
      expect(rows[1].room, 'IT Lab');
    });

    test('a slash split inside one line shares the line day', () {
      final rows = SectionedScheduleParser.parse(
        'Mon - Math 8:00-9:00 Room 5 / Science\n'
        '10:30-12:00 Lab 3',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'Math');
      expect(rows[0].day, 1);
      expect(rows[0].room, 'Room 5');
      expect(rows[1].subject, 'Science');
      expect(rows[1].day, 1);
      expect(rows[1].startMinutes, 10 * 60 + 30);
      expect(rows[1].room, 'Lab 3');
    });

    test('an open slash before the wrap joins the next line', () {
      final rows = SectionedScheduleParser.parse(
        'Tue - English 9:00-10:30 Room 2 /\n'
        'History 1:00 PM-2:30 PM Room 7',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'English');
      expect(rows[0].day, 2);
      expect(rows[0].room, 'Room 2');
      expect(rows[1].subject, 'History');
      expect(rows[1].day, 2); // not Monday's default
      expect(rows[1].startMinutes, 13 * 60);
      expect(rows[1].room, 'Room 7');
    });

    test('a time range wrapped across lines is rejoined', () {
      final rows = SectionedScheduleParser.parse(
        'Fri - Computer 10:00-\n'
        '11:30 IT Lab',
      );
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Computer');
      expect(rows.single.day, 5);
      expect(rows.single.startMinutes, 10 * 60);
      expect(rows.single.endMinutes, 11 * 60 + 30);
      expect(rows.single.room, 'IT Lab');
    });
  });

  group('bench4 email prose (prose lines, no end time -> miss)', () {
    final text = [
      'Good morning everyone, I hope the break',
      'treated you well. Here is what next week',
      'looks like for our section.',
      'On Monday, Math starts the day at 8:00,',
      'followed by Science at 10:30-12:00 in',
      'Lab 3. Tuesday has English at 9:00-10:30',
      'and then History after lunch, 1:00 PM-',
      '2:30 PM in Room 7.',
      'Wednesday: Physics 8:00-9:30 in Lab 1.',
      'Please bring calculators Thursday for',
      'Geometry at 11:00-12:30, Room 8.',
      'Friday wraps up with Computer 10:00-',
      '11:30 in the IT Lab and Art at',
      '1:00 PM-2:00 PM in Studio 2.',
    ].join('\n');

    test('parses the 7 mentioned classes, prose ramps stay out', () {
      final rows = SectionedScheduleParser.parse(text);
      expect(
        describeRows(rows),
        [
          'Science|1|630|720|Lab 3',
          'English|2|540|630|Room to confirm',
          'History|2|780|870|Room 7',
          'Physics|3|480|570|Lab 1',
          'Geometry|4|660|750|Room 8',
          'Computer|5|600|690|IT Lab',
          'Art|5|780|840|Studio 2',
        ],
      );
    });

    test('"starts the day at 8:00" alone emits nothing', () {
      final rows = SectionedScheduleParser.parse(
        'On Monday, Math starts the day at 8:00,',
      );
      expect(rows, isEmpty);
    });
  });

  group('bench4 email list (IT Lab room, comma runs)', () {
    final text = [
      'Dear students,',
      'Please find your confirmed schedule below.',
      'Monday: Math 101, 8:00 AM - 9:30 AM, Room 201',
      'Monday: Physics, 10:00 AM - 11:30 AM, Lab 3',
      'Tuesday: English, 9:00 AM - 10:30 AM, Room 105',
      'Wednesday: Chemistry, 8:00 AM - 9:00 AM, Lab 2',
      'Wednesday: Statistics, 1:00 PM - 2:30 PM, Room 12',
      'Thursday: Biology, 10:30 AM - 12:00 PM, Lab 1',
      'Friday: Computer Science, 8:00 AM - 9:30 AM, IT Lab',
      'Friday: PE, 2:00 PM - 3:30 PM, Gym',
    ].join('\n');

    test('parses all 8 rows with clean subjects and rooms', () {
      final rows = SectionedScheduleParser.parse(text);
      expect(
        describeRows(rows),
        [
          'Math 101|1|480|570|Room 201',
          'Physics|1|600|690|Lab 3',
          'English|2|540|630|Room 105',
          'Chemistry|3|480|540|Lab 2',
          'Statistics|3|780|870|Room 12',
          'Biology|4|630|720|Lab 1',
          'Computer Science|5|480|570|IT Lab',
          'PE|5|840|930|Gym',
        ],
      );
    });
  });

  group('bench4 notice boards (day-anchored rows; noise stays out)', () {
    test('main note rows all parse', () {
      final rows = SectionedScheduleParser.parse(
        'ROOM 12 - WEEK SCHEDULE\n'
        'MON   8:00 - 9:00   Mathematics\n'
        'MON   9:30 - 11:00   English\n'
        'TUE   8:00 - 9:30   Science\n'
        'TUE   10:00 - 11:30   History\n'
        'WED   9:00 - 10:30   Geography\n'
        'THU   8:00 - 9:00   Art\n'
        'FRI   10:00 - 11:30   Music\n'
        'FRI   1:00 PM - 2:30 PM   PE',
      );
      expect(
        describeRows(rows),
        [
          'Mathematics|1|480|540|Room to confirm',
          'English|1|570|660|Room to confirm',
          'Science|2|480|570|Room to confirm',
          'History|2|600|690|Room to confirm',
          'Geography|3|540|630|Room to confirm',
          'Art|4|480|540|Room to confirm',
          'Music|5|600|690|Room to confirm',
          'PE|5|780|870|Room to confirm',
        ],
      );
    });

    test('mixed note: only the 6 real classes parse', () {
      final rows = SectionedScheduleParser.parse(
        'GRADE 8 - SCHEDULE\n'
        'MON 7:30-8:30 Homeroom\n'
        'MON 8:30-10:00 Math\n'
        'TUE 9:00-10:30 Science\n'
        'WED 8:00-9:30 English\n'
        'THU 10:00-11:30 Music\n'
        'FRI 8:30-10:00 Social Studies',
      );
      expect(
        describeRows(rows),
        [
          'Homeroom|1|450|510|Room to confirm',
          'Math|1|510|600|Room to confirm',
          'Science|2|540|630|Room to confirm',
          'English|3|480|570|Room to confirm',
          'Music|4|600|690|Room to confirm',
          'Social Studies|5|510|600|Room to confirm',
        ],
      );
    });

    test('fire drill and PTA notices never become classes', () {
      expect(
        SectionedScheduleParser.parse('FRI 10:00-11:00 FIRE DRILL'),
        isEmpty,
      );
      expect(
        SectionedScheduleParser.parse('THU 4:00-5:00 PM PTA meeting'),
        isEmpty,
      );
      expect(
        SectionedScheduleParser.parse(
          'Notice: PTA assembly and fire drill this Friday, 10:00 AM.',
        ),
        isEmpty,
      );
    });

    test('UI chat timestamps are rejected', () {
      expect(SectionedScheduleParser.parse('Today 9:12 AM'), isEmpty);
      expect(SectionedScheduleParser.parse('Yesterday 10:11 PM'), isEmpty);
      expect(
        SectionedScheduleParser.parse(
          'Today 9:12 AM\n'
          'Mon - Math 8:00-9:00 Room 5',
        ),
        hasLength(1),
      );
      expect(SectionedScheduleParser.parse('Sent from my iPhone'), isEmpty);
    });
  });

  group('bench4 planner journal (subject debris, span cap)', () {
    final text = [
      'my week ~ term 2',
      'MONDAY',
      'Algebra  8-9',
      'Biology lab  10:30-12',
      'TUESDAY',
      'English  9-10:30',
      'History  1pm-2:30pm',
      'WEDNESDAY',
      'Chemistry  8-9',
      'Geometry  11-12:30',
      'THURSDAY',
      'Physics  9:30-11',
      'Music  1:30pm-2:30pm',
      'FRIDAY',
      'P.E.  7:30-9',
      'Computer  10-11:30',
      'SATURDAY',
      'Art workshop  9-11',
    ].join('\n');

    test('parses all 11 truth entries', () {
      final rows = SectionedScheduleParser.parse(text);
      expect(rows, hasLength(11));
      expect(
        rows.map((r) => '${r.subject}|${r.day}|${r.startMinutes}|${r.endMinutes}'),
        [
          'Algebra|1|480|540',
          'Biology lab|1|630|720',
          'English|2|540|630',
          'History|2|780|870',
          'Chemistry|3|480|540',
          'Geometry|3|660|750',
          'Physics|4|570|660',
          'Music|4|810|870',
          'P.E.|5|450|540',
          'Computer|5|600|690',
          'Art workshop|6|540|660',
        ],
      );
    });

    test('stray dots around times are cleaned from subjects', () {
      final rows = SectionedScheduleParser.parse(
        'TUESDAY\n'
        'English . 9-10:30\n'
        'History .1pm-2:30pm',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'English');
      expect(rows[0].startMinutes, 9 * 60);
      expect(rows[1].subject, 'History');
      expect(rows[1].startMinutes, 13 * 60);
      expect(rows[1].day, 2);
    });

    test('spans up to 8 hours are accepted (Art workshop misread 4-11)', () {
      final rows = SectionedScheduleParser.parse(
        'SATURDAY\n'
        'Art workshop 4-11',
      );
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Art workshop');
      expect(rows.single.day, 6);
      // "4-11" has no meridiem, so the literal AM reading stands (4:00
      // 11:00) — the pinned behaviour is that a 7-hour span is accepted
      // as a row at all (the old 6-hour cap dropped it), not which
      // meridiem the author meant.
      expect(rows.single.startMinutes, 4 * 60);
      expect(rows.single.endMinutes, 11 * 60);
    });
  });

  group('bench4 chat bubbles (guard: self-contained rows keep passing)', () {
    test('all 7 truth rows parse with rooms', () {
      final rows = SectionedScheduleParser.parse(
        'Ms. Santos (Adviser)\n'
        'Monday: Algebra 8:00-9:30 Room 201\n'
        'Monday: Science 10:30-12:00 Room 3\n'
        'Tuesday: World History 10:00-11:30 Room 105\n'
        'Wednesday: Chemistry 8:00-9:00 Lab 2\n'
        'Thursday: English Lit 1:00 PM-2:30 PM Room 9\n'
        'Friday: PE 7:30-9:00 Gym\n'
        'Friday: Computer 10:00-11:30 IT Lab',
      );
      expect(
        describeRows(rows),
        [
          'Algebra|1|480|570|Room 201',
          'Science|1|630|720|Room 3',
          'World History|2|600|690|Room 105',
          'Chemistry|3|480|540|Lab 2',
          'English Lit|4|780|870|Room 9',
          'PE|5|450|540|Gym',
          'Computer|5|600|690|IT Lab',
        ],
      );
    });
  });

  group('single-letter and separator debris', () {
    test('trailing single letters are dropped from subjects', () {
      final rows = SectionedScheduleParser.parse('THU 16:00-17:00 Science e');
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Science');
      expect(rows.single.day, 4);
    });

    test('comma runs left by removed times vanish', () {
      final rows = SectionedScheduleParser.parse(
        'Fri: Computer Science, 8:00 AM - 9:30 AM, IT Lab',
      );
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Computer Science');
      expect(rows.single.room, 'IT Lab');
      expect(rows.single.day, 5);
    });
  });
}

/// Compact row signature for tight failure messages:
/// subject|day|HHMM|HHMM|room
List<String> describeRows(List<SectionedRow> rows) => [
  for (final r in rows)
    '${r.subject}|${r.day}|${r.startMinutes}|${r.endMinutes}|${r.room}',
];
