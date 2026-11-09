import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/event_item.dart';

void main() {
  // Synthetic fixtures only — the app never ships sample events; these
  // names exist to assert behavior, not to suggest content.
  const base = ('Test Event A', 'Test Hall');

  EventItem eventAt({
    int startMinutes = 540,
    bool remindMe = true,
    int lead = 30,
    String date = '2026-11-07',
    String? venue,
  }) => EventItem(
    title: base.$1,
    venue: venue ?? base.$2,
    date: date,
    startMinutes: startMinutes,
    remindMe: remindMe,
    leadMinutes: lead,
  );

  test('defaults match the class engine but plan longer ahead', () {
    expect(eventDefaultLeadMinutes, 30);
    expect(eventLeadChoices, [5, 10, 15, 30]);
    final fresh = const EventItem(
      title: 'Culture Day',
      venue: '',
      date: '2026-11-20',
      startMinutes: 540,
    );
    expect(fresh.remindMe, isTrue);
    expect(fresh.leadMinutes, eventDefaultLeadMinutes);
  });

  test('when and where compose in the mockup voice', () {
    expect(eventAt().whenAndWhereLabel, 'Test Hall · 9:00 AM');

    // Numeric venues get the room prefix like classes do.
    expect(
      eventAt(venue: '204').whenAndWhereLabel,
      'Room 204 · 9:00 AM',
    );

    // No venue recorded yet: the time alone, never a bare separator.
    expect(eventAt(venue: '').whenAndWhereLabel, '9:00 AM');
    expect(eventAt(venue: '  ').whenAndWhereLabel, '9:00 AM');
  });

  test('the reminder fire time is the start minus the lead', () {
    // 9:00 AM start, 30 minutes before: the mockup's "Reminder 8:30 AM".
    expect(eventAt(startMinutes: 540, lead: 30).reminderFireLabel, '8:30 AM');
    expect(eventAt(startMinutes: 600, lead: 15).reminderFireLabel, '9:45 AM');

    // A lead longer than the gap to midnight clamps to the start itself,
    // never before the day's first minute — the class engine's rule.
    expect(eventAt(startMinutes: 25, lead: 30).reminderFireLabel, '12:25 AM');

    expect(
      eventAt(startMinutes: 600, lead: 5).leadLabel,
      '5 minutes before',
    );
  });

  test('upcoming means not started yet', () {
    final now = DateTime(2026, 11, 7, 10, 0);

    expect(
      eventAt(date: '2026-11-08').isUpcomingOn(now),
      isTrue,
      reason: 'tomorrow is always upcoming',
    );
    expect(eventAt(date: '2026-11-07', startMinutes: 720).isUpcomingOn(now),
        isTrue, reason: 'today, later start');
    expect(eventAt(date: '2026-11-07', startMinutes: 599).isUpcomingOn(now),
        isFalse, reason: 'today, already started');
    expect(eventAt(date: '2026-11-07', startMinutes: 600).isUpcomingOn(
          DateTime(2026, 11, 7, 10, 0),
        ),
        isFalse, reason: 'the starting minute itself is not upcoming');
    expect(eventAt(date: '2026-11-06').isUpcomingOn(now), isFalse);
  });

  test('maps round-trip, including the reminder fields', () {
    final event = eventAt(startMinutes: 540, lead: 15, remindMe: false);
    final map = event.toMap();
    expect(map.containsKey('id'), isFalse);

    final restored = EventItem.fromMap({'id': 7, ...map});
    expect(restored.id, 7);
    expect(restored.title, event.title);
    expect(restored.venue, event.venue);
    expect(restored.date, event.date);
    expect(restored.startMinutes, event.startMinutes);
    expect(restored.remindMe, isFalse);
    expect(restored.leadMinutes, 15);
  });

  test('legacy rows default their reminder fields on', () {
    // Events added before the reminder switch existed read as if the
    // switch had been left on.
    final legacy = EventItem.fromMap({
      'id': 3,
      'title': 'Test Event A',
      'venue': 'Test Hall',
      'date': '2026-11-07',
      'start_minutes': 540,
    });
    expect(legacy.remindMe, isTrue);
    expect(legacy.leadMinutes, eventDefaultLeadMinutes);
  });

  test('broadcast scope round-trips with the department', () {
    final event = const EventItem(
      title: 'IT Dept Event',
      venue: 'Lab 2',
      date: '2026-11-21',
      startMinutes: 540,
      department: 'IT',
      broadcast: true,
    );
    final map = event.toMap();
    expect(map['broadcast'], 1);
    expect(map['department'], 'IT');

    final restored = EventItem.fromMap({'id': 9, ...map});
    expect(restored.broadcast, isTrue);
    expect(restored.department, 'IT');
  });

  test('non-broadcast events default to personal scope', () {
    final map = eventAt().toMap();
    expect(map['broadcast'], 0);
    expect(map['department'], isNull);
    expect(EventItem.fromMap({'id': 1, ...map}).broadcast, isFalse);
  });

  test('legacy rows without broadcast columns read as personal', () {
    final legacy = EventItem.fromMap({
      'id': 4,
      'title': 'Test Event A',
      'venue': '',
      'date': '2026-11-07',
      'start_minutes': 600,
    });
    expect(legacy.broadcast, isFalse);
    expect(legacy.department, isNull);
  });

  test('the sheet kicker reads "Sat, Nov 7"', () {
    expect(eventKickLabel(DateTime(2026, 11, 7)), 'Sat, Nov 7');
    expect(eventKickLabel(DateTime(2026, 1, 1)), 'Thu, Jan 1');
  });
}
