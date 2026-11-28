import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/utils/next_class.dart';

// Reference: Friday 23 Oct 2026. Sunday of that week is 25 Oct.
ClassStatusEntry entry(DayStatus status, String start, [String? end]) =>
    ClassStatusEntry(
      classId: 1,
      status: status,
      startDate: start,
      endDate: end,
    );

/// (start, end, status) for each entry, sorted by start, for readable asserts.
List<(String, String?, DayStatus)> summary(List<ClassStatusEntry> entries) {
  final sorted = [...entries]
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  return [for (final e in sorted) (e.startDate, e.endDate, e.status)];
}

void main() {
  group('replaceStatusRange', () {
    test('adds a range when nothing overlaps', () {
      final result = replaceStatusRange(
        [],
        entry(DayStatus.cancelled, '2026-10-23', '2026-10-23'),
      );
      expect(summary(result), [
        ('2026-10-23', '2026-10-23', DayStatus.cancelled),
      ]);
    });

    test('a one-day change inside an until-cleared mark keeps both sides', () {
      final result = replaceStatusRange([
        entry(DayStatus.notAttending, '2026-10-19'),
      ], entry(DayStatus.cancelled, '2026-10-23', '2026-10-23'));
      expect(summary(result), [
        ('2026-10-19', '2026-10-22', DayStatus.notAttending),
        ('2026-10-23', '2026-10-23', DayStatus.cancelled),
        ('2026-10-24', null, DayStatus.notAttending),
      ]);
    });

    test('a new mark over the same day replaces it', () {
      final result = replaceStatusRange([
        entry(DayStatus.cancelled, '2026-10-23', '2026-10-23'),
      ], entry(DayStatus.finished, '2026-10-23', '2026-10-23'));
      expect(summary(result), [
        ('2026-10-23', '2026-10-23', DayStatus.finished),
      ]);
    });

    test('an until-cleared mark covers a longer existing mark', () {
      final result = replaceStatusRange([
        entry(DayStatus.notAttending, '2026-10-23', '2026-10-25'),
      ], entry(DayStatus.cancelled, '2026-10-20'));
      expect(summary(result), [('2026-10-20', null, DayStatus.cancelled)]);
    });

    test('a this-week mark does not touch next week', () {
      final result = replaceStatusRange([
        entry(DayStatus.notAttending, '2026-10-26'),
      ], entry(DayStatus.cancelled, '2026-10-23', '2026-10-25'));
      expect(summary(result), [
        ('2026-10-23', '2026-10-25', DayStatus.cancelled),
        ('2026-10-26', null, DayStatus.notAttending),
      ]);
    });
  });

  group('statusDurationLabel', () {
    final today = DateTime(2026, 10, 23);

    test('single day today reads "today"', () {
      expect(
        statusDurationLabel(
          entry(DayStatus.cancelled, '2026-10-23', '2026-10-23'),
          today,
        ),
        'today',
      );
    });

    test('single day on another date reads "this day"', () {
      expect(
        statusDurationLabel(
          entry(DayStatus.cancelled, '2026-10-22', '2026-10-22'),
          today,
        ),
        'this day',
      );
    });

    test('a range ending on a custom date reads "until <date>"', () {
      expect(
        statusDurationLabel(
          entry(DayStatus.notAttending, '2026-10-23', '2026-10-25'),
          today,
        ),
        'until 25 Oct',
      );
    });

    test('an open-ended mark reads "until cleared"', () {
      expect(
        statusDurationLabel(entry(DayStatus.notAttending, '2026-10-23'), today),
        'until cleared',
      );
    });

    test('a custom range shows its end date', () {
      expect(
        statusDurationLabel(
          entry(DayStatus.cancelled, '2026-10-23', '2026-10-24'),
          today,
        ),
        'until 24 Oct',
      );
    });
  });

  group('activeStatusEntry', () {
    test('returns the entry that covers the date, and none outside it', () {
      final statuses = <int, List<ClassStatusEntry>>{
        1: [
          entry(DayStatus.notAttending, '2026-10-19', '2026-10-22'),
          entry(DayStatus.cancelled, '2026-10-23', '2026-10-23'),
        ],
      };
      expect(
        activeStatusEntry(statuses, 1, DateTime(2026, 10, 23))?.status,
        DayStatus.cancelled,
      );
      expect(activeStatusEntry(statuses, 1, DateTime(2026, 10, 24)), isNull);
      expect(activeStatusEntry(statuses, 2, DateTime(2026, 10, 23)), isNull);
    });
  });

  group('findNextClass with finished marks', () {
    test(
      'a class marked finished early is not live, and the next class takes over',
      () {
        final classes = [
          const ClassItem(
            id: 1,
            subject: 'Web Development',
            room: 'Lab 2',
            professor: 'Prof. Santos',
            day: 5, // Friday
            startMinutes: 9 * 60,
            endMinutes: 10 * 60 + 30,
          ),
          const ClassItem(
            id: 2,
            subject: 'Database Systems',
            room: 'Room 210',
            professor: 'Ms. Cruz',
            day: 5,
            startMinutes: 11 * 60,
            endMinutes: 12 * 60,
          ),
        ];
        final statuses = <int, List<ClassStatusEntry>>{
          1: [entry(DayStatus.finished, '2026-10-23', '2026-10-23')],
        };

        final next = findNextClass(
          classes,
          DateTime(2026, 10, 23, 9, 45),
          statuses: statuses,
        );

        expect(next, isNotNull);
        expect(next!.isNow, isFalse);
        expect(next.item.id, 2);
        expect(next.minutesUntil, 75);
      },
    );
  });

  group('dateForWeekday', () {
    test('maps every weekday into the same Monday-to-Sunday week', () {
      // Wednesday 25 Nov 2026.
      final now = DateTime(2026, 11, 25, 14, 30);
      final dates = [
        for (var day = 1; day <= 7; day++) dateForWeekday(now, day),
      ];

      expect(dates.first, DateTime(2026, 11, 23));
      expect(dates.last, DateTime(2026, 11, 29));
      for (var day = 1; day <= 7; day++) {
        expect(dates[day - 1].weekday, day);
        expect(dates[day - 1].hour, 0);
      }
    });

    test('crosses month and year boundaries without drifting', () {
      // Wednesday 30 Dec 2026: the week ends in January.
      final now = DateTime(2026, 12, 30, 8);
      expect(dateForWeekday(now, DateTime.monday), DateTime(2026, 12, 28));
      expect(dateForWeekday(now, DateTime.sunday), DateTime(2027, 1, 3));
    });

    test('a Sunday still belongs to the week that started six days earlier', () {
      final now = DateTime(2027, 1, 3, 23, 59);
      expect(dateForWeekday(now, DateTime.monday), DateTime(2026, 12, 28));
    });
  });
}
