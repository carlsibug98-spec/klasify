import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/adaptive_grid_rules.dart';
import 'package:klasify/features/schedule_import/utils/cell_assignment.dart';
import 'package:klasify/features/schedule_import/utils/domain_rescoring.dart';
import 'package:klasify/features/schedule_import/utils/skew_correction.dart';
import 'package:klasify/features/schedule_import/utils/timetable_format.dart';

SpatialTextBlock _block(
  String text,
  double left,
  double top,
  double right,
  double bottom,
) => SpatialTextBlock(
  text: text,
  left: left,
  top: top,
  right: right,
  bottom: bottom,
);

void main() {
  group('timetable format classifier', () {
    test('detects list schedules from day+time lines', () {
      final estimate = TimetableFormatClassifier.classify('''
CS201 Mon 9:30-11:00 Room B12
MATH150 Tue 10:00-12:00 Hall A
PHYS210 Wed 14:00-15:30 Lab 3
CHEM101 Thu 9:00-10:30 Room C2
''');
      expect(estimate.format, TimetableFormat.list);
      expect(estimate.confidence, greaterThan(.4));
    });

    test('detects weekly grids via fragmented weekday words', () {
      final estimate = TimetableFormatClassifier.classify('''
Monday
Tuesday
Wednesday
Thursday
Friday
Saturday
CS201
B12
9.30
''');
      expect(estimate.format, TimetableFormat.weeklyGrid);
    });

    test('honors pixel grid evidence even with few text signals', () {
      final estimate = TimetableFormatClassifier.classify(
        'Mon\nTue\nWed\nThu\nFri\nSat\n09.00\n10.00\n11.00\n12.00\n13.00',
        hasPixelGridEvidence: true,
      );
      expect(estimate.format, TimetableFormat.weeklyGrid);
    });

    test('detects exam calendars from dates and header words', () {
      final estimate = TimetableFormatClassifier.classify('''
EXAM TIMETABLE - SECOND SEMESTER
Subject            Date        Time         Room
Data Structures    12/05/2026  09:00-12:00  Hall A
Operating Systems  14/05/2026  14:00-17:00  Hall B
Databases          18/05/2026  09:00-12:00  Lab 3
Networks           20/05/2026  14:00-17:00  Hall A
Calculus II        22/05/2026  09:00-11:30  Main Hall
Physics Lab        26/05/2026  10:00-13:00  Lab 1
Chemistry          28/05/2026  09:00-12:00  Hall C
''');
      expect(estimate.format, TimetableFormat.examCalendar);
    });

    test('returns unknown for empty input', () {
      final estimate = TimetableFormatClassifier.classify('   ');
      expect(estimate.format, TimetableFormat.unknown);
      expect(estimate.evidence, 'no text');
    });
  });

  group('list parser', () {
    test('parses one class per line and skips junk lines', () {
      final rows = TimetableListParser.parse('''
Page 1 of 2
CS201 - Data Structures, Mon 9:30-11:00, Room B12
Lunch break
MATH150 Tue 10:00-12:00 Hall A
''');
      expect(rows.length, greaterThanOrEqualTo(2));
      expect(rows.any((r) => r.subject.contains('CS201')), isTrue);
      expect(rows.map((r) => r.day).toSet().length, greaterThanOrEqualTo(2));
    });

    test('expands compact day groups like MWF into separate rows', () {
      final rows = TimetableListParser.parse('CS201 MWF 9:30-11:00 Room B12');
      expect(rows.length, 3);
      expect(rows.map((r) => r.day).toSet().length, 3);
    });
  });

  group('domain rescoring', () {
    test('normalizes confusable time characters', () {
      expect(normalizeOcrTokens('9:3O'), contains('9:30'));
      expect(normalizeOcrTokens('l2:00'), contains('12:00'));
      expect(normalizeOcrTokens('8；OO AM'), contains('8:00'));
    });

    test('collapses doubled dots in codes', () {
      expect(normalizeOcrTokens('CS..201'), 'CS.201');
    });

    test('fuzzy-corrects course codes against vocabulary', () {
      final rescorer = CourseCodeRescorer(['CS201', 'MATH150']);
      expect(rescorer.correct('as20i'), 'CS201');
      expect(rescorer.correct('CS201'), 'CS201');
      // Unknown tokens outside the edit budget stay unchanged.
      expect(rescorer.correct('XY999'), 'XY999');
      // Short tokens are never rewritten.
      expect(rescorer.correct('A1'), 'A1');
    });
  });

  group('skew estimation', () {
    test('reports no skew for tiny images', () {
      final estimate = estimateGridSkew(
        rowDarkCounts: List.filled(16, 16),
        rowDarkCenters: List.generate(16, (i) => 8.0),
        width: 16,
        height: 16,
      );
      expect(estimate, same(SkewEstimate.none));
    });

    test('estimates tilt from drifting rule centroids', () {
      const width = 200;
      const height = 100;
      final counts = List<int>.filled(height, 0);
      final centers = List<double>.filled(height, 0);
      // Horizontal rules every 10 rows whose center drifts 1 px per row:
      // slope dx/dy = 1 -> ~45 deg guard would reject .5+, so use .2.
      for (var y = 0; y < height; y++) {
        if (y % 10 == 0) {
          counts[y] = width; // fully dark rule row
          centers[y] = 100 + y * 0.2;
        }
      }
      final estimate = estimateGridSkew(
        rowDarkCounts: counts,
        rowDarkCenters: centers,
        width: width,
        height: height,
      );
      expect(estimate.radians, greaterThan(0));
      expect(estimate.confidence, greaterThanOrEqualTo(.4));
      expect(estimate.shouldCorrect, isTrue);
    });

    test('none when too few rule rows', () {
      final estimate = estimateGridSkew(
        rowDarkCounts: List<int>.filled(100, 0)..[3] = 200,
        rowDarkCenters: List<double>.filled(100, 100)..[3] = 100,
        width: 200,
        height: 100,
      );
      expect(estimate.radians, 0);
    });
  });

  group('adaptive grid rules', () {
    test('finds faint long runs above the noise floor', () {
      // 100-row page; text rows have ~10 dark px, rule rows ~60 (faint gray).
      final profiles = <int, ({int ink, int runStart, int runEnd})>{};
      for (var y = 0; y < 100; y++) {
        profiles[y] = (ink: 10, runStart: 5, runEnd: 40);
      }
      profiles[10] = (ink: 60, runStart: 0, runEnd: 99);
      profiles[50] = (ink: 70, runStart: 0, runEnd: 99);
      // Adjacent duplicate of a thick rule at 50/51 — should merge.
      profiles[51] = (ink: 65, runStart: 0, runEnd: 99);

      final rules = detectAdaptiveRules(
        profiles: profiles,
        axisLength: 100,
        isHorizontal: true,
      );
      expect(rules.map((r) => r.position), containsAll(<int>[10]));
      expect(
        rules.where((r) => r.position == 50 || r.position == 51).length,
        1,
      );
      expect(rules.every((r) => r.isHorizontal), isTrue);
    });

    test('rejects short dense runs that are not table lines', () {
      final profiles = <int, ({int ink, int runStart, int runEnd})>{
        for (var y = 0; y < 50; y++)
          y: (ink: 40, runStart: 0, runEnd: 10), // dense but short (20% span)
      };
      final rules = detectAdaptiveRules(
        profiles: profiles,
        axisLength: 50,
        isHorizontal: false,
      );
      expect(rules, isEmpty);
    });

    test('empty input yields no rules', () {
      expect(
        detectAdaptiveRules(profiles: {}, axisLength: 100, isHorizontal: true),
        isEmpty,
      );
    });
  });

  group('centroid cell assignment', () {
    final assigner = CentroidCellAssigner(
      columnBounds: const [0, 100, 200],
      rowRules: const [0, 50, 100],
    );

    test('assigns blocks by centroid, robust to reading order', () {
      final secondColumn = _block('CS201', 110, 10, 190, 30);
      final assignment = assigner.assign(secondColumn)!;
      expect(assignment.columnIndex, 1);
      expect(assignment.band, 0);
    });

    test('clamps slightly-outside blocks to nearest band', () {
      final straddling = _block('Lab', 10, 95, 90, 115);
      final assignment = assigner.assign(straddling)!;
      expect(assignment.band, 1);
    });

    test('rejects blocks far outside the grid', () {
      expect(assigner.assign(_block('x', 300, 10, 350, 30)), isNull);
      expect(assigner.assign(_block('y', 10, 500, 90, 520)), isNull);
    });

    test('groupCells buckets by d{col}r{band} key', () {
      final cells = assigner.groupCells([
        _block('CS201', 10, 10, 90, 30),
        _block('B12', 10, 15, 90, 35),
        _block('MATH', 110, 60, 190, 80),
      ]);
      expect(cells['d0r0']!.length, 2);
      expect(cells['d1r1']!.length, 1);
    });
  });

  group('merged cell spans', () {
    test('merges an empty continuation band below tall text', () {
      final cells = <String, List<SpatialTextBlock>>{
        'd0r0': [_block('CHEM LAB', 10, 5, 90, 55)], // reaches into band 1
      };
      final spans = mergeCellSpans(cells: cells, columnCount: 1, bandCount: 2);
      expect(spans.length, 1);
      expect(spans.first.startBand, 0);
      expect(spans.first.endBand, 1);
    });

    test('keeps separate bands when text does not continue', () {
      final cells = <String, List<SpatialTextBlock>>{
        'd0r0': [_block('CS201', 10, 5, 90, 40)],
        'd0r1': [_block('B12', 10, 60, 90, 90)],
      };
      final spans = mergeCellSpans(cells: cells, columnCount: 1, bandCount: 2);
      expect(spans.length, 2);
      expect(spans.every((s) => s.startBand == s.endBand), isTrue);
    });

    test('merges across a missing internal rule seam', () {
      final cells = <String, List<SpatialTextBlock>>{
        'd0r0': [_block('LAB', 10, 5, 90, 40)],
        'd0r1': [_block('PART2', 10, 60, 90, 90)],
      };
      // Rule row 1 exists globally but is absent in column 0 → seam merged.
      final spans = mergeCellSpans(
        cells: cells,
        columnCount: 1,
        bandCount: 2,
        strongRuleRowsByColumn: {0: <int>{}},
        allRuleRows: const [0, 1, 2],
      );
      expect(spans.length, 1);
      expect(spans.first.endBand, 1);
    });
  });
}
