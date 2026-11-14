import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_status.dart' show dateKey;
import 'package:klasify/models/event_item.dart' show EventItem, shortWeekdayNames;
import 'package:klasify/screens/home_screen.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Synthetic events only — the app never carries sample data; everything
/// below exists to exercise the section the user then fills themselves.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // NoIsolate: widget tests run in a fake async zone, and the isolate-
    // backed factory's responses never arrive there (same as the hero test).
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'events_home_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  setUp(() {
    // Reminders stay off in widget tests: the launch sync short-circuits
    // before it can touch the notification plugin.
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});
  });

  Future<void> clearEvents() async {
    final db = DatabaseHelper.instance;
    for (final e in await db.getAllEvents()) {
      await db.deleteEvent(e.id!);
    }
  }

  EventItem seed(String title, {required int daysAhead, int startHour = 10}) {
    final day = DateTime.now().add(Duration(days: daysAhead));
    return EventItem(
      title: title,
      venue: daysAhead % 2 == 0 ? 'Test Hall' : 'Gymnasium',
      date: dateKey(day),
      startMinutes: startHour * 60,
      remindMe: true,
      leadMinutes: 30,
    );
  }

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const HomeScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the section starts quiet: header and Add, no rows', (
    tester,
  ) async {
    await tester.runAsync(clearEvents);
    await pumpHome(tester);

    expect(find.text('Events'), findsOneWidget);
    expect(find.byKey(const ValueKey('events-add')), findsOneWidget);
    // No event tiles, so no "upcoming event" count either.
    expect(find.text('Gymnasium · 10:00 AM'), findsNothing);
  });

  testWidgets('upcoming events render rows, count chip, and reminder pill', (
    tester,
  ) async {
    // Semantics must be on before the frame: bySemanticsLabel finds nothing
    // unless the owner was enabled while the tree was pumped.
    final semantics = tester.ensureSemantics();
    await tester.runAsync(clearEvents);
    final a = seed('Test Event A', daysAhead: 2);
    final b = seed('Test Event B', daysAhead: 5, startHour: 13);
    final db = DatabaseHelper.instance;
    await tester.runAsync(() async {
      await db.insertEvent(a);
      await db.insertEvent(b);
    });
    await pumpHome(tester);
    // Semantics flushes with frames, and pumpHome's last flush rode the
    // loading spinner's build. One pump later, the painted rows and their
    // annotations (count chip, Add event) have materialized.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Test Event A'), findsOneWidget);
    expect(find.text('Test Event B'), findsOneWidget);

    // The Add chip stays, and the count lands on the chip's own semantics
    // label — a bare find.text('2') would collide with a date block that
    // happens to print the numeral 2 late in a month.
    expect(find.descendant(
      of: find.byKey(const ValueKey('events-add')),
      matching: find.text('Add'),
    ), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('2 upcoming events')), findsOneWidget);

    // Date blocks read the weekday (N+2 and N+5 never share one).
    expect(
      find.text(shortWeekdayNames[a.day.weekday - 1].toUpperCase()),
      findsOneWidget,
    );
    expect(
      find.text(shortWeekdayNames[b.day.weekday - 1].toUpperCase()),
      findsOneWidget,
    );

    // Venue · time meta with a reminder fire time on each row.
    expect(find.text('Test Hall · 10:00 AM'), findsOneWidget);
    expect(find.text('Gymnasium · 1:00 PM'), findsOneWidget);
    expect(find.text('Reminder 9:30 AM'), findsOneWidget);

    // Past events never render: one old event stays invisible.
    final past = const EventItem(
      title: 'An Old Event',
      venue: '',
      date: '2001-01-01',
      startMinutes: 540,
    );
    await tester.runAsync(() => db.insertEvent(past));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('An Old Event'), findsNothing);
    semantics.dispose();
  });

  testWidgets('Add opens a blank form whose Save lands a real event', (
    tester,
  ) async {
    await tester.runAsync(clearEvents);
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('events-add')));
    await tester.pumpAndSettle();

    // The new-event sheet: headline kicker and save up top, and the sync
    // footnote at the very bottom — which sits past the fold on this test
    // surface, so scroll the sheet to it, assert, then scroll back to
    // keep the form editable.
    expect(find.text('NEW EVENT'), findsOneWidget);
    expect(find.text('Save reminder'), findsOneWidget);
    await tester.dragFrom(
      tester.getCenter(find.text('NEW EVENT')),
      const Offset(0, -200),
    );
    await tester.pump();
    expect(
      find.textContaining('Saved on this phone'),
      findsOneWidget,
    );
    await tester.dragFrom(
      tester.getCenter(find.text('Save reminder')),
      const Offset(0, 200),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'Test Culture Day');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Save reminder'));
    await tester.pumpAndSettle();

    // The sheet closed back into Today and the row exists — reloaded
    // through the database listener, not the form's widget state.
    expect(find.text('Test Culture Day'), findsOneWidget);
  });

  testWidgets('tapping an event row opens it for editing with Delete', (
    tester,
  ) async {
    await tester.runAsync(clearEvents);
    final a = seed('Test Event A', daysAhead: 2);
    await tester.runAsync(() => DatabaseHelper.instance.insertEvent(a));
    await pumpHome(tester);

    await tester.tap(find.text('Test Event A'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('EVENT · '),
      findsOneWidget,
      reason: 'the kicker reflects the event day',
    );
    expect(find.text('Test Event A'), findsWidgets,
        reason: 'the row behind the sheet and the sheet field both carry it');
    expect(find.text('Remind me'), findsOneWidget);
    expect(find.text('Alert'), findsOneWidget);
    expect(find.text('30 minutes before'), findsOneWidget);

    // The Delete action sits past the fold on this test surface: scroll
    // the sheet down to reach it.
    await tester.dragFrom(
      tester.getCenter(find.textContaining('EVENT · ')),
      const Offset(0, -200),
    );
    await tester.pump();
    expect(find.text('Delete event'), findsOneWidget);

    // Close without touching: the sheet pops back to Today. The test
    // surface can be short enough that the sheet leaves no barrier above
    // it, so pop the route directly — identical contract: nothing changed.
    final nav = Navigator.of(
      tester.element(find.text('Delete event')),
    );
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('Delete event'), findsNothing);
  });
}
