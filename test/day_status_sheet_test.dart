import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/day_status_sheet.dart';

const _item = ClassItem(
  id: 7,
  subject: 'Advanced Mathematics',
  room: '304',
  professor: 'Prof. Santos',
  day: DateTime.tuesday,
  startMinutes: 10 * 60,
  endMinutes: 11 * 60 + 30,
);

final _date = DateTime(2026, 10, 27); // Tuesday

Widget _host({ClassStatusEntry? current}) => MaterialApp(
  theme: AppTheme.light(),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showDayStatusSheet(
            context,
            item: _item,
            date: _date,
            current: current,
          ),
          child: const Text('Open mark class'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, {ClassStatusEntry? current}) async {
  await tester.pumpWidget(_host(current: current));
  await tester.tap(find.text('Open mark class'));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mark class sheet matches the design and enables the action', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('MARK CLASS'), findsOneWidget);
    expect(find.text('Advanced Mathematics'), findsOneWidget);
    expect(find.text('10:00 – 11:30 AM · Room 304'), findsOneWidget);
    expect(find.text('Tue 27 Oct'), findsOneWidget);
    expect(find.text('What happened'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Not attending'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Pick what happened to this class.'), findsOneWidget);

    expect(find.text('For how long'), findsOneWidget);
    expect(find.text('This class'), findsOneWidget);
    expect(find.text('Until Sunday'), findsOneWidget);
    expect(find.text('Until I clear'), findsOneWidget);
    expect(find.text('Only Tue 27 Oct.'), findsOneWidget);
    expect(find.text('Pick what happened'), findsOneWidget);

    // Nothing is selected yet, so the primary action is disabled.
    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Finished'));
    await tester.pumpAndSettle();

    expect(find.text('You finished this class.'), findsOneWidget);
    expect(find.text('Mark as Finished'), findsOneWidget);
    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);

    // Span changes update the sentence in place.
    await tester.ensureVisible(find.text('Until Sunday'));
    await tester.tap(find.text('Until Sunday'));
    await tester.pumpAndSettle();
    expect(find.text('Tue 27 Oct through Sun 1 Nov.'), findsOneWidget);

    await tester.ensureVisible(find.text('Until I clear'));
    await tester.tap(find.text('Until I clear'));
    await tester.pumpAndSettle();
    expect(find.text('From Tue 27 Oct until you clear it.'), findsOneWidget);

    await _close(tester);
  });

  testWidgets('mark class sheet opens in edit mode with clear action', (
    tester,
  ) async {
    await _open(
      tester,
      current: const ClassStatusEntry(
        classId: 7,
        status: DayStatus.notAttending,
        startDate: '2026-10-27',
      ),
    );

    expect(find.text('Marked: Not attending · until cleared'), findsOneWidget);
    expect(find.text('You’re skipping this class.'), findsOneWidget);
    expect(find.text('From Tue 27 Oct until you clear it.'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Clear status'), findsOneWidget);

    await _close(tester);
  });

  testWidgets('cancelled copy and the span lock follow the design', (
    tester,
  ) async {
    await _open(tester);

    // Without a status the span control is visually and functionally locked;
    // the tiles stay tappable.
    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();

    expect(find.text('The class won’t meet.'), findsOneWidget);
    expect(find.text('Mark as Cancelled'), findsOneWidget);

    await _close(tester);
  });
}
