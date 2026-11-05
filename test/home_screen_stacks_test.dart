import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/models/class_item.dart';
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
    // A live first class summons the "Next up" echo card under the hero,
    // which pushes the last stack past the default test viewport's initial
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

  testWidgets(
    'Today list merges consecutive classes into one segmented stack',
    (tester) async {
      final rows = await pumpToday(tester, [
        todayClass('Software Engineering', 13 * 60, 14 * 60 + 30),
        // Back to back: merges into the same stack, exactly like the Week tab.
        todayClass('Statistics', 14 * 60 + 30, 16 * 60),
      ]);

      expect(rows, hasLength(2));
      expect(find.byType(CampusBreakDivider), findsNothing);

      // The rows carry the stack corners: 16px group corners on the ends,
      // 2px meeting edges between them.
      expect(rows[0].radius, AppTheme.segmentRadiusOf(0, 2));
      expect(rows[1].radius, AppTheme.segmentRadiusOf(1, 2));
    },
  );

  testWidgets('Today list splits stacks with a break chip on a real gap', (
    tester,
  ) async {
    final rows = await pumpToday(tester, [
      todayClass('Algorithms', 9 * 60, 10 * 60 + 30),
      // 90 minutes after: its own stack with a coffee chip between.
      todayClass('Database Systems', 12 * 60, 14 * 60),
    ]);

    expect(rows, hasLength(2));
    expect(find.byType(CampusBreakDivider), findsOneWidget);
    expect(find.text('1h 30m break'), findsOneWidget);

    // Both rows are single-row stacks: full 16px corners.
    expect(rows[0].radius, AppTheme.segmentRadiusOf(0, 1));
    expect(rows[1].radius, AppTheme.segmentRadiusOf(0, 1));
  });

  testWidgets('Today segment rows show the room and professor icons', (
    tester,
  ) async {
    await pumpToday(tester, [
      todayClass('Discrete Mathematics', 10 * 60 + 15, 11 * 60 + 15),
    ]);

    // The meta line keeps the pin/person icons the old cards had.
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
  });
}
