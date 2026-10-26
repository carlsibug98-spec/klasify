import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/timetable_grid_geometry.dart';

void main() {
  test(
    'uses physical grid spacing when OCR skips alternating clock labels',
    () {
      final spacing = inferTimetableRowSpacing(
        gridRulePositions: [36.5, 73.5, 91.9, 110.3, 128.7],
        ocrTickPositions: [82.7, 119.5, 156.3],
        maxGap: 77,
      );

      expect(spacing, closeTo(18.4, 0.1));
    },
  );

  test('falls back to OCR tick spacing when grid lines are unavailable', () {
    final spacing = inferTimetableRowSpacing(
      gridRulePositions: const [],
      ocrTickPositions: [80, 98, 116, 134],
      maxGap: 50,
    );

    expect(spacing, 18);
  });
}
