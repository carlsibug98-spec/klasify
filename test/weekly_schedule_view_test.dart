import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klasify/models/class_item.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/campus_break_divider.dart';
import 'package:klasify/widgets/selected_day_header.dart';
import 'package:klasify/widgets/week_agenda_view.dart';
import 'package:klasify/widgets/weekday_tile.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'WeekdayTile displays clean day name and date circle without cluttered subtext',
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

      // Displays day abbreviation and date badge cleanly
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);

      // Subtext below the date is removed per design simplification
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

    expect(find.text('Tue'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('1 class'), findsNothing);

    await tester.tap(find.text('20'));
    await tester.pump();
    expect(tapped, isTrue);
  });

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
    'SelectedDayHeaderDelegate renders workload badge without border outline',
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
      expect(find.text('3 classes · 4.5h'), findsOneWidget);

      // Find the badge container and ensure no outline
      final badgeContainer = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(12),
        ),
      );
      final decoration = badgeContainer.decoration as BoxDecoration;
      expect(decoration.border, isNull, reason: 'No outline on workload badge');
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

    // Classes should be present
    expect(find.text('Algorithms'), findsOneWidget);
    expect(find.text('Database Systems'), findsOneWidget);

    // Break divider between 10:30 and 12:00 (90 min)
    expect(find.byType(CampusBreakDivider), findsOneWidget);
    expect(find.text('1h 30m break'), findsOneWidget);

    // Grid toggle should NOT exist anywhere
    expect(find.text('Grid'), findsNothing);
  });
}
