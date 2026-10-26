import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/screens/home_screen.dart';
import 'package:klasify/theme/app_theme.dart';

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
      expect(find.text('TOMORROW'), findsNothing);
      expect(find.text('Tomorrow Math'), findsNothing);
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
      expect(find.text('TOMORROW'), findsNothing);
      expect(find.text('Next Day Chemistry'), findsNothing);
    },
  );
}
