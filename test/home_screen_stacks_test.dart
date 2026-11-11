import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/screens/home_screen.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/campus_break_divider.dart';
import 'package:klasify/widgets/class_segment_row.dart';

/// The Today screen's segmented stacks (the weekly schedule's approved
/// language applied under the hero): consecutive classes merge into one
/// rail with the settings' segment corners, break chips sit between
/// stacks, and every row is a [ClassSegmentRow] wired to the swipe plane.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // NoIsolate: widget tests run in a fake async zone, and the isolate-
    // backed factory's responses never arrive there (see the hero test).
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'home_stacks_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});
  });

  ClassItem todayClass(
    String subject,
    int startMinutes,
    int endMinutes, {
    String room = '302',
    String professor = 'Prof. Turing',
  }) {
    return ClassItem(
      subject: subject,
      room: room,
      professor: professor,
      day: DateTime.now().weekday,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
  }

  Future<List<ClassSegmentRow>> pumpToday(
    WidgetTester tester,
    List<ClassItem> classes,
  ) async {
    // A live hero keeps the next-up row focused beneath it, which used to
    // push the last stack past the default test viewport's initial
    // build range (the list is lazy; real devices just scroll). Size the
    // window so every stack is built — same surface pattern widget_test
    // uses — then reset so nothing leaks between cases.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2400);
    addTearDown(tester.view.reset);
    final db = DatabaseHelper.instance;
    await tester.runAsync(() async {
      await db.replaceAll([]);
      for (final c in classes) {
        await db.insert(c);
      }
    });
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
    );
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    return tester
        .widgetList<ClassSegmentRow>(find.byType(ClassSegmentRow))
        .toList();
  }

  /// The wall-clock fixture window for the live-hero stack test: a
  /// 90-minute live class anchored to the real clock, then, when it fits, a
  /// 60-minute upcoming class 40 minutes after the live one ends.
  ///
  /// Kept as a pure function so its day-end arithmetic can be checked at
  /// every minute of the day instead of only when the suite happens to run
  /// in the failing window.
  ({int liveStart, int liveEnd, bool roomForNextUp}) liveWindowAt(int nowM) {
    final liveStart = nowM > 0 ? nowM - 1 : 0;
    final liveEnd = liveStart + 90 > 1440 ? 1440 : liveStart + 90;
    // The upcoming class spans liveEnd+40 .. liveEnd+100, so the whole
    // window — not just its start — must fit before midnight. Checking only
    // the start let the fixture run past 24:00 between 20:52 and 21:51 and
    // fail validateClass in the test setup.
    final roomForNextUp = liveEnd + 100 <= 1440;
    return (
      liveStart: liveStart,
      liveEnd: liveEnd,
      roomForNextUp: roomForNextUp,
    );
  }

  test('the live-window fixture is valid at every minute of the day', () {
    for (var nowM = 0; nowM < 1440; nowM++) {
      final window = liveWindowAt(nowM);
      expect(window.liveStart, inInclusiveRange(0, 1439), reason: 'nowM=$nowM');
      expect(
        window.liveEnd,
        inInclusiveRange(window.liveStart + 1, 1440),
        reason: 'nowM=$nowM',
      );
      if (window.roomForNextUp) {
        // The upcoming class is inserted at liveEnd+40 .. liveEnd+100 and
        // must pass DatabaseHelper.validateClass in full.
        expect(
          window.liveEnd + 100,
          lessThanOrEqualTo(1440),
          reason: 'nowM=$nowM',
        );
      }
    }
  });

  testWidgets('a live hero leaves the next-up emphasis on the row below it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2400);
    addTearDown(tester.view.reset);
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final nowM = now.hour * 60 + now.minute;
    // The chain (done -> live -> upcoming) must fit before midnight. The
    // live window always hugs the real clock; the upcoming row only
    // exists while its whole 60-minute span fits, and late-evening runs
    // instead assert the day-end fallback (live hero, no next-up row).
    final window = liveWindowAt(nowM);
    final liveStart = window.liveStart;
    final liveEnd = window.liveEnd;
    final bool roomForNextUp = window.roomForNextUp;
    await tester.runAsync(() async {
      await db.replaceAll([]);
      final doneId = await db.insert(
        todayClass(
          'Data Structures',
          7 * 60,
          8 * 60,
          room: '301',
          professor: 'Prof. Reyes',
        ),
      );
      // Marked finished for the day: done rendering without relying on
      // the wall clock being past 08:00.
      await db.setClassStatus(
        ClassStatusEntry(
          classId: doneId,
          status: DayStatus.finished,
          startDate: dateKey(now),
          endDate: dateKey(now),
        ),
      );
      await db.insert(
        todayClass(
          'Advanced Mathematics',
          liveStart,
          liveEnd,
          room: '304',
          professor: 'Prof. Chen',
        ),
      );
      if (roomForNextUp) {
        await db.insert(
          todayClass(
            'Software Engineering',
            liveEnd + 40,
            liveEnd + 100,
            room: '302',
            professor: 'Prof. Turing',
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
    );
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final rows = tester
        .widgetList<ClassSegmentRow>(find.byType(ClassSegmentRow))
        .toList();

    // The queue: the finished class is gone from Today (its done state
    // lives on the weekly schedule), the live hero is promoted out of the
    // list, and the upcoming class queues beneath wearing "next up".
    //
    // The live hero is promoted out of the list: its subject appears only
    // in the hero card, and the rows below are the other classes in order.
    expect(find.text('Advanced Mathematics'), findsOneWidget);
    expect(find.text('Data Structures'), findsNothing);
    expect(rows, hasLength(roomForNextUp ? 1 : 0));

    expect(find.text('Next up'), findsNWidgets(roomForNextUp ? 1 : 0));
    if (roomForNextUp) {
      expect(rows.where((r) => r.isFocus), hasLength(1));
    }
  });

  testWidgets(
    'Today list merges consecutive classes into one segmented stack',
    (tester) async {
      final nowM = DateTime.now().hour * 60 + DateTime.now().minute;
      // All three stay upcoming so the first is the countdown hero: the
      // hero already IS the next-up class and no row below wears the tag.
      // Anchoring to `now` keeps the case clock-stable; the `fits` gate
      // mirrors the break-chip test for the late-night fallback.
      final fits = nowM + 170 <= 1440;
      final rows = await pumpToday(tester, fits
          ? [
              todayClass('Software Engineering', nowM + 10, nowM + 70),
              // Back to back: merges into the same stack, exactly like the Week tab.
              todayClass('Statistics', nowM + 70, nowM + 130),
              // A third class keeps two rows after the first is promoted to the hero.
              todayClass('Algorithms', nowM + 130, nowM + 170),
            ]
          : const []);

      if (fits) {
        expect(rows, hasLength(2));
        expect(find.byType(CampusBreakDivider), findsNothing);
        // The countdown hero already IS the next-up class, so no row below
        // wears the tag — the same language the list rows use belongs to
        // the hero alone.
        expect(rows.every((r) => !r.isFocus), isTrue);

        // The rows carry the stack corners: 16px group corners on the ends,
        // 2px meeting edges between them.
        expect(rows[0].radius, AppTheme.segmentRadiusOf(0, 2));
        expect(rows[1].radius, AppTheme.segmentRadiusOf(1, 2));
      }
    },
  );

  testWidgets('Today list splits stacks with a break chip on a real gap', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2400);
    addTearDown(tester.view.reset);
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final nowM = now.hour * 60 + now.minute;
    // The live class hugs the real clock (so it is always the promoted
    // hero) and the two remaining classes follow it, split by a fixed
    // 90-minute gap. The day-end runs (no room for both after the live
    // window) only assert the fallback: no chip, no rows below.
    final liveStart = nowM > 0 ? nowM - 1 : 0;
    final liveEnd = (liveStart + 40 > 1440 ? 1440 : liveStart + 40);
    final bool fits = liveEnd + 50 + 60 + 90 + 60 <= 1440;
    await tester.runAsync(() async {
      await db.replaceAll([]);
      await db.insert(
        todayClass('Algorithms', liveStart, liveEnd),
      );
      if (fits) {
        await db.insert(
          todayClass('Database Systems', liveEnd + 50, liveEnd + 110),
        );
        await db.insert(
          todayClass('Networks', liveEnd + 200, liveEnd + 260),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
    );
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final rows = tester
        .widgetList<ClassSegmentRow>(find.byType(ClassSegmentRow))
        .toList();

    expect(find.byType(CampusBreakDivider), findsNWidgets(fits ? 1 : 0));
    expect(find.text('1h 30m break'), findsNWidgets(fits ? 1 : 0));
    if (fits) {
      expect(rows, hasLength(2));
      // Both rows are single-row stacks: full 16px corners.
      expect(rows[0].radius, AppTheme.segmentRadiusOf(0, 1));
      expect(rows[1].radius, AppTheme.segmentRadiusOf(0, 1));
    }
  });

  testWidgets('Today segment rows show the room and professor icons', (
    tester,
  ) async {
    final nowM = DateTime.now().hour * 60 + DateTime.now().minute;
    // The first class hugs the real clock so it is always the promoted hero
    // (live, not done); the second stays beneath it so its row keeps the
    // pin/person icons. Mirrors the break-chip test's clock anchoring.
    final liveStart = nowM > 0 ? nowM - 1 : 0;
    final liveEnd = liveStart + 60;
    final fits = liveEnd + 30 + 60 <= 1440;
    if (!fits) return;
    await pumpToday(tester, [
      todayClass('Discrete Mathematics', liveStart, liveEnd),
      // A second class stays beneath the hero so its row keeps the icons.
      todayClass('Linear Algebra', liveEnd + 30, liveEnd + 90),
    ]);

    // The meta line keeps the pin/person icons the old cards had.
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });
}
