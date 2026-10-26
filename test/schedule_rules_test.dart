import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/utils/schedule_rules.dart';

ClassItem item(int id, int day, int start, int end) => ClassItem(
  id: id,
  subject: 'Class $id',
  room: '101',
  professor: 'Professor',
  day: day,
  startMinutes: start,
  endMinutes: end,
);

void main() {
  group('findOverlappingClass', () {
    final existing = [
      item(1, 1, 480, 540),
      item(2, 1, 600, 660),
      item(3, 2, 480, 540),
    ];

    test('detects a class starting inside an existing class', () {
      expect(
        findOverlappingClass(
          existing,
          day: 1,
          startMinutes: 500,
          endMinutes: 560,
        )?.id,
        1,
      );
    });

    test('allows adjacent classes with no shared minutes', () {
      expect(
        findOverlappingClass(
          existing,
          day: 1,
          startMinutes: 540,
          endMinutes: 600,
        ),
        isNull,
      );
    });

    test('ignores classes on other days', () {
      expect(
        findOverlappingClass(
          existing,
          day: 3,
          startMinutes: 480,
          endMinutes: 500,
        ),
        isNull,
      );
    });

    test('ignores the class being edited', () {
      expect(
        findOverlappingClass(
          existing,
          day: 1,
          startMinutes: 490,
          endMinutes: 530,
          excludeId: 1,
        ),
        isNull,
      );
    });

    test('detects an overlap that fully contains an existing class', () {
      expect(
        findOverlappingClass(
          existing,
          day: 1,
          startMinutes: 470,
          endMinutes: 550,
        )?.id,
        1,
      );
    });
  });
}
