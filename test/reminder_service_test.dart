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
}
