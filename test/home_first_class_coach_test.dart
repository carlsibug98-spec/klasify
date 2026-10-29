import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/screens/home_screen.dart';
import 'package:klasify/services/first_class_coach_store.dart';
import 'package:klasify/theme/app_theme.dart';

/// The empty-schedule coach: newcomers who tap "Explore first" (or skip
/// onboarding) land on the bare Scan/Add tiles with no class yet. The coach
/// spotlights those tiles once, then gets out of the way permanently.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The no-isolate factory completes via microtasks, which pump() drains
    // inside the fake-async test zone (isolate backed responses don't).
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'first_coach_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});
  });

  Future<DatabaseHelper> emptySchedule(WidgetTester tester) async {
    final db = DatabaseHelper.instance;
    // Opening the database touches the file system, and real async never
    // completes inside a widget test's fake-async zone â€” runAsync opens it
    // once; queries after that resolve through microtasks.
    await tester.runAsync(() => db.replaceAll([]));
    return db;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('empty schedule shows the one-shot coach over the tiles', (
    tester,
  ) async {
    await emptySchedule(tester);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(firstRunTilesKey: GlobalKey()),
      ),
    );
    await settle(tester);

    expect(find.text('Add your first class'), findsOneWidget);
    expect(find.text('START HERE'), findsOneWidget);
    // The two tiles stay on the page, and the copy names both ways in.
    expect(find.text('Scan it'), findsOneWidget);
    expect(find.text('Add by hand'), findsOneWidget);
    expect(find.textContaining('photo or PDF'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);

    // One shot: dismissing persists, and nothing of the coach remains.
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Add your first class'), findsNothing);
    expect(await FirstClassCoachStore.isDismissed(), isTrue);
  });

  testWidgets('never shows twice', (tester) async {
    await emptySchedule(tester);
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'first_class_coach_dismissed': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(firstRunTilesKey: GlobalKey()),
      ),
    );
    await settle(tester);

    expect(find.text('Add your first class'), findsNothing);
  });

  testWidgets('stays clear of anyone who already took the full tour', (
    tester,
  ) async {
    await emptySchedule(tester);
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'coach_tour_shown': true,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(firstRunTilesKey: GlobalKey()),
      ),
    );
    await settle(tester);

    expect(find.text('Add your first class'), findsNothing);
  });

  testWidgets('without a shell anchor the coach stays hidden for plain hosts', (
    tester,
  ) async {
    // Only MainNavigationScreen passes the tiles key; other hosts (tests,
    // previews) get the bare empty state without a coach.
    await emptySchedule(tester);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
    );
    await settle(tester);

    expect(find.text('Add your first class'), findsNothing);
  });
}
