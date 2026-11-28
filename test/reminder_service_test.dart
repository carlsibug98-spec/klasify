import 'package:klasify/screens/reminders_screen.dart';
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

      await service.setLeadMinutes(60);
      expect(await service.leadMinutes, 60);

      await service.setLeadMinutes(30);
      expect(await service.leadMinutes, 30);

      await service.setLeadMinutes(99);
      expect(await service.leadMinutes, ReminderService.defaultLeadMinutes);
    },
  );

  test('only reminders missing from the new schedule are stale', () {
    expect(staleReminderIds([1, 2, 3, 4], {2, 4, 5}), [1, 3]);
  });

  test('nothing is stale when every pending reminder is rescheduled', () {
    expect(staleReminderIds([7, 8], {7, 8, 9}), isEmpty);
  });

  test('an empty schedule makes every pending reminder stale', () {
    expect(staleReminderIds([10, 11], <int>{}), [10, 11]);
  });

  test('event reminders read off while class reminders are off', () async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'event_reminders_enabled': true,
    });

    expect(await ReminderService.instance.eventsEnabled, isFalse);
  });

  test('event reminders read on when both gates are on', () async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': true,
      'event_reminders_enabled': true,
    });

    expect(await ReminderService.instance.eventsEnabled, isTrue);
  });

  test('event reminders default on once class reminders are on', () async {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': true});

    expect(await ReminderService.instance.eventsEnabled, isTrue);
  });

  test('a revoked permission outranks the exact-alarm warning', () {
    final warning = reminderWarning(
      enabled: true,
      notificationsAllowed: false,
      exactAlarmsAvailable: false,
    );

    expect(warning, contains('blocking Klasify notifications'));
  });

  test('no gate warning while reminders are off', () {
    expect(
      reminderWarning(
        enabled: false,
        notificationsAllowed: false,
        exactAlarmsAvailable: false,
      ),
      isNull,
    );
  });

  test('exact alarms warn only when notifications can appear', () {
    expect(
      reminderWarning(
        enabled: true,
        notificationsAllowed: true,
        exactAlarmsAvailable: false,
      ),
      contains('may delay'),
    );
    expect(
      reminderWarning(
        enabled: true,
        notificationsAllowed: true,
        exactAlarmsAvailable: true,
      ),
      isNull,
    );
  });
}
