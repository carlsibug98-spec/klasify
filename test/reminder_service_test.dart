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

  test('a past event alarm that is still pending is not treated as stale', () {
    expect(
      eventAlarmKeepDecision(
        enabled: true,
        remindMe: true,
        future: false,
        pending: true,
      ),
      isTrue,
      reason: 'an inexact alarm delayed past its time must still be allowed to fire',
    );
    expect(
      eventAlarmKeepDecision(
        enabled: true,
        remindMe: true,
        future: false,
        pending: false,
      ),
      isFalse,
      reason: 'a past event with no pending alarm has nothing to preserve',
    );
    expect(
      eventAlarmKeepDecision(
        enabled: false,
        remindMe: true,
        future: false,
        pending: true,
      ),
      isFalse,
      reason: 'a disabled gate must drop the alarm',
    );
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
