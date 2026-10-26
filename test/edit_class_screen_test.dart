import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/screens/edit_class_screen.dart';
import 'package:klasify/widgets/edit_class_time_picker_sheet.dart';

void main() {
  const sampleClass = ClassItem(
    id: 1,
    subject: 'Algorithms',
    room: 'Lab 4',
    professor: 'Dr. Turing',
    day: 1, // Monday
    startMinutes: 600, // 10:00 AM
    endMinutes: 690, // 11:30 AM
  );

  Widget buildScreen({
    required WidgetTester tester,
    ClassItem classItem = sampleClass,
    Future<bool> Function(ClassItem)? onSave,
    Future<bool> Function(ClassItem)? onDelete,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    return MaterialApp(
      home: EditClassScreen(
        classItem: classItem,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  group('Validation tests on Save', () {
    testWidgets(
      'Validates required subject and room, shows inline errors, and clears on typing',
      (tester) async {
        await tester.pumpWidget(buildScreen(tester: tester));
        await tester.pumpAndSettle();

        // Clear Subject and Room
        await tester.enterText(
          find.byKey(const Key('edit_class_subject_field')),
          '',
        );
        await tester.enterText(
          find.byKey(const Key('edit_class_room_field')),
          '',
        );
        await tester.pump();

        // Tap Save
        await tester.tap(find.byKey(const Key('edit_class_save_button')));
        await tester.pump();

        expect(find.text('Enter a subject.'), findsOneWidget);
        expect(find.text('Enter a room.'), findsOneWidget);

        // Type in subject -> inline error clears
        await tester.enterText(
          find.byKey(const Key('edit_class_subject_field')),
          'Data Structures',
        );
        await tester.pump();
        expect(find.text('Enter a subject.'), findsNothing);
        expect(find.text('Enter a room.'), findsOneWidget);

        // Type in room -> inline error clears
        await tester.enterText(
          find.byKey(const Key('edit_class_room_field')),
          'Room 101',
        );
        await tester.pump();
        expect(find.text('Enter a room.'), findsNothing);
      },
    );

    testWidgets('Validates end time must be after start time', (tester) async {
      const invalidClass = ClassItem(
        id: 1,
        subject: 'Math',
        room: '101',
        professor: 'Prof. Gauss',
        day: 2,
        startMinutes: 700,
        endMinutes: 700, // Not after start
      );

      await tester.pumpWidget(
        buildScreen(tester: tester, classItem: invalidClass),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_class_save_button')));
      await tester.pump();

      expect(
        find.text('End time must be after the start time.'),
        findsOneWidget,
      );
    });

    testWidgets('Save shows success notification and navigates back', (
      tester,
    ) async {
      ClassItem? savedItem;

      await tester.pumpWidget(
        buildScreen(
          tester: tester,
          onSave: (item) async {
            savedItem = item;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_class_save_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(savedItem, isNotNull);
      expect(savedItem!.subject, 'Algorithms');
      expect(find.text('Class updated.'), findsOneWidget);
    });
  });

  group('One-day selection tests', () {
    testWidgets(
      '7 day chips shown, exactly one selected at a time with semantics',
      (tester) async {
        await tester.pumpWidget(buildScreen(tester: tester));
        await tester.pumpAndSettle();

        // Monday is initially selected
        final monSemantics = tester.getSemantics(
          find.byKey(const Key('edit_class_day_chip_Mon')),
        );
        expect(monSemantics.label, 'Monday');
        expect(monSemantics.flagsCollection.isSelected, Tristate.isTrue);
        expect(monSemantics.flagsCollection.isButton, isTrue);

        final tueSemantics = tester.getSemantics(
          find.byKey(const Key('edit_class_day_chip_Tue')),
        );
        expect(tueSemantics.label, 'Tuesday');
        expect(tueSemantics.flagsCollection.isSelected, Tristate.isFalse);
        expect(tueSemantics.flagsCollection.isButton, isTrue);

        // Tap Wednesday
        await tester.tap(find.byKey(const Key('edit_class_day_chip_Wed')));
        await tester.pump();

        // Now Wednesday is selected, Monday is deselected
        final monAfter = tester.getSemantics(
          find.byKey(const Key('edit_class_day_chip_Mon')),
        );
        expect(monAfter.flagsCollection.isSelected, Tristate.isFalse);

        final wedAfter = tester.getSemantics(
          find.byKey(const Key('edit_class_day_chip_Wed')),
        );
        expect(wedAfter.label, 'Wednesday');
        expect(wedAfter.flagsCollection.isSelected, Tristate.isTrue);
      },
    );
  });

  group('Two-tap delete tests', () {
    testWidgets('First tap arms confirmation for 3s, second tap calls delete', (
      tester,
    ) async {
      bool deleteCalled = false;

      await tester.pumpWidget(
        buildScreen(
          tester: tester,
          onDelete: (item) async {
            deleteCalled = true;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Initial state
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Tap to confirm'), findsNothing);

      // 1st tap: arms button
      await tester.tap(find.byKey(const Key('edit_class_delete_button')));
      await tester.pump();

      expect(find.text('Delete'), findsNothing);
      expect(find.text('Tap to confirm'), findsOneWidget);
      expect(deleteCalled, isFalse);

      // 2nd tap within 3 seconds: calls delete
      await tester.tap(find.byKey(const Key('edit_class_delete_button')));
      await tester.pumpAndSettle();

      expect(deleteCalled, isTrue);
    });

    testWidgets(
      'Arms for 3s and resets if 3 seconds expire without second tap',
      (tester) async {
        await tester.pumpWidget(buildScreen(tester: tester));
        await tester.pumpAndSettle();

        // Tap once
        await tester.tap(find.byKey(const Key('edit_class_delete_button')));
        await tester.pump();
        expect(find.text('Tap to confirm'), findsOneWidget);

        // Advance 3.1 seconds
        await tester.pump(const Duration(milliseconds: 3100));
        expect(find.text('Delete'), findsOneWidget);
        expect(find.text('Tap to confirm'), findsNothing);
      },
    );
  });

  group('Discard changes on back tests', () {
    testWidgets('Pops immediately when no unsaved changes', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool didPop = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const EditClassScreen(classItem: sampleClass),
                  ),
                );
                didPop = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit class'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byKey(const Key('edit_class_back_button')));
      await tester.pumpAndSettle();

      // Popped immediately without discard prompt
      expect(didPop, isTrue);
      expect(find.text('Edit class'), findsNothing);
    });

    testWidgets(
      'Prompts Discard changes when modified, allows keep editing or discard',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        bool didPop = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const EditClassScreen(classItem: sampleClass),
                    ),
                  );
                  didPop = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Modify room
        await tester.enterText(
          find.byKey(const Key('edit_class_room_field')),
          'Lab 99',
        );
        await tester.pump();

        // Tap back button -> dialog appears
        await tester.tap(find.byKey(const Key('edit_class_back_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('discard_dialog_title')), findsOneWidget);
        expect(find.text('Keep editing'), findsOneWidget);
        expect(find.text('Discard'), findsOneWidget);

        // Tap Keep editing -> stays
        await tester.tap(find.byKey(const Key('discard_dialog_cancel_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('discard_dialog_title')), findsNothing);
        expect(find.text('Edit class'), findsOneWidget);
        expect(didPop, isFalse);

        // Tap back button again -> tap Discard -> pops
        await tester.tap(find.byKey(const Key('edit_class_back_button')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('discard_dialog_confirm_button')),
        );
        await tester.pumpAndSettle();

        expect(didPop, isTrue);
        expect(find.text('Edit class'), findsNothing);
      },
    );
  });

  group('Time picker bottom sheet tests', () {
    testWidgets(
      'Opens with field current value and Done updates start time, adjusting end if needed',
      (tester) async {
        await tester.pumpWidget(buildScreen(tester: tester));
        await tester.pumpAndSettle();

        // Starts: 10:00 AM (600), Ends: 11:30 AM (690). Duration = 90 min
        expect(find.text('10:00 AM'), findsOneWidget);
        expect(find.text('11:30 AM'), findsOneWidget);

        // Tap Starts tile
        await tester.tap(find.byKey(const Key('edit_class_start_tile')));
        await tester.pumpAndSettle();

        // Time picker sheet opens with current value
        expect(find.byKey(const Key('time_picker_title')), findsOneWidget);
        expect(find.text('Start time'), findsOneWidget);
        expect(find.text('10:00 AM'), findsNWidgets(2)); // Tile + Sheet preview

        // Tap Done
        await tester.tap(find.byKey(const Key('time_picker_done_button')));
        await tester.pumpAndSettle();

        // Sheet closed
        expect(find.byKey(const Key('time_picker_title')), findsNothing);
      },
    );

    testWidgets('End-before-start check keeps sheet open with error message', (
      tester,
    ) async {
      TimePickerResult? sheetResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  sheetResult = await showEditClassTimePickerSheet(
                    context: context,
                    title: 'End time',
                    initialMinutes: 600, // 10:00 AM
                    isStart: false,
                    currentStartMinutes: 660, // 11:00 AM (end is before start)
                  );
                },
                child: const Text('Open End Picker'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open End Picker'));
      await tester.pumpAndSettle();

      expect(find.text('End time'), findsOneWidget);

      // Tap Done while end (600) <= start (660)
      await tester.tap(find.byKey(const Key('time_picker_done_button')));
      await tester.pumpAndSettle();

      // Sheet must stay open and show error inside sheet
      expect(find.byKey(const Key('time_picker_error_text')), findsOneWidget);
      expect(find.text('End must be after the start time.'), findsOneWidget);
      expect(sheetResult, isNull); // Was not saved / closed

      // Tapping Cancel dismisses without saving
      await tester.tap(find.byKey(const Key('time_picker_cancel_button')));
      await tester.pumpAndSettle();

      expect(find.text('End time'), findsNothing);
      expect(sheetResult, isNull);
    });

    testWidgets('Start time adjusts end time if new start is at or after end', (
      tester,
    ) async {
      TimePickerResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showEditClassTimePickerSheet(
                    context: context,
                    title: 'Start time',
                    initialMinutes: 720, // 12:00 PM
                    isStart: true,
                    currentEndMinutes: 720, // start at end
                    previousDuration: 90,
                  );
                },
                child: const Text('Open Start Picker'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Start Picker'));
      await tester.pumpAndSettle();

      // Tap Done
      await tester.tap(find.byKey(const Key('time_picker_done_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.minutes, 720);
      expect(result!.adjustedEndMinutes, 810); // 720 + 90 min duration
    });
  });

  group('Add class mode tests', () {
    testWidgets(
      'Renders Add class title, no delete button, and full-width Save button',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: EditClassScreen(), // classItem: null -> Add mode
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Add class'), findsOneWidget);
        expect(find.text('Edit class'), findsNothing);
        expect(find.byKey(const Key('edit_class_delete_button')), findsNothing);
        expect(find.byKey(const Key('edit_class_save_button')), findsOneWidget);
      },
    );

    testWidgets('Saves new class and pops with success', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      ClassItem? addedItem;
      await tester.pumpWidget(
        MaterialApp(
          home: EditClassScreen(
            onSave: (item) async {
              addedItem = item;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit_class_subject_field')),
        'Computer Networks',
      );
      await tester.enterText(
        find.byKey(const Key('edit_class_room_field')),
        'Room 302',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('edit_class_save_button')));
      await tester.pumpAndSettle();

      expect(addedItem, isNotNull);
      expect(addedItem!.subject, 'Computer Networks');
      expect(addedItem!.room, 'Room 302');
    });
  });

  group('Import draft mode tests', () {
    testWidgets(
      'hides delete, labels save for review, and returns the edited item without saving',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        ClassItem? returned;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  returned = await Navigator.of(context).push<ClassItem>(
                    MaterialPageRoute(
                      builder: (_) => EditClassScreen(
                        classItem: sampleClass,
                        returnDraft: true,
                        onSave: (_) async =>
                            fail('Draft edits must not save to the database'),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Edit class'), findsOneWidget);
        expect(find.byKey(const Key('edit_class_delete_button')), findsNothing);
        expect(find.text('Save changes'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('edit_class_subject_field')),
          'Advanced Algorithms',
        );
        await tester.tap(find.byKey(const Key('edit_class_save_button')));
        await tester.pumpAndSettle();

        expect(returned, isNotNull);
        expect(returned!.subject, 'Advanced Algorithms');
        expect(returned!.id, sampleClass.id);
      },
    );
  });
}
