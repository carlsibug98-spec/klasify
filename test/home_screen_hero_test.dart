import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/routes/app_router.dart';
import 'package:klasify/screens/home_screen.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/next_class_card.dart';
import 'package:klasify/widgets/swipe_actions.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // NoIsolate: widget tests run in a fake async zone, and the isolate-
    // backed factory's responses never arrive there, so the home screen
    // stays on its skeleton. The no-isolate factory completes via
    // microtasks, which pump() drains.
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'home_hero_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});
  });

  testWidgets(
    'HomeScreen hero shows "All done for today" when today classes have passed',
    (tester) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final todayWeekday = now.weekday;
      final todayName = const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][todayWeekday - 1];
      final tomorrowWeekday = (todayWeekday % 7) + 1;
      final nowMinutes = now.hour * 60 + now.minute;
      final pastEnd = nowMinutes > 1 ? nowMinutes - 1 : 1;
      final pastStart = (pastEnd - 30).clamp(0, pastEnd - 1);

      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Morning Physics',
            room: 'Room 101',
            professor: 'Dr. Santos',
            day: todayWeekday,
            startMinutes: pastStart,
            endMinutes: pastEnd,
          ),
        );
        await db.insert(
          ClassItem(
            subject: 'Tomorrow Math',
            room: 'Room 202',
            professor: 'Prof. Lee',
            day: tomorrowWeekday,
            startMinutes: 480,
            endMinutes: 540,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('All done for today'), findsOneWidget);
      expect(find.text('Enjoy the rest of your $todayName.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      // The celebration now teases the next class (Tomorrow Math) on a
      // tappable shelf.
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Tomorrow Math'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeScreen hero shows "No classes today" when today has 0 classes scheduled',
    (tester) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final tomorrowWeekday = (now.weekday % 7) + 1;

      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Next Day Chemistry',
            room: 'Lab 3',
            professor: 'Prof. Gomez',
            day: tomorrowWeekday,
            startMinutes: 480,
            endMinutes: 540,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      final isWeekend = now.weekday >= DateTime.saturday;
      expect(
        find.text(isWeekend ? 'Weekend off' : 'No classes today'),
        findsOneWidget,
      );
      expect(
        find.text(
          isWeekend
              ? 'No classes today. Enjoy your break.'
              : 'Nothing scheduled. Enjoy the open time.',
        ),
        findsOneWidget,
      );
      expect(
        find.byIcon(
          isWeekend ? Icons.weekend_outlined : Icons.wb_sunny_outlined,
        ),
        findsOneWidget,
      );
      // The teaser shelf shows tomorrow's class.
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Next Day Chemistry'), findsOneWidget);
    },
  );

  group('hero swipe', () {
    // One class today: the hero shows it as "Upcoming" (or "In class" in the
    // last minutes of the day) and the Today list shows the same class, so
    // swipe finders must target the hero's wrapper specifically.
    //
    // The window must stay inside the current day even when the test runs at
    // 23:xx. A fixed now+120 start used to push endMinutes past 1440 after
    // 21:00, which made DatabaseHelper reject the fixture before the widget
    // under test was ever built.
    Future<void> pumpUpcomingHero(WidgetTester tester) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      final start = nowMinutes + 2 > 1438 ? 1438 : nowMinutes + 2;
      final end = start + 60 > 1440 ? 1440 : start + 60;
      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Hero Physics',
            room: 'Room 9',
            professor: 'Dr. Who',
            day: now.weekday,
            startMinutes: start,
            endMinutes: end,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: const HomeScreen(),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }

    Finder heroSwipe() => find.ancestor(
      of: find.byType(NextClassCard),
      matching: find.byType(SwipeActions),
    );

    testWidgets('a full swipe on the hero deletes it with a 5-second undo', (
      tester,
    ) async {
      await pumpUpcomingHero(tester);
      expect(heroSwipe(), findsOneWidget);

      await tester.drag(heroSwipe(), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('Class deleted'), findsOneWidget);
      final remaining = await tester.runAsync(
        () => DatabaseHelper.instance.getAll(),
      );
      expect(remaining, isEmpty);
    });

    testWidgets('undo brings the hero class back', (tester) async {
      await pumpUpcomingHero(tester);

      await tester.drag(heroSwipe(), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Class restored'), findsOneWidget);
      final remaining = await tester.runAsync(
        () => DatabaseHelper.instance.getAll(),
      );
      expect(remaining, hasLength(1));
    });

    testWidgets('the hero plane Edit opens the class form', (tester) async {
      await pumpUpcomingHero(tester);

      await tester.drag(heroSwipe(), const Offset(-100, 0));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: heroSwipe(),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit class'), findsOneWidget);
    });

    testWidgets('the celebration hero carries no swipe plane', (tester) async {
      // Guard for the non-goal: the all-done celebration has nothing to
      // delete, so it must stay unwrapped.
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Past Physics',
            room: 'Room 1',
            professor: 'Dr. Past',
            day: now.weekday,
            startMinutes: nowMinutes > 61 ? nowMinutes - 61 : 0,
            endMinutes: nowMinutes > 1 ? nowMinutes - 1 : 1,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('All done for today'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(NextClassCard),
          matching: find.byType(SwipeActions),
        ),
        findsNothing,
      );
    });

    testWidgets('the celebration teaser jumps to that day on Week', (
      tester,
    ) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final tomorrowWeekday = (now.weekday % 7) + 1;
      var jumpedTo = 0;
      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Tomorrow Math',
            room: 'Room 202',
            professor: 'Prof. Lee',
            day: tomorrowWeekday,
            startMinutes: 480,
            endMinutes: 540,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HomeScreen(onJumpToDay: (day) => jumpedTo = day),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // No class today, so the hero is the free-day celebration and the
      // shelf teases tomorrow's class. This fixture stays valid at any
      // wall-clock time, including the first minute of the day.
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('Tomorrow Math'), findsOneWidget);

      await tester.tap(find.text('Tomorrow Math'));
      await tester.pump();
      expect(jumpedTo, tomorrowWeekday);
    });


    testWidgets('the in-class hero carries the 6px elapsed bar', (
      tester,
    ) async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      // A class that is live right now and fits inside the day at any
      // wall-clock time. The zip's fixture (now-30 .. now+60) goes invalid
      // in the first half hour and after 22:30; this window does not.
      final start = nowMinutes > 0 ? nowMinutes - 1 : 0;
      final end = start + 90 > 1440 ? 1440 : start + 90;
      await tester.runAsync(() async {
        await db.replaceAll([]);
        await db.insert(
          ClassItem(
            subject: 'Live Physics',
            room: 'Room 5',
            professor: 'Dr. Live',
            day: now.weekday,
            startMinutes: start,
            endMinutes: end,
          ),
        );
      });

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.text('LIVE NOW'), findsOneWidget);
      final card = tester.widget<NextClassCard>(find.byType(NextClassCard));
      expect(card.liveProgress, isNotNull);
      expect(card.liveProgress, inInclusiveRange(0.0, 1.0));
      expect(card.liveRemaining, isNotNull);
    });
  });
}
