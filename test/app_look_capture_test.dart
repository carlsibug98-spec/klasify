import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/models/event_item.dart';
import 'package:klasify/screens/main_navigation_screen.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Captures what the app actually looks like right now: the real
/// [MainNavigationScreen] shell (Today / Week / Settings tabs) pumped from
/// the live code with a seeded weekday schedule, in both themes.
///
/// Run with the store timezone so the clock lands mid-day and the hero
/// renders its live state: `TZ=Asia/Manila flutter test --update-goldens`.
/// Font loading mirrors design_capture_test.dart (the SDK font cache must
/// be indexed case-insensitively for the Linux artifact layout).

String _resolveFontDir() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) {
    return '$env/bin/cache/artifacts/material_fonts';
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 4; i++) {
    dir = dir.parent;
  }
  return '${dir.path}/bin/cache/artifacts/material_fonts';
}

final String _fontDir = _resolveFontDir();

Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
  final byName = {
    for (final e in Directory(_fontDir).listSync())
      e.uri.pathSegments.last.toLowerCase(): e.path,
  };
  for (final f in files) {
    final path = byName[f.toLowerCase()];
    if (path == null) {
      throw StateError('Font $f not found in $_fontDir');
    }
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

ThemeData _theme(bool dark) {
  final base = dark ? AppTheme.dark() : AppTheme.light();
  TextStyle? buttonText(ButtonStyle? style) => style?.textStyle
      ?.resolve(const <WidgetState>{})
      ?.copyWith(fontFamily: 'Roboto');
  ButtonStyle? withFont(ButtonStyle? style) =>
      style?.copyWith(textStyle: WidgetStatePropertyAll(buttonText(style)));
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: withFont(base.filledButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: withFont(base.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: withFont(base.outlinedButtonTheme.style),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Roboto',
      ),
    ),
  );
}

const _phoneInsets = EdgeInsets.only(top: 44, bottom: 34);

final _rootKey = GlobalKey();

void main() {
  setUpAll(() async {
    await _load('Roboto', [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
    ]);
    await _load('MaterialIcons', ['materialicons-regular.otf']);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    // Launcher-widget sync: no native side in the tester; answer with null
    // so MainNavigationScreen's schedule sync is a clean no-op.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('klasify/next_class_widget'),
      (call) async => null,
    );
    sqfliteFfiInit();
    // NoIsolate: widget tests run in a fake async zone (see the hero test).
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'app_look_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  testWidgets('capture Today / Week / Settings in both themes', (tester) async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'onboarding_completed': true,
      'coach_tour_shown': true,
    });

    // --- Seed a believable school day relative to the real clock. -------
    final now = DateTime.now();
    final today = now.weekday;
    // Clamp the seed reference so night runs (00:00–02:59) never produce a
    // negative start time; captures for the look book should still be
    // regenerated in the daytime window with --update-goldens.
    final realM = now.hour * 60 + now.minute;
    final nowM = realM < 180 ? 180 : realM;

    // Classes are anchored to the real clock so the app's own "now" logic
    // marks one class live (hero pulse) and earlier ones finished. Evening
    // runs compress the upcoming pair so everything ends before midnight.
    final futureBudget = 23 * 60 + 55 - nowM;
    int upcomingStart, upcomingEnd, secondEnd;
    if (futureBudget >= 260) {
      upcomingStart = 70;
      upcomingEnd = 180;
      secondEnd = 260;
    } else if (futureBudget >= 245) {
      upcomingStart = 50;
      upcomingEnd = 155;
      secondEnd = 245;
    } else if (futureBudget >= 165) {
      upcomingStart = 50;
      upcomingEnd = 165;
      secondEnd = -1; // no second class fits tonight
    } else {
      upcomingStart = -1;
      upcomingEnd = -1;
      secondEnd = -1;
    }

    final todays = <ClassItem>[
      ClassItem(
        subject: 'Data Structures',
        room: '301',
        professor: 'Prof. Reyes',
        day: today,
        startMinutes: nowM - 170,
        endMinutes: nowM - 95,
      ),
      ClassItem(
        subject: 'Advanced Mathematics',
        room: '304',
        professor: 'Prof. Chen',
        day: today,
        startMinutes: nowM - 50,
        // Late-evening runs (after ~23:20) would push the end past midnight,
        // which validateClass rejects. Clamp to 23:55 so the seed always
        // stays within the day; near midnight the hero shows the class as
        // finished instead of live, which is fine for a smoke run.
        endMinutes: math.min(nowM + 40, 1435),
      ),
      if (upcomingStart > 0)
        ClassItem(
          subject: 'Software Engineering',
          room: '302',
          professor: 'Prof. Turing',
          day: today,
          startMinutes: nowM + upcomingStart,
          endMinutes: nowM + upcomingEnd,
        ),
      // Back to back with the previous one: merges into the same stack.
      if (secondEnd > 0)
        ClassItem(
          subject: 'Operating Systems',
          room: '108',
          professor: 'Prof. Lovelace',
          day: today,
          startMinutes: nowM + upcomingEnd,
          endMinutes: nowM + secondEnd,
        ),
    ];

    // The rest of the week so the Week tab's day bar carries class dots.
    // Extras on `today`'s weekday are skipped: the relative `todays` list
    // already owns that day, and the database rejects same-day overlaps.
    final extras = <ClassItem>[
      const ClassItem(
        subject: 'Calculus',
        room: '201',
        professor: 'Prof. Reyes',
        day: 1,
        startMinutes: 9 * 60,
        endMinutes: 10 * 60 + 30,
      ),
      const ClassItem(
        subject: 'Physics Laboratory',
        room: 'Lab 2',
        professor: 'Prof. Chen',
        day: 1,
        startMinutes: 13 * 60,
        endMinutes: 14 * 60 + 30,
      ),
      const ClassItem(
        subject: 'Discrete Mathematics',
        room: '305',
        professor: 'Prof. Turing',
        day: 2,
        startMinutes: 10 * 60 + 15,
        endMinutes: 11 * 60 + 15,
      ),
      const ClassItem(
        subject: 'Statistics',
        room: '210',
        professor: 'Prof. Lovelace',
        day: 2,
        startMinutes: 14 * 60,
        endMinutes: 15 * 60 + 30,
      ),
      const ClassItem(
        subject: 'Data Structures',
        room: '301',
        professor: 'Prof. Reyes',
        day: 3,
        startMinutes: 9 * 60 + 30,
        endMinutes: 11 * 60,
      ),
      const ClassItem(
        subject: 'Software Engineering',
        room: '302',
        professor: 'Prof. Turing',
        day: 3,
        startMinutes: 13 * 60,
        endMinutes: 14 * 60 + 30,
      ),
      const ClassItem(
        subject: 'Advanced Mathematics',
        room: '304',
        professor: 'Prof. Chen',
        day: 4,
        startMinutes: 11 * 60,
        endMinutes: 12 * 60 + 30,
      ),
      const ClassItem(
        subject: 'Design Seminar',
        room: 'Hall A',
        professor: 'Prof. Lovelace',
        day: 4,
        startMinutes: 15 * 60,
        endMinutes: 16 * 60,
      ),
      const ClassItem(
        subject: 'Calculus',
        room: '201',
        professor: 'Prof. Reyes',
        day: 6,
        startMinutes: 10 * 60,
        endMinutes: 11 * 60 + 30,
      ),
    ].where((c) => c.day != today).toList();
    final week = <ClassItem>[...todays, ...extras];

    // Whole-school events around the seeded day: one this afternoon plus
    // two further out, so the Events section under the classes renders
    // with real rows (count chip, inverted date block, tiles).
    final events = [
      EventItem(
        title: 'Foundation Day Assembly',
        venue: 'Main Grounds',
        date: dateKey(now),
        startMinutes: 15 * 60,
        remindMe: false,
        leadMinutes: 30,
      ),
      EventItem(
        title: 'Midterm Examinations',
        venue: 'Testing Center',
        date: dateKey(now.add(const Duration(days: 5))),
        startMinutes: 8 * 60,
        remindMe: true,
        leadMinutes: 30,
      ),
      EventItem(
        title: 'Campus Sports Fest',
        venue: 'Gymnasium',
        date: dateKey(now.add(const Duration(days: 12))),
        startMinutes: 13 * 60,
        remindMe: true,
        leadMinutes: 30,
      ),
    ];

    final db = DatabaseHelper.instance;
    await tester.runAsync(() async {
      await db.replaceAll([]);
      for (final c in week) {
        await db.insert(c);
      }
      // Events own their own table: clear what other suites left behind,
      // then seed the look-book rows.
      for (final e in await db.getAllEvents()) {
        await db.deleteEvent(e.id!);
      }
      for (final e in events) {
        await db.insertEvent(e);
      }
    });

    Future<void> shootTab(String name) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      // The captures are clock-anchored (countdown text, live hero), so the
      // pixels only ever match right after a regeneration. Plain suite runs
      // therefore exercise the render as a smoke test and leave the pixels
      // to explicit `flutter test --update-goldens` captures.
      if (!autoUpdateGoldenFiles) return;
      await expectLater(
        find.byKey(_rootKey),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    Future<void> captureTheme(bool dark) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      final suffix = dark ? 'dark' : 'light';

      await tester.pumpWidget(
        RepaintBoundary(
          key: _rootKey,
          // Keyed MaterialApp per theme run: a fresh app element skips the
          // framework's 200ms theme animation, matching a real fresh launch
          // that starts on its final theme (the sticky header delegate only
          // rebuilds on data changes, so a mid-animation build would stick).
          child: MaterialApp(
            key: ValueKey('app-$suffix'),
            theme: _theme(dark),
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: _phoneInsets,
                  viewPadding: _phoneInsets,
                  viewInsets: EdgeInsets.zero,
                ),
                child: child!,
              );
            },
            // A keyed shell per theme run: without it the second pumpWidget
            // reconciles into the same State and inherits the previous tab
            // selection instead of a fresh launch on Today.
            home: MainNavigationScreen(key: ValueKey('shell-$suffix')),
          ),
        ),
      );
      // Let the database stream land, then past the hero's pulse setup.
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 150));
      });
      await shootTab('look_today_$suffix');

      // Week tab.
      await tester.tap(find.text('Week').last, warnIfMissed: false);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 600));
      await shootTab('look_week_$suffix');

      // Profile tab.
      await tester.tap(find.text('Profile').last, warnIfMissed: false);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      // Settings has no motion of its own, but the shell's hero countdown
      // ticks every second, so pumpAndSettle would never return: fixed
      // pumps let the async preference load land instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await shootTab('look_profile_$suffix');

      debugDisableShadows = true;
    }

    await captureTheme(false);
    await captureTheme(true);
  });
}
