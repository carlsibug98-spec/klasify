import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/database/database_helper.dart';
import 'package:klasify/features/schedule_import/import_schedule_screen.dart';
import 'package:klasify/features/schedule_import/services/schedule_ocr_service.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:klasify/routes/app_router.dart';
import 'package:klasify/theme/app_theme.dart';

/// Pins the weak-grid rescue on the import screen: a grid scan that locked
/// onto one or two weak lines (a notice board posing as a grid) must not
/// silence the flat-text cascade that parses the real schedule underneath.
/// The stronger ParseChain candidate wins the review screen; a grid result
/// that read clean text keeps the fast path and never runs the text stage.

class _WeakGridService extends ScheduleOcrService {
  _WeakGridService({this.cleanStats = false});

  /// When true the grid scan pretends the geometry mapped the page (its
  /// lines mostly landed in cells), so the screen must trust the grid and
  /// skip the text cascade entirely.
  final bool cleanStats;

  int scanImageCalls = 0;

  static const _bogusGridRow = ParsedTimetableRow(
    subject: 'Claim at the office.',
    room: 'Room to confirm',
    professor: '',
    day: 5,
    startMinutes: 21 * 60,
    endMinutes: 21 * 60 + 30,
    ocrConfidence: 0.5,
  );

  @override
  Future<List<ParsedTimetableRow>> scanGridImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
    GridScanStats? stats,
  }) async {
    if (cleanStats) {
      // A real grid: lines stay within a small multiple of mapped rows.
      stats
        ?..lineCount = 4
        ..alnumChars = 120
        ..meanLineConfidence = .99;
    } else {
      // A document the geometry locked onto: 73 lines read, 1 row mapped.
      stats
        ?..lineCount = 73
        ..alnumChars = 290
        ..meanLineConfidence = .93;
    }
    return const [_bogusGridRow];
  }

  @override
  Future<String> scanImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  }) async {
    scanImageCalls++;
    return '''
Monday
08:00 - 09:00 Math
Tuesday
09:00 - 10:30 English
Wednesday
10:00 - 11:00 Physics
''';
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
        'import_weak_grid_rescue_test_${DateTime.now().microsecondsSinceEpoch}.db';
    SharedPreferences.setMockInitialValues({});
    sampleFile = File(
      '${Directory.systemTemp.path}/import_weak_grid_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await sampleFile.writeAsBytes([0, 1, 2, 3]);
  });

  tearDownAll(() async {
    if (await sampleFile.exists()) {
      await sampleFile.delete();
    }
  });

  Future<void> pumpImport(WidgetTester tester, _WeakGridService service) async {
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
          ocrService: service,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('a weak 1-row grid is rescued by the text cascade', (
    tester,
  ) async {
    final service = _WeakGridService();
    await pumpImport(tester, service);

    // The text cascade ran and its three parsed classes won the review;
    // the bogus grid row is gone.
    expect(service.scanImageCalls, 1);
    expect(find.text('Review your timetable'), findsOneWidget);
    expect(find.text('Math'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Claim at the office.'), findsNothing);
  });

  testWidgets('a clean grid read keeps the fast path and skips the cascade', (
    tester,
  ) async {
    final service = _WeakGridService(cleanStats: true);
    await pumpImport(tester, service);

    // The grid row is trusted without spending a text pass.
    expect(service.scanImageCalls, 0);
    expect(find.text('Review your timetable'), findsOneWidget);
    expect(find.text('Claim at the office.'), findsOneWidget);
    expect(find.text('Math'), findsNothing);
  });
}
