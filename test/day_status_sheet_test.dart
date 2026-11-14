import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/services/widget_data_actions.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/day_status_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _draft = ClassItem(
  subject: 'Advanced Mathematics',
  room: '304',
  professor: 'Prof. Santos',
  day: DateTime.tuesday,
  startMinutes: 10 * 60,
  endMinutes: 11 * 60 + 30,
);

final _date = DateTime(2026, 10, 27); // Tuesday

late ClassItem _item;
late int _classId;

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
            actions: DayStatusActions.database,
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

/// Taps a button that may sit below the fold on the test surface.
Future<void> _tapVisible(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    // Reminder sync short-circuits, so the save path is deterministic.
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});
    DatabaseHelper.databaseName =
        'day_status_sheet_${DateTime.now().microsecondsSinceEpoch}.db';
    await DatabaseHelper.instance.resetForTesting();
    _classId = await DatabaseHelper.instance.insert(_draft);
    _item = (await DatabaseHelper.instance.getAll()).single;
  });

  tearDown(() async {
    await DatabaseHelper.instance.resetForTesting();
  });

  testWidgets('mark class sheet matches the design and saves a real mark', (
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
    expect(find.text('Until date'), findsOneWidget);
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
    await tester.ensureVisible(find.text('Until date'));
    await tester.tap(find.text('Until date'));
    await tester.pumpAndSettle();
    expect(find.text('Tue 27 Oct through Tue 3 Nov.'), findsOneWidget);

    await tester.ensureVisible(find.text('Until I clear'));
    await tester.tap(find.text('Until I clear'));
    await tester.pumpAndSettle();
    expect(find.text('From Tue 27 Oct until you clear it.'), findsOneWidget);

    // Save through the real database-backed action bundle.
    await _tapVisible(tester, 'Mark as Finished');

    final marks = await tester.runAsync(
      () => DatabaseHelper.instance.statusesForClass(_classId),
    );
    expect(marks, isNotNull);
    expect(marks!, hasLength(1));
    expect(marks.single.classId, _classId);
    expect(marks.single.status, DayStatus.finished);
    expect(marks.single.startDate, '2026-10-27');
    expect(marks.single.endDate, isNull, reason: 'Until I clear is open-ended');
  });

  testWidgets('mark class sheet edits and clears a real saved mark', (
    tester,
  ) async {
    await DatabaseHelper.instance.setClassStatus(
      ClassStatusEntry(
        classId: _classId,
        status: DayStatus.notAttending,
        startDate: '2026-10-27',
      ),
    );
    final current = (await DatabaseHelper.instance.statusesForClass(
      _classId,
    )).single;

    await _open(tester, current: current);

    expect(find.text('Marked: Not attending · until cleared'), findsOneWidget);
    expect(find.text('You’re skipping this class.'), findsOneWidget);
    expect(find.text('From Tue 27 Oct until you clear it.'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Clear status'), findsOneWidget);

    await _tapVisible(tester, 'Clear status');

    // Clearing one day of an open-ended mark keeps the later days marked:
    // the remainder starts the next day. This also proves the real database
    // write ran rather than the seeded row merely still being present.
    final marks = await tester.runAsync(
      () => DatabaseHelper.instance.statusesForClass(_classId),
    );
    expect(marks, isNotNull);
    expect(marks!, hasLength(1));
    expect(marks.single.status, DayStatus.notAttending);
    expect(marks.single.startDate, '2026-10-28');
    expect(marks.single.endDate, isNull);
  });

  testWidgets('cancelled copy and the saved status follow the design', (
    tester,
  ) async {
    await _open(tester);

    // Without a status the span control is visually and functionally locked;
    // the tiles stay tappable.
    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();

    expect(find.text('The class won’t meet.'), findsOneWidget);
    expect(find.text('Mark as Cancelled'), findsOneWidget);

    await _tapVisible(tester, 'Mark as Cancelled');

    final marks = await tester.runAsync(
      () => DatabaseHelper.instance.statusesForClass(_classId),
    );
    expect(marks, isNotNull);
    expect(marks!, hasLength(1));
    expect(marks.single.status, DayStatus.cancelled);
    expect(marks.single.startDate, '2026-10-27');
    expect(marks.single.endDate, '2026-10-27');
  });
}
