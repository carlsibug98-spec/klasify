import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klasify/models/class_item.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/campus_break_divider.dart';
import 'package:klasify/widgets/class_segment_row.dart';
import 'package:klasify/widgets/selected_day_header.dart';
import 'package:klasify/widgets/week_agenda_view.dart';
import 'package:klasify/widgets/weekday_tile.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'WeekdayTile renders the segmented day-bar treatment: caps, date, dots',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          WeekdayTile(
            name: 'Mon',
            date: DateTime(2026, 10, 19),
            selected: true,
            isToday: true,
            classCount: 5,
            onTap: () {},
          ),
        ),
      );

      // Displays the uppercase abbreviation and the date
      expect(find.text('MON'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);

      // Subtext below the date is removed per design simplification — the
      // workload reads as count dots instead
      expect(find.text('5 classes'), findsNothing);

      // Preserves accessibility via Semantics
      expect(find.bySemanticsLabel(RegExp(r'Mon.*5 classes')), findsOneWidget);
    },
  );

  testWidgets('WeekdayTile handles selection and tap correctly', (
    WidgetTester tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        WeekdayTile(
          name: 'Tue',
          date: DateTime(2026, 10, 20),
          selected: false,
          isToday: false,
          classCount: 1,
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.text('TUE'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('1 class'), findsNothing);

    await tester.tap(find.text('20'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets(
    'WeekdayTile states: selected fills, today rings, others carry the card edge',
    (WidgetTester tester) async {
      Future<Material> material(bool selected, bool isToday) async {
        await tester.pumpWidget(
          _host(
            WeekdayTile(
              name: 'Wed',
              date: DateTime(2026, 10, 21),
              selected: selected,
              isToday: isToday,
              classCount: 2,
              onTap: () {},
            ),
          ),
        );
        return tester.widget<Material>(
          find
              .descendant(
                of: find.byType(WeekdayTile),
                matching: find.byType(Material),
              )
              .first,
        );
      }

      final selected = await material(true, false);
      expect(selected.color, AppTheme.light().colorScheme.primary);

      final today = await material(false, true);
      expect(today.color, Colors.transparent);
      expect(today.shape, isA<RoundedRectangleBorder>());
      expect(
        (today.shape as RoundedRectangleBorder).side.width,
        1.5,
        reason: 'Today keeps its 1.5px ring when unselected',
      );

      final resting = await material(false, false);
      expect(
        resting.color,
        AppTheme.cardFillColorOf(AppTheme.light().colorScheme),
      );
      expect(
        (resting.shape as RoundedRectangleBorder).side,
        AppTheme.cardBorderSideOf(AppTheme.light().colorScheme),
      );
    },
  );

  testWidgets(
    'CampusBreakDivider renders clean break chip without border outline',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(const CampusBreakDivider(breakMinutes: 90)),
      );

      // Formatted break label
      expect(find.text('1h 30m break'), findsOneWidget);

      // Verify container decoration has no border outline
      final container = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius != null,
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.border, isNull, reason: 'No outline on break chip');
    },
  );

  testWidgets(
    'SelectedDayHeader renders the workload as quiet tracked caps',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: SelectedDayHeaderDelegate(
                  dayName: 'Wednesday',
                  formattedDate: 'October 21',
                  classCount: 3,
                  totalHours: 4.5,
                ),
              ),
            ],
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('Wednesday') &&
              w.text.toPlainText().contains('October 21'),
        ),
        findsOneWidget,
      );

      // The workload badge is gone; its quiet-caps replacement reads
      // uppercase with the group-label ink.
      expect(find.text('3 CLASSES · 4.5H'), findsOneWidget);
      final caps = tester.widget<Text>(find.text('3 CLASSES · 4.5H'));
      final style = caps.style!;
      expect(style.letterSpacing, 1.3);
      expect(
        style.color,
        AppTheme.groupLabelColorOf(AppTheme.light().colorScheme),
      );

      // No chip container behind the caps anymore
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(AppTheme.chipRadius),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('WeekAgendaView renders agenda with break dividers and classes', (
    WidgetTester tester,
  ) async {
    const class1 = ClassItem(
      id: 1,
      subject: 'Algorithms',
      room: '302',
      professor: 'Prof. Turing',
      day: 3, // Wednesday
      startMinutes: 9 * 60, // 9:00 AM
      endMinutes: 10 * 60 + 30, // 10:30 AM
    );
    const class2 = ClassItem(
      id: 2,
      subject: 'Database Systems',
      room: 'Lab 2',
      professor: 'Dr. Codd',
      day: 3, // Wednesday
      startMinutes: 12 * 60, // 12:00 PM
      endMinutes: 14 * 60, // 2:00 PM
    );

    final classesByDay = <int, List<ClassItem>>{
      for (var d = 1; d <= 7; d++) d: [],
    };
    classesByDay[3] = [class1, class2];

    await tester.pumpWidget(
      _host(
        WeekAgendaView(
          classesByDay: classesByDay,
          allClassesEmpty: false,
          today: 3,
          nowMinutes: 11 * 60,
          selectedDay: 3,
          dayDirection: 1,
          onSelectDay: (_) {},
          onTap: (_) {},
          onEdit: (_) {},
          onLongPress: (_) async => true,
          onAddClassForDay: (_) {},
        ),
      ),
    );

    // Classes render as segments with their start time in the left column
    expect(find.text('Algorithms'), findsOneWidget);
    expect(find.text('Database Systems'), findsOneWidget);
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('12:00 PM'), findsOneWidget);
    expect(find.byType(ClassSegmentRow), findsNWidgets(2));

    // Break divider between 10:30 and 12:00 (90 min)
    expect(find.byType(CampusBreakDivider), findsOneWidget);
    expect(find.text('1h 30m break'), findsOneWidget);

    // Grid toggle should NOT exist anywhere
    expect(find.text('Grid'), findsNothing);
  });

  testWidgets(
    'WeekAgendaView merges consecutive classes into one segmented stack',
    (WidgetTester tester) async {
    const class1 = ClassItem(
      id: 1,
      subject: 'Software Engineering',
      room: 'Lab 2',
      professor: 'Prof. Tan',
      day: 5,
      startMinutes: 13 * 60, // 1:00 PM
      endMinutes: 14 * 60 + 30, // 2:30 PM
    );
    const class2 = ClassItem(
      id: 2,
      subject: 'Statistics',
      room: '305',
      professor: 'Prof. Mendoza',
      day: 5,
      startMinutes: 14 * 60 + 30, // 2:30 PM — back to back
      endMinutes: 16 * 60, // 4:00 PM
    );

    final classesByDay = <int, List<ClassItem>>{
      for (var d = 1; d <= 7; d++) d: [],
    };
    classesByDay[5] = [class1, class2];

    await tester.pumpWidget(
      _host(
        WeekAgendaView(
          classesByDay: classesByDay,
          allClassesEmpty: false,
          today: 5,
          nowMinutes: 12 * 60,
          selectedDay: 5,
          dayDirection: 1,
          onSelectDay: (_) {},
          onTap: (_) {},
          onEdit: (_) {},
          onLongPress: (_) async => true,
          onAddClassForDay: (_) {},
        ),
      ),
    );

    // No break between back-to-back classes
    expect(find.byType(CampusBreakDivider), findsNothing);
    expect(find.byType(ClassSegmentRow), findsNWidgets(2));

    // The rows carry the stack corners: 16px group corners on the ends,
    // 2px meeting edges between them.
    final rows = tester
        .widgetList<ClassSegmentRow>(find.byType(ClassSegmentRow))
        .toList();
    expect(rows[0].radius, AppTheme.segmentRadiusOf(0, 2));
    expect(rows[1].radius, AppTheme.segmentRadiusOf(1, 2));
  });

  testWidgets(
    'WeekAgendaView shapes the segmented day bar: outer 16px, meeting edges 2px',
    (WidgetTester tester) async {
    final classesByDay = <int, List<ClassItem>>{
      for (var d = 1; d <= 7; d++) d: [],
    };

    await tester.pumpWidget(
      _host(
        WeekAgendaView(
          classesByDay: classesByDay,
          allClassesEmpty: true,
          today: 1,
          nowMinutes: 0,
          selectedDay: 1,
          dayDirection: 1,
          onSelectDay: (_) {},
          onEdit: (_) {},
          onLongPress: (_) async => true,
          onAddClassForDay: (_) {},
        ),
      ),
    );

    final tiles = tester
        .widgetList<WeekdayTile>(find.byType(WeekdayTile))
        .toList();
    expect(tiles, hasLength(7));
    expect(tiles.first.borderRadius, AppTheme.segmentRadiusHOf(0, 7));
    expect(tiles[3].borderRadius, AppTheme.segmentRadiusHOf(3, 7));
    expect(tiles.last.borderRadius, AppTheme.segmentRadiusHOf(6, 7));
  });

  test('segmentRadiusHOf mirrors the segment logic for horizontal bars', () {
    // Single segment: full group corners
    expect(
      AppTheme.segmentRadiusHOf(0, 1),
      BorderRadius.circular(AppTheme.cardRadius),
    );

    // First: outer (left) corners stay 16, meeting edge softens to 2
    expect(
      AppTheme.segmentRadiusHOf(0, 7),
      const BorderRadius.horizontal(
        left: Radius.circular(AppTheme.cardRadius),
        right: Radius.circular(AppTheme.segmentSoften),
      ),
    );

    // Middle: all meeting edges
    expect(
      AppTheme.segmentRadiusHOf(3, 7),
      BorderRadius.circular(AppTheme.segmentSoften),
    );

    // Last: meeting edge left, outer (right) corners 16
    expect(
      AppTheme.segmentRadiusHOf(6, 7),
      const BorderRadius.horizontal(
        left: Radius.circular(AppTheme.segmentSoften),
        right: Radius.circular(AppTheme.cardRadius),
      ),
    );
  });
}
