import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/database_helper.dart';
import 'package:klasify/features/schedule_import/import_schedule_screen.dart';
import 'package:klasify/features/schedule_import/services/schedule_ocr_service.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:klasify/routes/app_router.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/swipe_actions.dart';

class _FakeScheduleOcrService extends ScheduleOcrService {
  @override
  Future<List<ParsedTimetableRow>> scanGridImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
    GridScanStats? stats,
  }) async {
    onProgress(.4, 'Detected timetable grid');
    // A clean, trusted grid read: the screen must not spend a text cascade
    // on it (this fake pins the strong-grid fast path).
    stats
      ?..lineCount = 20
      ..alnumChars = 400
      ..meanLineConfidence = .99;
    return const [
      ParsedTimetableRow(
        subject: 'Algorithms',
        room: 'Room to confirm',
        professor: 'Dr. Turing',
        day: 1,
        startMinutes: 600,
        endMinutes: 690,
        ocrConfidence: .5,
      ),
    ];
  }

  @override
  Future<String> scanImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress(.9, 'Recognized timetable text');
    return '';
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File sampleFile;

  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'import_review_edit_test_${DateTime.now().microsecondsSinceEpoch}.db';
    SharedPreferences.setMockInitialValues({});
    sampleFile = File(
      '${Directory.systemTemp.path}/import_review_edit_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await sampleFile.writeAsBytes([0, 1, 2, 3]);
  });

  tearDownAll(() async {
    if (await sampleFile.exists()) {
      await sampleFile.delete();
    }
  });

  testWidgets('tapping a reviewed class opens the original edit screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Open the database in a real-async window so the review screen's
    // microtask-backed query can complete during pump().
    await tester.runAsync(() async {
      await DatabaseHelper.instance.getAll();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: ImportScheduleScreen(
          initialFilePath: sampleFile.path,
          ocrService: _FakeScheduleOcrService(),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Review your timetable'), findsOneWidget);
    expect(find.text('Algorithms'), findsOneWidget);
    expect(find.text('Low OCR score · 50%'), findsOneWidget);
    expect(find.text('Room to confirm'), findsOneWidget);
    expect(find.text('A few details need review'), findsOneWidget);

    await tester.tap(find.text('Algorithms'));
    await tester.pumpAndSettle();

    expect(find.text('Edit class'), findsOneWidget);
    expect(find.byKey(const Key('edit_class_delete_button')), findsNothing);
    expect(find.text('Save changes'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('edit_class_subject_field')),
      'Advanced Algorithms',
    );
    await tester.enterText(
      find.byKey(const Key('edit_class_room_field')),
      'Lab 4',
    );
    await tester.tap(find.byKey(const Key('edit_class_save_button')));
    await tester.pumpAndSettle();

    expect(find.text('Review your timetable'), findsOneWidget);
    expect(find.text('Advanced Algorithms'), findsOneWidget);
    expect(find.text('Algorithms'), findsNothing);
    expect(find.text('Low OCR score · 50%'), findsNothing);
    expect(find.text('Room to confirm'), findsNothing);
    expect(find.text('A few details need review'), findsNothing);

    await tester.runAsync(() async {
      expect(await DatabaseHelper.instance.getAll(), isEmpty);
    });
  });

  group('draft row swipe', () {
    Future<Finder> pumpReview(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.runAsync(() async {
        await DatabaseHelper.instance.getAll();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: ImportScheduleScreen(
            initialFilePath: sampleFile.path,
            ocrService: _FakeScheduleOcrService(),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      return find.ancestor(
        of: find.text('Algorithms'),
        matching: find.byType(SwipeActions),
      );
    }

    testWidgets('a full swipe on a draft row removes it from the review', (
      tester,
    ) async {
      final row = await pumpReview(tester);
      expect(row, findsOneWidget);

      await tester.drag(row, const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('Algorithms'), findsNothing);
      expect(
        find.text('Removed "Algorithms" from this import review.'),
        findsOneWidget,
      );
    });

    testWidgets('the draft plane Edit opens the draft editor', (tester) async {
      final row = await pumpReview(tester);

      await tester.drag(row, const Offset(-100, 0));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit class'), findsOneWidget);
    });

    testWidgets('the trash button keeps removing drafts', (tester) async {
      // Fallback guard: the visible trash affordance survives the swipe
      // integration, like the class card's menu.
      final row = await pumpReview(tester);

      await tester.tap(find.byTooltip('Remove Algorithms from import'));
      await tester.pumpAndSettle();

      expect(find.text('Algorithms'), findsNothing);
      expect(row, findsNothing);
    });
  });

  group('import save reminder feedback', () {
    const warningCopy =
        'Classes saved, but reminders could not be updated. '
        'Check notification permission.';
    const disabledCopy =
        'Turn on class reminders in Settings to get notifications when '
        'the app is closed.';

    Future<void> pumpManualImportReview(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.runAsync(() async {
        DatabaseHelper.databaseName =
            'import_save_reminder_${DateTime.now().microsecondsSinceEpoch}.db';
        await DatabaseHelper.instance.resetForTesting();
        await DatabaseHelper.instance.getAll();
      });

      // No file and no OCR service: import this class through the real
      // manual-entry route the picker card opens.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          onGenerateRoute: AppRouter.onGenerateRoute,
          home: const ImportScheduleScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter classes manually'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit_class_subject_field')),
        'Algorithms',
      );
      await tester.enterText(
        find.byKey(const Key('edit_class_room_field')),
        'Lab 4',
      );
      await tester.tap(find.byKey(const Key('edit_class_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Review your timetable'), findsOneWidget);
      expect(find.text('Algorithms'), findsOneWidget);

      // Let the "added to review" toast retire so the post-save
      // notifications have the queue to themselves.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }

    Future<void> saveManualImport(WidgetTester tester) async {
      await tester.tap(find.text('Import 1 class'));
      // The review footer shows an indeterminate progress bar until the save
      // finishes, so poll for the success card instead of settling. Each poll
      // yields to the real event loop, where the reminder plugin reply lands.
      await tester.pump();
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Import complete').evaluate().isNotEmpty) break;
      }
      expect(find.text('Import complete'), findsOneWidget);
      await tester.pumpAndSettle();
    }

    /// Advances fake time through queued notifications until [text] is shown
    /// or the budget runs out.
    Future<void> pumpUntilText(
      WidgetTester tester,
      String text, {
      int maxSteps = 80,
      Duration step = const Duration(milliseconds: 250),
    }) async {
      for (var i = 0; i < maxSteps; i++) {
        if (find.text(text).evaluate().isNotEmpty) return;
        await tester.pump(step);
      }
    }

    testWidgets(
      'a real reminder failure keeps the manually added class and warns',
      (tester) async {
        // Premise: this host has no timezone plugin, so the real
        // ReminderService.sync() fails after the database write. Assert that
        // instead of injecting a fake service failure.
        final timezoneError = await tester.runAsync(() async {
          try {
            await FlutterTimezone.getLocalTimezone();
            return null;
          } on MissingPluginException catch (error) {
            return error;
          }
        });
        expect(
          timezoneError,
          isA<MissingPluginException>(),
          reason:
              'This warning test needs the host timezone plugin to be absent.',
        );

        SharedPreferences.setMockInitialValues({
          'class_reminders_enabled': true,
        });

        await pumpManualImportReview(tester);
        // The service logs the expected plugin failure; keep the run quiet.
        final originalDebugPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {};
        try {
          await saveManualImport(tester);
        } finally {
          debugPrint = originalDebugPrint;
        }

        // The class still landed, even though reminders could not refresh.
        final rows = await tester.runAsync(
          () => DatabaseHelper.instance.getAll(),
        );
        expect(rows, hasLength(1));
        expect(rows!.single.subject, 'Algorithms');
        expect(rows.single.room, 'Lab 4');

        expect(find.text('Import complete'), findsOneWidget);

        // The success notification is shown first; the warning is queued
        // behind it.
        await pumpUntilText(tester, warningCopy);
        await tester.pumpAndSettle();
        expect(find.text(warningCopy), findsOneWidget);

        await tester.runAsync(DatabaseHelper.instance.resetForTesting);
      },
    );

    testWidgets('reminders off explains how to turn them on after saving', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'class_reminders_enabled': false,
      });

      await pumpManualImportReview(tester);
      await saveManualImport(tester);

      expect(find.text('Import complete'), findsOneWidget);

      await pumpUntilText(tester, disabledCopy);
      await tester.pumpAndSettle();
      expect(find.text(disabledCopy), findsOneWidget);

      await tester.runAsync(DatabaseHelper.instance.resetForTesting);
    });
  });
}
