import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/routes/app_router.dart';
import 'package:klasify/screens/main_navigation_screen.dart';
import 'package:klasify/services/coach_tour_store.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The one-time coach tour teaches one thing — the Today screen's gestures —
/// so it may only play while Today is really on screen. These tests pin the
/// shell's triggers: a shell opening on a schedule, the import-style save
/// that happens under a pushed route before the flow lands on Week, and
/// route pops back to the shell.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // NoIsolate: completes via microtasks, which pump() drains inside the
    // fake-async widget-test zone; the isolate-backed factory never resolves
    // there and would leave every screen on its loading spinner.
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'coach_trigger_${DateTime.now().microsecondsSinceEpoch}.db';
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    // Launcher-widget sync: no native side in the tester.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('klasify/next_class_widget'),
      (call) async => null,
    );
  });

  tearDown(() => MainNavigationScreen.tabRequest.value = null);

  /// Seeds the schedule and opens the database outside the fake-async zone;
  /// later queries resolve through microtasks that pump() drains.
  ///
  /// The class is anchored to the real wall clock so Today always has the
  /// live/next hero the tour's first step anchors on: a strict-future class
  /// while the morning leaves room, a live class through the evening, and a
  /// plain past class only in the narrow midnight edge where nothing fits
  /// (like app_look_capture_test, that window leans on daytime runs).
  Future<void> seed(WidgetTester tester, {required bool hasClass}) async {
    await tester.runAsync(() async {
      if (!hasClass) {
        await DatabaseHelper.instance.replaceAll([]);
        return;
      }
      final now = DateTime.now();
      final wallM = now.hour * 60 + now.minute;
      var start = wallM + 15;
      var end = start + 60;
      if (end > 24 * 60 - 5) {
        // Evening: a live class that can still end before midnight.
        start = wallM;
        end = 24 * 60 - 5;
      }
      if (start > 24 * 60 - 5 || start >= end) {
        // Midnight edge (23:55–00:00): nothing fits; use a past one.
        start = 10 * 60;
        end = 11 * 60;
      }
      final day = DateTime.now().weekday;
      await DatabaseHelper.instance.replaceAll([
        ClassItem(
          subject: 'Coach Test',
          room: 'Room 1',
          professor: 'Dr. Coach',
          day: day,
          startMinutes: start,
          endMinutes: end,
        ),
      ]);
    });
  }

  Future<void> setUpPhone(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget shellHost() => MaterialApp(
        theme: AppTheme.light(),
        // The shell learns about route pops through this observer, the same
        // hook the app registers on MaterialApp.
        navigatorObservers: [AppRouter.routeObserver],
        home: const MainNavigationScreen(),
      );

  /// The full tour's first tooltip; the empty-schedule coach says something
  /// else ('Add your first class'), so this can't collide with that one.
  Finder tourTooltip() => find.text('Your next class');

  /// Lets real-async database continuations (the sqflite FFI reads behind
  /// the shell's and HomeScreen's listener chains) step through between
  /// pumps; plain pump() calls alone can leave those chains unresolved.
  Future<void> dbSettle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('a shell opening on unseen classes plays the tour over Today', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'first_class_coach_dismissed': true,
    });
    await setUpPhone(tester);
    await seed(tester, hasClass: true);

    await tester.pumpWidget(shellHost());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // The tooltip paints a frame after the overlay's post-frame anchor
    // lookup (the spotlight needs measured geometry first).
    await tester.pump(const Duration(milliseconds: 320));

    expect(tourTooltip(), findsOneWidget);
    expect(await CoachTourStore.isShown(), isTrue);
  });

  testWidgets('an import-style save under a pushed route never tours Week', (
    tester,
  ) async {
    // The empty-schedule coach is dismissed so it can't overlap this flow.
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'first_class_coach_dismissed': true,
    });
    await setUpPhone(tester);
    await seed(tester, hasClass: false);

    await tester.pumpWidget(shellHost());
    await tester.pump(const Duration(milliseconds: 200));

    // Mirror the import flow: the shell sits under a pushed screen, and that
    // screen saves classes into the database while it holds the pointer.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    // (Navigator.push completes on pop; don't await it or the flow deadlocks.)
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'stub-import'),
          builder: (_) => const Scaffold(
            body: Center(child: Text('stub import screen')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('stub import screen'), findsOneWidget);

    await seed(tester, hasClass: true);
    // The DB write notifies both listeners under the stub: HomeScreen reloads
    // (fires the pending first-class trigger) and the shell syncs. Both
    // attempts must defer while Today is covered, so let them finish here.
    await dbSettle(tester);

    // Closing the flow jumps the shell to Week (the import "View schedule"
    // tap) right before popping itself.
    MainNavigationScreen.tabRequest.value = MainNavigationScreen.weekTab;
    // NavigatorState.pop is void; the pop's frame lands on the next pump.
    navigator.pop();
    await dbSettle(tester);

    expect(find.text('Weekly schedule'), findsOneWidget);
    expect(tourTooltip(), findsNothing);
    expect(await CoachTourStore.isShown(), isFalse);

    // Returning to Today finally plays the one-time tour, over Today only.
    // The request notifier is the shell's cross-screen Today-landing path —
    // the same `_selectDestination` receiver a bottom-nav tap calls.
    MainNavigationScreen.tabRequest.value = MainNavigationScreen.todayTab;
    await dbSettle(tester);
    // The overlay mounts one pump later than the (rejected) state checks
    // above suggest: its post-frame pruner re-waits a frame for the hero
    // anchor to lay out inside the newly shown Today pane before measuring
    // the spotlight, so the tooltip only appears on a second settle.
    await dbSettle(tester);

    // IndexedStack keeps hidden tabs' text alive, so the Today switch is
    // verified through the mounted tour itself rather than by absence.
    expect(tourTooltip(), findsOneWidget);
    expect(await CoachTourStore.isShown(), isTrue);
  });

  testWidgets('a shell opening on an already-seen schedule stays silent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'first_class_coach_dismissed': true,
      'coach_tour_shown': true,
    });
    await setUpPhone(tester);
    await seed(tester, hasClass: true);

    await tester.pumpWidget(shellHost());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tourTooltip(), findsNothing);
    expect(await CoachTourStore.isShown(), isTrue);
  });
}
