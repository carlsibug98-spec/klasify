import 'package:klasify/models/class_item.dart';
import 'package:klasify/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'persists the reminder lead time and falls back to 10 minutes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = ReminderService.instance;

      expect(await service.leadMinutes, ReminderService.defaultLeadMinutes);

      await service.setLeadMinutes(15);
      expect(await service.leadMinutes, 15);

      await service.setLeadMinutes(30);
      expect(await service.leadMinutes, 30);

      await service.setLeadMinutes(99);
      expect(await service.leadMinutes, ReminderService.defaultLeadMinutes);
    },
  );

  test(
    'does not clear reminders when reading the saved schedule fails',
    () async {
      var cancelled = false;

      await expectLater(
        readClassesBeforeClearingReminders(
          readClasses: () async => throw StateError('database unavailable'),
          cancelAll: () async {
            cancelled = true;
          },
        ),
        throwsStateError,
      );

      expect(cancelled, isFalse);
    },
  );

  test('reads the schedule before clearing current reminders', () async {
    final events = <String>[];
    const item = ClassItem(
      subject: 'Mathematics',
      room: '101',
      professor: 'Prof. Cruz',
      day: 1,
      startMinutes: 480,
      endMinutes: 540,
    );

    final result = await readClassesBeforeClearingReminders(
      readClasses: () async {
        events.add('read');
        return [item];
      },
      cancelAll: () async => events.add('cancel'),
    );

    expect(result, [item]);
    expect(events, ['read', 'cancel']);
  });
}
