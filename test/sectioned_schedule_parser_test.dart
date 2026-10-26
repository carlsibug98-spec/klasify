import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SectionedScheduleParser', () {
    test('self-contained list lines keep every field (dark theme)', () {
      final rows = SectionedScheduleParser.parse(
        'TIMETABLE // SEMESTER B\n'
        'TUE  09:00-10:30  Databases  Room 12  Prof. J. Sarmiento\n'
        'FRI  10:00-11:30  Linear Algebra  Room 5  Prof. R. DeJesus',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'Databases');
      expect(rows[0].day, 2);
      expect(rows[0].startMinutes, 9 * 60);
      expect(rows[0].endMinutes, 10 * 60 + 30);
      expect(rows[0].room, 'Room 12');
      expect(rows[0].professor, 'J. Sarmiento');
      expect(rows[0].assumptions, isEmpty);
    });

    test('day sections carry the weekday to day-less class lines', () {
      final rows = SectionedScheduleParser.parse(
        'Weekly Class Plan\n'
        'Monday\n'
        '11:00 - 12:30   Computer Networks  (Room 5)  -  Prof. J. Sarmiento\n'
        '15:00 - 16:30   Physics Lab  (Lab 3)  -  Prof. R. DeJesus\n'
        'Tuesday\n'
        '16:00 - 17:30   Academic Writing  (Room 12)  -  Prof. K. Cruz',
      );
      expect(rows, hasLength(3));
      expect(rows[0].day, 1);
      expect(rows[0].subject, 'Computer Networks');
      expect(rows[0].room, 'Room 5');
      expect(rows[0].professor, 'J. Sarmiento');
      expect(rows[2].day, 2);
    });

    test('weekday header band engages slot mode with column-order days', () {
      final rows = SectionedScheduleParser.parse(
        'FACULTY TEACHING SCHEDULE\n'
        'MON\nTUE\nWED\nTHU\nFRI\n'
        'Prof. R. DeJesus\n'
        'Academic Writing\n'
        'Studio 1  10:00-11:30\n'
        'No class\n'
        'Physics Lab\n'
        'Room 5  12:00-13:30\n'
        'No class\n'
        'No class',
      );
      expect(rows, hasLength(2));
      expect(rows[0].day, 1);
      expect(rows[0].subject, 'Academic Writing');
      expect(rows[0].room, 'Studio 1');
      expect(rows[0].professor, 'R. DeJesus');
      expect(rows[1].day, 3);
      expect(rows[1].subject, 'Physics Lab');
      expect(rows[1].professor, 'R. DeJesus');
    });

    test('joined OCR header bands still engage slot mode', () {
      final rows = SectionedScheduleParser.parse(
        'MON | TUE | WED | THU | FRI\n'
        'Prof. R. DeJesus\n'
        'Academic Writing\n'
        'Studio 1  10:00-11:30\n'
        'No class\n'
        'Physics Lab\n'
        'Room 5  12:00-13:30\n'
        'No class\n'
        'No class',
      );
      expect(rows, hasLength(2));
      expect(rows[0].day, 1);
      expect(rows[1].day, 3);
    });

    test('time-rail rows label sibling cells and reset the column cycle', () {
      final rows = SectionedScheduleParser.parse(
        'CLASS SCHEDULE - WEEK 1\n'
        'Time\nMon\nWed\nFri\n'
        '08:00-10:00\n'
        'Academic Writing\n'
        'Room 5  |  Prof. L. Santos\n'
        '10:00-12:00\n'
        'Calculus II\n'
        'Room 5  |  Prof. L. Santos\n'
        'Data Structures\n'
        'Room 2  |  Prof. A. Reyes\n'
        '12:00-14:00\n'
        'Calculus II\n'
        'Lab 3  |  Prof. K. Cruz',
      );
      expect(rows, hasLength(4));
      expect(rows[0].day, 1);
      expect(rows[0].startMinutes, 8 * 60);
      expect(rows[0].endMinutes, 10 * 60);
      expect(rows[1].day, 1);
      expect(rows[1].startMinutes, 10 * 60);
      // Sibling cell in the same row: inherits the row label time.
      expect(rows[2].subject, 'Data Structures');
      expect(rows[2].day, 3);
      expect(rows[2].startMinutes, 10 * 60);
      expect(rows[2].endMinutes, 12 * 60);
      // Next row restarts the cycle at Monday.
      expect(rows[3].day, 1);
      expect(rows[3].startMinutes, 12 * 60);
    });

    test('exam records take the weekday from the date line', () {
      final rows = SectionedScheduleParser.parse(
        'END-OF-TERM EXAMINATION TIMETABLE\n'
        'Date\nTime\nSubject\nRoom\nProfessor\n'
        'Nov 07 (Thu)\n'
        '13:30 - 15:30\n'
        'Statistics\n'
        'Main Hall\n'
        'Prof. T. Lim',
      );
      expect(rows, hasLength(1));
      expect(rows[0].day, 4);
      expect(rows[0].subject, 'Statistics');
      expect(rows[0].startMinutes, 13 * 60 + 30);
      expect(rows[0].endMinutes, 15 * 60 + 30);
      expect(rows[0].room, 'Main Hall');
      expect(rows[0].professor, 'T. Lim');
      expect(rows[0].assumptions, isNotEmpty);
      expect(rows[0].ocrConfidence, 0.74);
    });

    test('single printed times become one-hour classes, flagged', () {
      final rows = SectionedScheduleParser.parse(
        'my timetable :)\n'
        'Mon  09:00  Art History  Room 12  Prof. L. Santos\n'
        'Tue  15:00  Calculus II  Main Hall  Prof. B. Mallari',
      );
      expect(rows, hasLength(2));
      expect(rows[0].day, 1);
      expect(rows[0].startMinutes, 9 * 60);
      expect(rows[0].endMinutes, 10 * 60);
      expect(rows[0].assumptions, contains(contains('start time')));
    });

    test('card layouts: subject, time+room, professor on stacked lines', () {
      final rows = SectionedScheduleParser.parse(
        'My Classes This Week\n'
        'Monday\n'
        'Calculus II\n'
        '11:00  Room 5\n'
        'Prof. T. Lim\n'
        'Art History\n'
        '11:00  Studio 1\n'
        'Prof. M. Panlaqui',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'Calculus II');
      expect(rows[0].room, 'Room 5');
      expect(rows[0].professor, 'T. Lim');
      expect(rows[0].startMinutes, 11 * 60);
      expect(rows[1].subject, 'Art History');
      expect(rows[1].room, 'Studio 1');
    });

    test('tables without a day column default to Monday, flagged', () {
      final rows = SectionedScheduleParser.parse(
        'Class Schedule - Semester 1\n'
        'Time\nSubject\nRoom\nProfessor\n'
        '15:00-16:30\nDatabases\nRoom 5\nProf. R. DeJesus\n'
        '12:00-13:30\nAcademic Writing\nRoom 5\nProf. B. Mallari',
      );
      expect(rows, hasLength(2));
      expect(rows[0].day, 1);
      expect(rows[0].subject, 'Databases');
      expect(rows[0].assumptions, isNotEmpty);
      expect(rows[1].subject, 'Academic Writing');
      expect(rows[1].startMinutes, 12 * 60);
    });

    test('calendar dates map to weekdays by grid position', () {
      final rows = SectionedScheduleParser.parse(
        'OCTOBER CLASS CALENDAR\n'
        'Sun\nMon\nTue\nWed\nThu\nFri\nSat\n'
        '1\n'
        '2\n'
        '13:30-14:30\n'
        'Ethics in Tech\n'
        'Room 2\n'
        'R. DeJesus\n'
        '3\n'
        '09:00-10:00\n'
        'Academic Writing\n'
        'Lab 3\n'
        'R. DeJesus',
      );
      expect(rows, hasLength(2));
      // Date 2 sits in the Mon column of a Sunday-first grid.
      expect(rows[0].day, 1);
      expect(rows[0].subject, 'Ethics in Tech');
      expect(rows[0].professor, 'R. DeJesus');
      expect(rows[1].day, 2);
      expect(rows[1].room, 'Lab 3');
    });

    test('period rows reset the slot counter per period', () {
      final rows = SectionedScheduleParser.parse(
        'Week A Timetable\n'
        'Mon\nTue\nWed\nThu\nFri\n'
        'P1\n'
        'Academic Writing\n'
        '08:00-09:00\n'
        'Main Hall\n'
        'Prof. R. DeJesus\n'
        'Linear Algebra\n'
        '16:00-17:30\n'
        'Lab 3\n'
        'Prof. J. Sarmiento\n'
        'P2\n'
        'Data Structures\n'
        '10:30-12:00\n'
        'Main Hall\n'
        'Prof. M. Panlaqui',
      );
      expect(rows, hasLength(3));
      expect(rows[0].day, 1);
      expect(rows[1].day, 2);
      expect(rows[2].day, 1); // P2 restarts the cycle
      expect(rows[2].subject, 'Data Structures');
    });

    test('hour rail ticks never become class times', () {
      final rows = SectionedScheduleParser.parse(
        'MON\nTUE\nWED\nTHU\nFRI\n'
        '7:00\n8:00\n9:00\n10:00\n'
        'Calculus II\nRoom 5\nProf. R. DeJesus\n'
        'Data Structures\nStudio 1\nProf. M. Panlaqui',
      );
      // No cell ever receives a time, so nothing can be emitted: the geometry
      // path (grid scanner) owns this layout.
      expect(rows, isEmpty);
    });

    test('Weds and Tues section headers set the active day', () {
      expect(
        SectionedScheduleParser.parse('WEDS\nMath 8:00-9:00').single.day,
        3,
      );
      expect(
        SectionedScheduleParser.parse('Tues\nMath 8:00-9:00').single.day,
        2,
      );
    });

    test('casual PM-only range keeps its section day', () {
      final rows = SectionedScheduleParser.parse(
        'TUES\nScience fair prep 1-3pm',
      );
      expect(rows, hasLength(1));
      expect(rows.single.day, 2);
      expect(rows.single.startMinutes, 13 * 60);
      expect(rows.single.endMinutes, 15 * 60);
    });
  });
}
