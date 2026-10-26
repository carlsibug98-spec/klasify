import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/utils/next_class.dart';

// Reference dates (2026): Wed Oct 14, Thu Oct 15, Sun Oct 18.
ClassItem cls(String subject, int day, int startH, int endH) => ClassItem(
  id: 1,
  subject: subject,
  room: '101',
  professor: 'Prof. Cruz',
  day: day,
  startMinutes: startH * 60,
  endMinutes: endH * 60,
);

void main() {
  const wed = 3, thu = 4, fri = 5, mon = 1;

  group('findNextClass', () {
    test('returns null for an empty schedule', () {
      expect(findNextClass([], DateTime(2026, 10, 14, 9)), isNull);
    });

    test('detects a class in progress', () {
      final r = findNextClass([
        cls('Math', wed, 8, 10),
      ], DateTime(2026, 10, 14, 9));
      expect(r!.isNow, isTrue);
      expect(r.item.subject, 'Math');
      expect(r.whenText, 'Ends in 1h');
    });

    test('a class starting exactly now counts as in progress', () {
      final r = findNextClass([
        cls('Math', wed, 8, 10),
      ], DateTime(2026, 10, 14, 8));
      expect(r!.isNow, isTrue);
    });

    test('a class that just ended is not in progress; next is next week', () {
      final r = findNextClass([
        cls('Math', wed, 8, 10),
      ], DateTime(2026, 10, 14, 10));
      expect(r!.isNow, isFalse);
      expect(r.minutesUntil, 7 * 1440 - 120);
      expect(r.whenText, 'Starts in 6d 22h');
    });

    test('after today ends, picks the class tomorrow', () {
      final r = findNextClass([
        cls('Math', wed, 8, 10),
        cls('Science', thu, 8, 10),
      ], DateTime(2026, 10, 14, 11));
      expect(r!.item.subject, 'Science');
      expect(r.minutesUntil, 1260);
      expect(r.whenText, 'Starts in 21h');
    });

    test('Sunday night rolls over to Monday morning', () {
      final r = findNextClass([
        cls('English', mon, 8, 10),
      ], DateTime(2026, 10, 18, 22));
      expect(r!.item.subject, 'English');
      expect(r.minutesUntil, 600);
    });

    test('picks the soonest of several upcoming classes', () {
      final r = findNextClass([
        cls('Friday class', fri, 8, 10),
        cls('Thursday class', thu, 13, 15),
      ], DateTime(2026, 10, 14, 11));
      expect(r!.item.subject, 'Thursday class');
      expect(r.whenText, 'Starts in 1d 2h');
    });
  });

  group('NextClass.whenText', () {
    final item = cls('Math', wed, 8, 10);
    test(
      'minutes',
      () => expect(NextClass(item, false, 45).whenText, 'Starts in 45 min'),
    );
    test(
      'hours and minutes',
      () => expect(NextClass(item, false, 90).whenText, 'Starts in 1h 30m'),
    );
    test(
      'whole hours',
      () => expect(NextClass(item, false, 120).whenText, 'Starts in 2h'),
    );
  });

  group('formatMinutes', () {
    test('midnight', () => expect(formatMinutes(0), '12:00 AM'));
    test('noon', () => expect(formatMinutes(720), '12:00 PM'));
    test('afternoon', () => expect(formatMinutes(13 * 60 + 30), '1:30 PM'));
    test('pads minutes', () => expect(formatMinutes(8 * 60 + 5), '8:05 AM'));
  });

  group('ClassItem', () {
    test('toMap / fromMap round trip', () {
      final original = cls('Math', wed, 8, 10);
      final copy = ClassItem.fromMap(original.toMap());
      expect(copy.subject, original.subject);
      expect(copy.day, original.day);
      expect(copy.startMinutes, original.startMinutes);
      expect(copy.endMinutes, original.endMinutes);
      expect(copy.timeRange, '8:00 AM - 10:00 AM');
    });

    test('toMap leaves out id when null (so SQLite auto-assigns it)', () {
      const c = ClassItem(
        subject: 'X',
        room: '1',
        professor: 'Y',
        day: 1,
        startMinutes: 480,
        endMinutes: 540,
      );
      expect(c.toMap().containsKey('id'), isFalse);
    });
  });

  group('NextClass dayPillText', () {
    test('returns TOMORROW when next class is on the following day', () {
      final now = DateTime(2026, 10, 14, 18); // Wednesday
      final next = NextClass(
        cls('Science', 4, 8, 10),
        false,
        840,
      ); // Thursday (4)
      expect(next.dayPillText(now), 'TOMORROW');
    });

    test('returns TOMORROW when Sunday night rolls over to Monday', () {
      final now = DateTime(2026, 10, 18, 22); // Sunday (7)
      final next = NextClass(cls('Math', 1, 8, 10), false, 600); // Monday (1)
      expect(next.dayPillText(now), 'TOMORROW');
    });

    test('returns uppercase day name when next class is 2+ days away', () {
      final now = DateTime(2026, 10, 16, 18); // Friday (5)
      final next = NextClass(cls('Math', 1, 8, 10), false, 3720); // Monday (1)
      expect(next.dayPillText(now), 'MONDAY');
    });
  });
}
