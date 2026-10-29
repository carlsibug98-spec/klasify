/// Regression check: runs every expectation from
/// test/cor_schedule_parser_test.dart plus the neighbouring parser suites'
/// COR-relevant cases through the REAL parser, without Flutter.
///
/// The flutter test suite remains the source of truth on a machine with the
/// SDK; this harness catches COR-parser regressions inside the benchmark VM.
library;

import '../../../lib/features/schedule_import/utils/cor_schedule_parser.dart';
import '../../../lib/features/schedule_import/utils/parse_chain.dart';

var failures = 0;
var checks = 0;

void expectEq(Object? actual, Object? expected, String label) {
  checks++;
  if ('$actual' != '$expected') {
    failures++;
    print('FAIL $label\n  expected: $expected\n  actual:   $actual');
  }
}

void expectTrue(bool value, String label) {
  checks++;
  if (!value) {
    failures++;
    print('FAIL $label (expected true)');
  }
}

void main() {
  // 1. reads code, units, time/day, room and faculty on each row
  const text1 = '''
CERTIFICATE OF REGISTRATION
Code Subject Description Units Section Time / Day Room Faculty
IT 104 Data Structures and Algorithm 3 BSIT-2A 08:00 AM - 09:30 AM / Mon Rm 301 Prof. Ana Reyes
IT 202L Database Systems Laboratory 1 BSIT-2A 02:30 PM - 04:30 PM / Tue Lab 2 Prof. Ben Cole
TOTAL UNITS ENROLLED: 4
''';
  final rows1 = CorScheduleParser.parse(text1);
  expectEq(rows1.length, 2, 't1 row count');
  expectEq(rows1[0].subject, 'Data Structures and Algorithm', 't1 subject0');
  expectEq(rows1[0].day, 1, 't1 day0');
  expectEq(rows1[0].startMinutes, 8 * 60, 't1 start0');
  expectEq(rows1[0].endMinutes, 9 * 60 + 30, 't1 end0');
  expectEq(rows1[0].room, 'Rm 301', 't1 room0');
  expectEq(rows1[0].professor, 'Prof. Ana Reyes', 't1 prof0');
  expectEq(rows1[0].assumptions.isEmpty, true, 't1 assumptions0');
  expectEq(rows1[1].day, 2, 't1 day1');
  expectEq(rows1[1].startMinutes, 14 * 60 + 30, 't1 start1');
  expectEq(rows1[1].room, 'Lab 2', 't1 room1');

  // 2. ignores tba and online cells and keeps the room
  const text2 =
      'GE C03 Purposive Communication 3 07:00 AM - 08:30 AM / Mon tba Prof. Cara Lim Rm 105';
  final rows2 = CorScheduleParser.parse(text2);
  expectEq(rows2.single.room, 'Rm 105', 't2 room');
  expectEq(rows2.single.professor, 'Prof. Cara Lim', 't2 prof');

  // 3. a time row without a code continues the subject above it
  const text3 = '''
IT 201 Data Structures and Algorithms 3 BSIT-2A 08:00 AM - 09:30 AM / Mon Rm 301 Prof. Ana Reyes
10:00 AM - 11:30 AM / Wed Rm 301 Prof. Ana Reyes
''';
  final rows3 = CorScheduleParser.parse(text3);
  expectEq(rows3.length, 2, 't3 rows');
  expectEq(rows3[1].subject, 'Data Structures and Algorithms', 't3 carried');
  expectEq(rows3[1].day, 3, 't3 day');
  expectEq(rows3[1].ocrConfidence, 0.74, 't3 confidence');
  expectEq(rows3[1].assumptions.isNotEmpty, true, 't3 assumptions');

  // 4. a blank-schedule COR emits no classes
  const text4 = '''
CERTIFICATE OF REGISTRATION
GE C03 Purposive Communication 3
GE C04 Readings in Philippine History 3
IT 104 Data Structures and Algorithm 3
TOTAL NUMBER OF UNITS ENROLLED: 9
''';
  expectEq(CorScheduleParser.parse(text4).length, 0, 't4 blank schedule');

  // 5. zero-length or reversed time range is skipped
  const text5 =
      'IT 104 Data Structures 3 10:00 AM - 09:00 AM / Mon Rm 301 Prof. Ana Reyes';
  expectEq(CorScheduleParser.parse(text5).length, 0, 't5 reversed range');

  // 6. looksLikeCor: form title or column headers, but not a plain timetable
  expectTrue(
    CorScheduleParser.looksLikeCor('CERTIFICATE OF REGISTRATION'),
    't6 title',
  );
  expectTrue(
    CorScheduleParser.looksLikeCor(
      'Units Faculty Room\nIT 104 Data 3 08:00 AM - 09:30 AM / Mon Rm 301',
    ),
    't6 headers',
  );
  expectTrue(
    !CorScheduleParser.looksLikeCor(
      'Time / Day Room\n08:00 AM - 09:30 AM / Mon Rm 301',
    ),
    't6 plain timetable rejected',
  );

  // 7. ParseChain routes a COR through the COR parser
  const cor7 =
      'IT 104 Data Structures and Algorithm 3 08:00 AM - 09:30 AM / Mon Rm 301 Prof. Ana Reyes';
  final chain7 = ParseChain.parse('Certificate of Registration\n$cor7');
  expectEq(chain7.used, 'sectioned', 't7 chain used');
  expectEq(chain7.sectioned.single.subject, 'Data Structures and Algorithm',
      't7 chain subject');

  // --- New behaviours added with the bench7 COR fixture set ----------------

  // 8. tolerant schedule cell: space after colon, dropped colon, tight slash
  const text8 =
      'IT 104 Data Structures 3 08:00 AM - 09: 30 AM / Mon Rm 301 Prof. Ana Reyes';
  final rows8 = CorScheduleParser.parse(text8);
  expectEq(rows8.single.startMinutes, 480, 't8 space in time start');
  expectEq(rows8.single.endMinutes, 9 * 60 + 30, 't8 space in time end');

  const text8b =
      'IT 104 Data Structures 3 04:00 PM - 05 00 PM / Thu Gym Coach E. Park';
  final rows8b = CorScheduleParser.parse(text8b);
  expectEq(rows8b.single.startMinutes, 16 * 60, 't8b dropped colon start');
  expectEq(rows8b.single.endMinutes, 17 * 60, 't8b dropped colon end');

  // 9. fuzzy day: one-character OCR slip still resolves, ambiguous stays out
  const text9 =
      'IT 104 Data Structures 3 08:00 AM - 09:30 AM / Tuo Rm 301 Prof. A';
  expectEq(CorScheduleParser.parse(text9).single.day, 2, 't9 Tuo -> Tue');

  // 10. code letter/digit slips: trailing O for 0, trailing L for 1
  const text10 =
      'PEO? PATHFit 3 - Dance and Sports 2 04:00 PM - 05:00 PM / Thu Gym Coach E. Park';
  final rows10 = CorScheduleParser.parse(text10);
  expectEq(rows10.single.subject, 'PATHFit 3 - Dance and Sports',
      't10 O-for-0 subject');

  const text10b =
      'IT FEL Free Elective 1 (Internet of Things) 3 02:30 PM - 04:00 PM / Fri Rm 204 Prof. Ben Cole';
  final rows10b = CorScheduleParser.parse(text10b);
  expectEq(rows10b.single.subject, 'Free Elective 1 (Internet of Things)',
      't10b L-for-1 subject');

  // 11. cell separators and underline filler are stripped from subjects
  const text11 =
      'IT 201 | Data Structures and Algorithms | 3 | BSIT-2A _ 08:00 AM - 09:30 AM / Mon | Rm 301 __ | Prof. Ana Reyes';
  final rows11 = CorScheduleParser.parse(text11);
  expectEq(rows11.single.subject, 'Data Structures and Algorithms',
      't11 pipe cleanup');

  // 12. a subject line inside the table attaches to the next time cell
  const text12 = '''
08:00 AM - 09:30 AM / Mon
PATHAit 3 - Dance, Sports, and Adventure Prof. Ana Reyes Rm 301
04:00 PM - 05:00 PM / Thu
''';
  final rows12 = CorScheduleParser.parse(text12);
  expectEq(rows12.length, 1, 't12 stash rows');
  expectEq(rows12.single.subject,
      'PATHAit 3 - Dance, Sports, and Adventure', 't12 stash subject');
  expectEq(rows12.single.day, 4, 't12 stash day');

  // 13. merged lab rooms are normalized (lab2 -> Lab 2, maclab -> MacLab)
  const text13 =
      'IT 202L Database Systems Laboratory 1 02:30 PM - 04:30 PM / Tue lab2 Prof. Ben Cole';
  expectEq(CorScheduleParser.parse(text13).single.room, 'Lab 2', 't13 lab2');
  const text13b =
      'IT 104L Data Structures Laboratory 1 10:00 AM - 11:30 AM / Wed maclab Prof. A';
  expectEq(
      CorScheduleParser.parse(text13b).single.room, 'MacLab', 't13 maclab');

  // 14. fallback COR detection without title or headers
  expectTrue(
    CorScheduleParser.looksLikeCor(
      'Purposive Communication 07:00 AM - 08:30 AM / Mon\n'
      'Readings in Philippine History 09:00 AM - 10:30 AM / Tue\n'
      'Prof. Cara Lim Rm 105',
    ),
    't14 vocabulary fallback',
  );

  print('checks=$checks failures=$failures');
}
