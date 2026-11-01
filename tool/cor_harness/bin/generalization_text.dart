// ignore_for_file: avoid_relative_lib_imports
// Round-11 generalization audit, Track C: never-seen TEXT through the pure
// parse surfaces (no OCR involved).
//
// Suite 1 - PdfTimetableText rail parsing: every rail shape the class
//           documents (24h, military, dotted, am/pm, ranges, noon wrap,
//           PM-only pull-in, period rails) with NEW values.
// Suite 2 - PdfTimetableText weekday header cells: full names, prefixes,
//           two-letter, MTWRF single letters, negatives.
// Suite 3 - Schedule text generalization: new-content list schedules fed
//           through the production chain (sectioned parser first, then the
//           free-text parser), matched against expected rows with the bench6
//           matcher semantics (day equal, interval overlap, subject sim).
// Suite 4 - stretch probes: formats the parsers may not support yet
//           (compound day tokens, day ranges, slash day pairs). Reported
//           separately as gaps, never counted as failures.
//
// Usage (from klasify-cor-extracted/):
//   dart run tool/cor_harness/bin/generalization_text.dart
// Prints one JSON object.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';
import '../../../lib/features/schedule_import/utils/parse_chain.dart';
import '../../../lib/features/schedule_import/utils/pdf_timetable_text.dart';
import '../../../lib/features/schedule_import/utils/timetable_parser.dart';

int dayIndex(String name) {
  final key = name.toLowerCase().trim();
  const days = {
    'mon': 1, 'monday': 1, 'tue': 2, 'tues': 2, 'tuesday': 2,
    'wed': 3, 'weds': 3, 'wednesday': 3, 'thu': 4, 'thur': 4, 'thurs': 4,
    'thursday': 4, 'fri': 5, 'friday': 5, 'sat': 6, 'saturday': 6,
    'sun': 7, 'sunday': 7,
  };
  return days[key] ?? 0;
}

int minutes(String hhmm) {
  final parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double similarity(String a, String b) {
  final x = norm(a);
  final y = norm(b);
  if (x.isEmpty && y.isEmpty) return 1.0;
  final longest = math.max(x.length, y.length);
  if (longest == 0) return 1.0;
  return 1.0 - _levenshtein(x, y) / longest;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = math.min(math.min(curr[j] + 1, prev[j + 1] + 1),
          prev[j] + cost);
    }
    final swap = prev;
    prev = curr;
    curr = swap;
  }
  return prev[b.length];
}

class _Row {
  const _Row(this.subject, this.day, this.start, this.end);

  final String subject;
  final int day;
  final int start;
  final int end;
}

List<_Row> _chainRows(String text) {
  final normalized = normalizeOcrTokens(text);
  final sectioned = ParseChain.sectionedRows(normalized);
  if (sectioned.isNotEmpty) {
    return [
      for (final r in sectioned)
        _Row(r.subject, r.day, r.startMinutes, r.endMinutes),
    ];
  }
  return [
    for (final r in TimetableParser.parse(normalized))
      _Row(r.subject, r.day, r.startMinutes, r.endMinutes),
  ];
}

void main() {
  final failures = <Map<String, dynamic>>[];
  final stretch = <Map<String, dynamic>>[];
  var passed = 0;

  void check(String suite, String caseName, bool ok, dynamic expected,
      dynamic got) {
    if (ok) {
      passed++;
    } else {
      failures.add({
        'suite': suite,
        'case': caseName,
        'expected': expected,
        'got': got,
      });
    }
  }

  // ------------------------------------------------ Suite 1: rail parsing
  const rails = <String, (int, bool)>{
    '08:00': (480, false),
    '0800': (480, false),
    '8:30 AM': (510, true),
    '9:15 pm': (1275, true),
    '12:00': (720, false),
    '8 - 9 PM': (1230, true),
    '1:30 - 3 PM': (855, true),
    '7:30 - 8:30': (480, false),
    '11:00 - 1:00': (720, false),
    'P1': (510, true),
    'P3-P4': (660, true),
    'Period 3': (630, true),
    '9': (540, false),
    '10:15.': (615, false),
  };
  for (final entry in rails.entries) {
    final parsed = PdfTimetableText.parseRailLine(entry.key);
    final ok = parsed != null &&
        parsed.minute == entry.value.$1 &&
        parsed.meridiemExplicit == entry.value.$2;
    check('rail', entry.key, ok, entry.value,
        parsed == null ? null : (parsed.minute, parsed.meridiemExplicit));
  }
  for (final negative in ['2025 - 2026', 'Room 8', 'not a time']) {
    final parsed = PdfTimetableText.parseRailLine(negative);
    check('rail-negative', negative, parsed == null, null,
        parsed?.minute);
  }

  // Noon-crossing rail sequence carried by the resolver:
  // 8:00 9:00 10:00 11:00 12:00 1:00 2:00 -> 480..840
  final noonLines = <PdfTextLineGeometry>[
    for (final e in [
      ('8:00', 40.0), ('9:00', 100.0), ('10:00', 160.0),
      ('11:00', 220.0), ('12:00', 280.0), ('1:00', 340.0), ('2:00', 400.0),
    ])
      (text: e.$1, left: 0, right: 40, centerY: e.$2),
  ];
  final ticks = PdfTimetableText.resolveRailTicks(
    noonLines,
    inMargin: (_) => true,
  );
  final tickMinutes = ticks.map((t) => t.minute).toList();
  check('rail-sequence', 'noon carry',
      const [480, 540, 600, 660, 720, 780, 840].join() == tickMinutes.join(),
      [480, 540, 600, 660, 720, 780, 840], tickMinutes);

  // ------------------------------------------- Suite 2: weekday headers
  const headers = <String, int>{
    'MONDAY': 1, 'Thursday': 4, 'SAT': 6, 'SUN': 7, 'Sun.': 7,
    'M': 1, 'T': 2, 'W': 3, 'R': 4, 'F': 5, 'S': 6, 'U': 7,
    'TH': 4, 'SA': 6, 'SU': 7,
  };
  for (final entry in headers.entries) {
    final day = PdfTimetableText.dayOfHeaderCell(entry.key);
    check('header', entry.key, day == entry.value, entry.value, day);
  }
  for (final negative in ['TTH', 'ROOM', '']) {
    final day = PdfTimetableText.dayOfHeaderCell(negative);
    check('header-negative', negative, day == null, null, day);
  }

  // ------------------------------------------ Suite 3: schedule text
  // Each case: text + expected rows (subject, day, start, end).
  final textCases = <(String, List<(String, String, String, String)>)>[
    // full day names, 24h times
    (
      'Algebra II\nMonday 8:00-9:30\nRm 204\n'
      'World History\nWednesday 14:00-15:30\nRm 210',
      [('Algebra II', 'Mon', '08:00', '09:30'),
       ('World History', 'Wed', '14:00', '15:30')],
    ),
    // am/pm with minutes
    (
      'Biology 1 Tue 9:00 AM - 10:30 AM Lab 2',
      [('Biology 1', 'Tue', '09:00', '10:30')],
    ),
    // noon boundary: class ending at 12 NN
    (
      'Statistics Thursday 10:30 AM - 12:00 PM Rm 7',
      [('Statistics', 'Thu', '10:30', '12:00')],
    ),
    // afternoon start past noon
    (
      'Public Speaking Fri 1:00 PM - 2:30 PM Room 15',
      [('Public Speaking', 'Fri', '13:00', '14:30')],
    ),
    // military times
    (
      'Marketing 0900-1030 Mon\nFinance 1300-1430 Tue',
      [('Marketing', 'Mon', '09:00', '10:30'),
       ('Finance', 'Tue', '13:00', '14:30')],
    ),
    // dotted minutes
    (
      'Ethics Wed 2.00-3.30 PM Rm 9',
      [('Ethics', 'Wed', '14:00', '15:30')],
    ),
    // no leading zero
    (
      'Botany 9:30-11:00 sat Lab 4',
      [('Botany', 'Sat', '09:30', '11:00')],
    ),
  ];
  for (final case_ in textCases) {
    final rows = _chainRows(case_.$1);
    final expected = [
      for (final e in case_.$2)
        (e.$1, dayIndex(e.$2), minutes(e.$3), minutes(e.$4)),
    ];
    // every expected row must be matched 1-to-1
    final used = <int>{};
    var allOk = rows.length >= expected.length;
    final detail = <String>[];
    for (final exp in expected) {
      var found = -1;
      for (var i = 0; i < rows.length; i++) {
        if (used.contains(i)) continue;
        final r = rows[i];
        final okDay = r.day == exp.$2;
        final okTime = r.start < exp.$4 && exp.$3 < r.end;
        final okSubj = similarity(exp.$1, r.subject) >= 0.34;
        if (okDay && okTime && okSubj) {
          found = i;
          break;
        }
      }
      if (found >= 0) {
        used.add(found);
      } else {
        allOk = false;
        detail.add('missing ${exp.$1} d${exp.$2} '
            '${exp.$3}-${exp.$4}');
      }
    }
    check('text', case_.$1.split('\n').first, allOk, 'all expected rows',
        rows.isEmpty ? 'no rows' : detail.join('; '));
  }

  // ------------------------------------------ Suite 4: stretch probes
  const stretchCases = <(String, List<(String, String, String, String)>)>[
    // compound day token
    (
      'Cost Accounting TTh 9:00-10:30 Rm 402',
      [('Cost Accounting', 'Tue', '09:00', '10:30'),
       ('Cost Accounting', 'Thu', '09:00', '10:30')],
    ),
    // day range
    (
      'Choir MWF 11:00-12:00 Music Hall',
      [('Choir', 'Mon', '11:00', '12:00'),
       ('Choir', 'Wed', '11:00', '12:00'),
       ('Choir', 'Fri', '11:00', '12:00')],
    ),
    // slash day pair
    (
      'Robotics Mon/Wed 13:00-14:30 ComLab 2',
      [('Robotics', 'Mon', '13:00', '14:30'),
       ('Robotics', 'Wed', '13:00', '14:30')],
    ),
  ];
  for (final case_ in stretchCases) {
    final rows = _chainRows(case_.$1);
    final expectedDays = case_.$2.map((e) => dayIndex(e.$2)).toSet();
    final gotDays = rows.map((r) => r.day).toSet();
    final ok = expectedDays.difference(gotDays).isEmpty &&
        rows.length >= case_.$2.length;
    stretch.add({
      'case': case_.$1.split('\n').first,
      'expected_days': expectedDays.toList(),
      'got_rows': [
        for (final r in rows)
          {'day': r.day, 'start': r.start, 'end': r.end}
      ],
      'supported': ok,
    });
  }

  stdout.writeln(jsonEncode({
    'passed': passed,
    'failed': failures.length,
    'failures': failures,
    'stretch': stretch,
  }));
}
