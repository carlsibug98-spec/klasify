import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/cor_schedule_parser.dart';
import 'package:klasify/features/schedule_import/utils/parse_chain.dart';

void main() {
  group('CorScheduleParser', () {
    test('reads code, units, time/day, room and faculty on each row', () {
      const text = '''
CERTIFICATE OF REGISTRATION
Code Subject Description Units Section Time / Day Room Faculty
IT 104 Data Structures and Algorithm 3 BSIT-2A 08:00 AM - 09:30 AM / Mon Rm 301 Prof. Ana Reyes
IT 202L Database Systems Laboratory 1 BSIT-2A 02:30 PM - 04:30 PM / Tue Lab 2 Prof. Ben Cole
TOTAL UNITS ENROLLED: 4
''';
      final rows = CorScheduleParser.parse(text);
      expect(rows.length, 2);
      expect(rows[0].subject, 'Data Structures and Algorithm');
      expect(rows[0].day, 1);
      expect(rows[0].startMinutes, 8 * 60);
      expect(rows[0].endMinutes, 9 * 60 + 30);
      expect(rows[0].room, 'Rm 301');
      expect(rows[0].professor, 'Prof. Ana Reyes');
      expect(rows[0].assumptions, isEmpty);
      expect(rows[1].day, 2);
      expect(rows[1].startMinutes, 14 * 60 + 30);
      expect(rows[1].room, 'Lab 2');
    });

    test('ignores tba and online cells and keeps the room', () {
      const text =
          'GE C03 Purposive Communication 3 07:00 AM - 08:30 AM / Mon tba Prof. Cara Lim Rm 105';
      final rows = CorScheduleParser.parse(text);
      expect(rows.single.room, 'Rm 105');
      expect(rows.single.professor, 'Prof. Cara Lim');
    });

    test('a time row without a code continues the subject above it', () {
      const text = '''
IT 201 Data Structures and Algorithms 3 BSIT-2A 08:00 AM - 09:30 AM / Mon Rm 301 Prof. Ana Reyes
10:00 AM - 11:30 AM / Wed Rm 301 Prof. Ana Reyes
''';
      final rows = CorScheduleParser.parse(text);
      expect(rows.length, 2);
      expect(rows[1].subject, 'Data Structures and Algorithms');
      expect(rows[1].day, 3);
      expect(rows[1].ocrConfidence, 0.74);
      expect(rows[1].assumptions, isNotEmpty);
    });

    test('a blank-schedule COR emits no classes', () {
      const text = '''
CERTIFICATE OF REGISTRATION
GE C03 Purposive Communication 3
GE C04 Readings in Philippine History 3
IT 104 Data Structures and Algorithm 3
TOTAL NUMBER OF UNITS ENROLLED: 9
''';
      expect(CorScheduleParser.parse(text), isEmpty);
    });

    test('a zero-length or reversed time range is skipped', () {
      const text =
          'IT 104 Data Structures 3 10:00 AM - 09:00 AM / Mon Rm 301 Prof. Ana Reyes';
      expect(CorScheduleParser.parse(text), isEmpty);
    });

    test('looksLikeCor recognises the form title or the column headers', () {
      expect(
        CorScheduleParser.looksLikeCor('CERTIFICATE OF REGISTRATION'),
        isTrue,
      );
      expect(
        CorScheduleParser.looksLikeCor(
          'Units Faculty Room\nIT 104 Data 3 08:00 AM - 09:30 AM / Mon Rm 301',
        ),
        isTrue,
      );
      expect(
        CorScheduleParser.looksLikeCor(
          'Time / Day Room\n08:00 AM - 09:30 AM / Mon Rm 301',
        ),
        isFalse,
      );
    });

    test('ParseChain prefers COR rows for a COR and leaves other text alone', () {
      const cor =
          'IT 104 Data Structures and Algorithm 3 08:00 AM - 09:30 AM / Mon Rm 301 Prof. Ana Reyes';
      final chain = ParseChain.parse('Certificate of Registration\n$cor');
      expect(chain.used, 'sectioned');
      expect(chain.sectioned.single.subject, 'Data Structures and Algorithm');

      const plain = 'Mon 09:00 Art History Room 12';
      expect(ParseChain.sectionedRows(plain).length, lessThanOrEqualTo(1));
    });
  });
}
