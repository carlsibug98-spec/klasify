import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:klasify/features/schedule_import/utils/schedule_text_parser.dart';

void main() {
  test('parses a row when both times include AM/PM', () {
    final rows = TimetableParser.parse(
      'Monday Mathematics 8:00 AM - 9:30 AM Room 101',
    );
    expect(rows, hasLength(1));
    expect(rows.single.subject, contains('Mathematics'));
    expect(rows.single.day, 1);
    expect(rows.single.startMinutes, 480);
    expect(rows.single.endMinutes, 570);
    expect(rows.single.room, 'Room 101');
  });

  test('infers PM for an omitted end meridiem when needed', () {
    final rows = TimetableParser.parse('Tue Programming 11:00 AM - 1:00 Lab 2');
    expect(rows, hasLength(1));
    expect(rows.single.startMinutes, 660);
    expect(rows.single.endMinutes, 780);
  });

  test('parses abbreviated weekdays and dash variants', () {
    final rows = TimetableParser.parse(
      'Thu - English - 1:00 PM to 2:30 PM - Room 202',
    );
    expect(rows, hasLength(1));
    expect(rows.single.day, 4);
    expect(rows.single.startMinutes, 780);
    expect(rows.single.endMinutes, 870);
  });

  test('deduplicates identical OCR lines', () {
    final rows = TimetableParser.parse(
      'Friday Biology 8:00 AM - 9:00 AM Room 4\nFriday Biology 8:00 AM - 9:00 AM Room 4',
    );
    expect(rows, hasLength(1));
  });

  test('uses a standalone weekday heading for following timetable rows', () {
    final rows = TimetableParser.parse('''
Monday
Mathematics 8:00 AM - 9:30 AM Room 101
Science 10:00 AM - 11:00 AM Room 202
Tuesday
Programming 1:00 PM - 3:00 PM Lab 2
''');
    expect(rows, hasLength(3));
    expect(rows[0].day, 1);
    expect(rows[1].day, 1);
    expect(rows[2].day, 2);
  });

  test('duplicates a class across multiple explicit weekdays', () {
    final rows = TimetableParser.parse(
      'Mon Wed Fri Mathematics 8:00 AM - 9:00 AM Room 101',
    );
    expect(rows.map((r) => r.day).toList(), [1, 3, 5]);
  });

  test('parses OCR-style separators with compact weekday groups', () {
    final rows = TimetableParser.parse(
      'MWF | 8:00 AM – 9:30 AM | biology | Room 14',
    );
    expect(rows.map((row) => row.day).toList(), [1, 3, 5]);
    expect(rows.first.subject.toLowerCase(), contains('biology'));
    expect(rows.first.room, 'Room 14');
  });

  test('does not accept malformed or backwards time ranges', () {
    expect(
      TimetableParser.parse('Monday Math 9:00 AM - 8:00 AM Room 1'),
      isEmpty,
    );
    expect(
      TimetableParser.parse('Monday Math 25:90 AM - 8:00 AM Room 1'),
      isEmpty,
    );
  });

  test('parses 24-hour time ranges', () {
    final rows = TimetableParser.parse(
      'Monday Mathematics 08:00-09:30 Room 101',
    );
    expect(rows, hasLength(1));
    expect(rows.single.startMinutes, 480);
    expect(rows.single.endMinutes, 570);
  });

  test('parses a one-letter Thursday heading', () {
    final rows = TimetableParser.parse(
      'R Mathematics 8:00 AM - 9:00 AM Room 101',
    );

    expect(rows, hasLength(1));
    expect(rows.single.day, 4);
  });

  test('parses 12-hour range where end omits AM/PM', () {
    final rows = TimetableParser.parse(
      'Monday Mathematics 8:00-9:30 AM Room 101',
    );
    expect(rows, hasLength(1));
    expect(rows.single.startMinutes, 480);
    expect(rows.single.endMinutes, 570);
  });

  test('does not mistake Computer Lab Programming for a room', () {
    final rows = TimetableParser.parse(
      'Monday Computer Lab Programming 8:00 AM - 9:30 AM',
    );
    expect(rows, hasLength(1));
    expect(
      rows.single.subject.toLowerCase(),
      contains('computer lab programming'),
    );
    expect(rows.single.room, 'Room to confirm');
  });

  group('compact military times', () {
    test('parses compact military time ranges', () {
      final rows = TimetableParser.parse('MWF 0800-0930 Mathematics Room 12');
      expect(rows.map((row) => row.day).toList(), [1, 3, 5]);
      expect(rows.first.startMinutes, 480);
      expect(rows.first.endMinutes, 570);
    });

    test('parses compact military times across the meridiem boundary', () {
      final rows = TimetableParser.parse('Tuesday Seminar 1330-1500 Room 5');
      expect(rows, hasLength(1));
      expect(rows.single.day, 2);
      expect(rows.single.startMinutes, 13 * 60 + 30);
      expect(rows.single.endMinutes, 15 * 60);
    });

    test('does not treat year ranges as class times', () {
      expect(TimetableParser.parse('Semester 2025-2026 enrollment'), isEmpty);
      expect(TimetableParser.parse('Catalogue 2025–2026'), isEmpty);
    });

    test('ignores implausibly short time ranges', () {
      expect(TimetableParser.parse('Monday Math 9:00 - 9:10 Room 1'), isEmpty);
    });
  });

  group('period-number ranges', () {
    test('parses P3-P4 rows with assumed nominal times and a review flag', () {
      final rows = TimetableParser.parse('Monday\nMATH 101 P3-P4 Room 5');
      expect(rows, hasLength(1));
      expect(rows.single.day, 1);
      expect(rows.single.subject, 'MATH 101');
      expect(rows.single.room, 'Room 5');
      // P3 starts 10:00; P4 ends 12:00 (inclusive end).
      expect(rows.single.startMinutes, 10 * 60);
      expect(rows.single.endMinutes, 12 * 60);
      expect(rows.single.ocrConfidence, .74);
    });

    test('parses spelled-out period pairs', () {
      final rows = TimetableParser.parse('TR Period 1 - Period 2 Physics Lab');
      expect(rows.map((row) => row.day).toList(), [2, 4]);
      expect(rows.first.startMinutes, 8 * 60);
      expect(rows.first.endMinutes, 10 * 60);
    });

    test('period pair pattern requires the prefix on both tokens', () {
      // "P3-4" is ambiguous with clock-like ranges, so the pair pattern
      // refuses it; PeriodTimes never produces assumed times for it.
      expect(const PeriodTimes().parsePair('MATH 101 P3-4'), isNull);
      expect(const PeriodTimes().parsePair('MATH 101 P3-P4'), isNotNull);
      expect(const PeriodTimes().parsePair('MATH 101 P3-P4')?.start, 600);
      expect(const PeriodTimes().parsePair('MATH 101 P3-P4')?.end, 720);
    });

    test('rejects out-of-range and reversed period pairs', () {
      expect(TimetableParser.parse('Monday Club P9-P2'), isEmpty);
      expect(TimetableParser.parse('Monday Watch P13-P14'), isEmpty);
    });
  });

  group('multi-class lines', () {
    test('splits a slash-joined line into one row per time range', () {
      final rows = TimetableParser.parse(
        'MON - Algebra 8AM-9AM / Science 10AM-11AM',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'Algebra');
      expect(rows[0].day, 1);
      expect(rows[0].startMinutes, 8 * 60);
      expect(rows[0].endMinutes, 9 * 60);
      expect(rows[1].subject, 'Science');
      expect(rows[1].day, 1);
      expect(rows[1].startMinutes, 10 * 60);
      expect(rows[1].endMinutes, 11 * 60);
    });

    test('keeps the room with the class it follows', () {
      final rows = TimetableParser.parse(
        'MON Math 8:00-9:00 Room 204 / Science 9:00-10:00 Room 205',
      );
      expect(rows, hasLength(2));
      expect(rows[0].subject, 'Math');
      expect(rows[0].day, 1);
      expect(rows[0].room, 'Room 204');
      expect(rows[1].subject, 'Science');
      expect(rows[1].day, 1);
      expect(rows[1].room, 'Room 205');
    });

    test('day tokens before each range stay with that range', () {
      final rows = TimetableParser.parse('MON Algebra 8-9 / TUE Science 9-10');
      expect(rows, hasLength(2));
      expect(rows[0].day, 1);
      expect(rows[1].day, 2);
    });

    test('connective between two ranges of one class makes no junk row', () {
      final rows = TimetableParser.parse('MON Math 8:00-9:00 and 10:00-11:00');
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Math');
      expect(rows.single.day, 1);
      expect(rows.single.startMinutes, 8 * 60);
      expect(rows.single.endMinutes, 9 * 60);
    });

    test('year-range noise before a class still yields the class', () {
      final rows = TimetableParser.parse('MON S.Y. 2025-2026 Math 8:00-9:00');
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Math');
      expect(rows.single.day, 1);
      expect(rows.single.startMinutes, 8 * 60);
      expect(rows.single.endMinutes, 9 * 60);
    });

    test('active day from a heading line applies to every range', () {
      final rows = TimetableParser.parse(
        'WEDNESDAY\nAlgebra 8AM-9AM / Science 10AM-11AM',
      );
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.day == 3), isTrue);
    });

    test('PM on the end alone carries a bare start into the afternoon', () {
      final rows = TimetableParser.parse('FRIDAY Club 1-3pm');
      expect(rows, hasLength(1));
      expect(rows.single.startMinutes, 13 * 60);
      expect(rows.single.endMinutes, 15 * 60);

      final rows2 = TimetableParser.parse('MON Club meeting 1:00-2:30 PM');
      expect(rows2, hasLength(1));
      expect(rows2.single.startMinutes, 13 * 60);
      expect(rows2.single.endMinutes, 14 * 60 + 30);
    });

    test('bare hours with no meridiem anywhere stay morning', () {
      final rows = TimetableParser.parse('MON Math 8-9');
      expect(rows.single.startMinutes, 8 * 60);
      expect(rows.single.endMinutes, 9 * 60);

      final rows2 = TimetableParser.parse('MON Science 10:30-12');
      expect(rows2.single.startMinutes, 10 * 60 + 30);
      expect(rows2.single.endMinutes, 12 * 60);
    });

    test('explicit PM end at noon does not bump a morning start', () {
      final rows = TimetableParser.parse('THU Art class 10:30-12:00 PM');
      expect(rows.single.startMinutes, 10 * 60 + 30);
      expect(rows.single.endMinutes, 12 * 60);
    });

    test('Tues/Weds abbreviations are recognized as weekdays', () {
      expect(TimetableParser.parse('TUES Math 8-9').single.day, 2);
      expect(TimetableParser.parse('WEDS Science 9-10').single.day, 3);
      expect(TimetableParser.parse('Tues Math 8-9').single.day, 2);
      expect(TimetableParser.parse('Weds Science 9-10').single.day, 3);
    });

    test('a class named after its venue is not dropped', () {
      final rows = TimetableParser.parse('THURSDAY\nLibrary 11-12');
      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Library');
      expect(rows.single.day, 4);
      expect(rows.single.startMinutes, 11 * 60);
      expect(rows.single.endMinutes, 12 * 60);
    });
  });
}
