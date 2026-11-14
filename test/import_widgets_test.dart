import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/models/import_mode.dart';
import 'package:klasify/features/schedule_import/widgets/import_picker_card.dart';
import 'package:klasify/features/schedule_import/widgets/import_replacement_options.dart';
import 'package:klasify/features/schedule_import/widgets/import_success_card.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

ClassItem _saved({required int id, required String subject, required int day}) =>
    ClassItem(
      id: id,
      subject: subject,
      room: '101',
      professor: 'Prof. Cruz',
      day: day,
      startMinutes: 480,
      endMinutes: 540,
    );

void main() {
  testWidgets('picker card shows the file and forwards its three actions', (
    tester,
  ) async {
    _useLargeSurface(tester);
    var scanned = 0;
    var chose = 0;
    var manual = 0;

    await tester.pumpWidget(
      _host(
        ImportPickerCard(
          selectedFilePath: 'tmp/timetable.pdf',
          working: false,
          onScan: () => scanned++,
          onChooseFile: () => chose++,
          onManual: () => manual++,
        ),
      ),
    );

    expect(find.text('Selected file'), findsOneWidget);
    expect(find.text('timetable.pdf'), findsOneWidget);

    await tester.tap(find.text('Scan timetable'));
    await tester.tap(find.text('Choose another file'));
    await tester.tap(find.text('Enter classes manually'));

    expect(scanned, 1);
    expect(chose, 1);
    expect(manual, 1);
  });

  testWidgets('picker card hides the selected file and scan until a file', (
    tester,
  ) async {
    _useLargeSurface(tester);

    await tester.pumpWidget(
      _host(
        ImportPickerCard(
          selectedFilePath: null,
          working: false,
          onScan: () {},
          onChooseFile: () {},
          onManual: () {},
        ),
      ),
    );

    expect(find.text('Selected file'), findsNothing);
    expect(find.text('Scan timetable'), findsNothing);
    expect(find.text('Choose a timetable'), findsOneWidget);
  });

  testWidgets('success card shows the save copy and forwards both actions', (
    tester,
  ) async {
    _useLargeSurface(tester);
    var viewed = 0;
    var another = 0;

    await tester.pumpWidget(
      _host(
        ImportSuccessCard(
          message: 'Imported 2 classes successfully.',
          onViewSchedule: () => viewed++,
          onImportAnother: () => another++,
        ),
      ),
    );

    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('Imported 2 classes successfully.'), findsOneWidget);

    await tester.tap(find.text('View schedule'));
    await tester.tap(find.text('Import another'));

    expect(viewed, 1);
    expect(another, 1);
  });

  testWidgets('replacement options report mode changes and checked classes', (
    tester,
  ) async {
    _useLargeSurface(tester);
    ImportMode? changed;
    ClassItem? toggledItem;
    bool? toggledValue;

    await tester.pumpWidget(
      _host(
        ImportReplacementOptions(
          existing: [
            _saved(id: 1, subject: 'Mathematics', day: 1),
            _saved(id: 2, subject: 'Science', day: 2),
          ],
          mode: ImportMode.replaceSelected,
          selectedIds: {1},
          working: false,
          onModeChanged: (mode) => changed = mode,
          onToggle: (item, selected) {
            toggledItem = item;
            toggledValue = selected;
          },
        ),
      ),
    );

    expect(find.text('Import options'), findsOneWidget);
    expect(find.text('Add to schedule'), findsOneWidget);
    expect(find.text('Replace entire schedule'), findsOneWidget);
    expect(find.text('Choose classes to replace'), findsOneWidget);
    expect(
      find.text('1 saved class will be removed after confirmation.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Replace entire schedule'));
    expect(changed, ImportMode.replaceAll);

    final scienceTile = find.widgetWithText(CheckboxListTile, 'Science');
    await tester.tap(scienceTile);
    expect(toggledItem?.subject, 'Science');
    expect(toggledValue, isTrue);
  });
}
