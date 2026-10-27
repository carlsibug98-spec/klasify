import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/database/database_helper.dart';
import 'package:klasify/features/schedule_import/import_schedule_screen.dart';
import 'package:klasify/features/schedule_import/services/schedule_ocr_service.dart';
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
  }) async {
    onProgress(.4, 'Detected timetable grid');
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
}
