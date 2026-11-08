import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/main.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/screens/main_navigation_screen.dart';
import 'package:klasify/widgets/bottom_navigation_item.dart';
import 'package:klasify/widgets/week_agenda_view.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // NoIsolate: widget tests run in a fake async zone where the isolate-
    // backed factory's responses never arrive, so DB-driven screens would
    // stay on their loading spinner (an endless animation that also makes
    // pumpAndSettle time out). The no-isolate factory completes via
    // microtasks, which pump() drains.
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'widget_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  setUp(() {
    // The shell's one-time coach tour would otherwise mount over these
    // tests' Today view (the last test leaves a class in the shared DB);
    // pin them to the already-shown behavior they were written against.
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'coach_tour_shown': true,
      'first_class_coach_dismissed': true,
    });
  });

  testWidgets('Klasify app opens', (WidgetTester tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    // Open the database in a real-async window before pumping: once open,
    // the screens' queries complete via microtasks that pump() drains. A
    // lazy open started inside the fake-async zone never resolves, which
    // leaves the loading spinners (infinite animations) ticking forever
    // and makes pumpAndSettle time out.
    await tester.runAsync(() async {
      await DatabaseHelper.instance.getAll();
    });

    await tester.pumpWidget(const ScheduleApp());

    // The home screen starts by loading classes from the local database.
    // Pump once more so the initial loading state can settle where possible.
    await tester.pump();

    expect(find.text('Klasify'), findsOneWidget);
    expect(find.bySemanticsLabel('Today'), findsOneWidget);
    expect(find.bySemanticsLabel('Week'), findsOneWidget);
    expect(find.text('Import'), findsNothing);
    expect(find.bySemanticsLabel('Profile'), findsOneWidget);
    expect(find.byType(BottomNavigationItem), findsNWidgets(3));
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(800, 1000);
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(BottomNavigationItem), findsNothing);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(find.byType(BottomNavigationItem), findsNWidgets(3));
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.bySemanticsLabel('Week'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Weekly schedule'), findsOneWidget);
    expect(find.byTooltip('Switch to weekly grid'), findsNothing);
    expect(find.text('Week at a glance'), findsNothing);
    // The quick-actions FAB replaced the dedicated Add-class FAB.
    expect(find.byTooltip('Open class actions'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pump(const Duration(milliseconds: 500));
    // Settings is a reading surface: the add-class action steps aside (the
    // FAB stays in the tree but is faded out and ignores pointer input).
    expect(find.byTooltip('Open class actions'), findsOneWidget);
    // The settings row was renamed from "Import a timetable" to match its
    // route and the import screen's app bar ("Import schedule").
    expect(find.text('Import schedule'), findsOneWidget);

    await tester.tap(find.text('Import schedule'));
    // The import screen gates its content behind a delayed init, so a fixed
    // 500ms pump can land a frame too early; settle instead.
    await tester.pumpAndSettle();
    expect(find.text('Import schedule'), findsOneWidget);
    await tester.pageBack();
    // Leaving the import screen flips canPop and awaits endOfFrame before
    // popping, so the settings screen needs several frames to come back.
    await tester.pumpAndSettle();

    expect(find.text('Class reminders'), findsOneWidget);
    expect(find.text('Backup and restore'), findsOneWidget);
    expect(find.text('How Klasify works'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Today'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Klasify'), findsOneWidget);
    expect(find.byTooltip('Open class actions'), findsOneWidget);
  });

  testWidgets('a week-day request lands on that day', (
    WidgetTester tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      MainNavigationScreen.weekDayRequest.value = null;
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    // Tomorrow, so the Week tab's default (today) selection cannot make this
    // pass by accident.
    final target = (DateTime.now().weekday % 7) + 1;
    await tester.runAsync(() async {
      await DatabaseHelper.instance.replaceAll([]);
      await DatabaseHelper.instance.insert(
        ClassItem(
          subject: 'Jump Target',
          room: 'Room 7',
          professor: 'Dr. Jump',
          day: target,
          startMinutes: 600,
          endMinutes: 660,
        ),
      );
    });

    MainNavigationScreen.weekDayRequest.value = null;
    await tester.pumpWidget(const ScheduleApp());
    await tester.pump();

    MainNavigationScreen.weekDayRequest.value = target;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Weekly schedule'), findsOneWidget);
    final agenda = tester.widget<WeekAgendaView>(find.byType(WeekAgendaView));
    expect(agenda.selectedDay, target);
    expect(MainNavigationScreen.weekDayRequest.value, isNull);
  });
}
