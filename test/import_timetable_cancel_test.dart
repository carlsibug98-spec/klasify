import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/features/schedule_import/import_schedule_screen.dart';
import 'package:klasify/features/schedule_import/services/schedule_ocr_service.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:klasify/features/schedule_import/widgets/import_review_widgets.dart';
import 'package:klasify/theme/app_theme.dart';

class TestScheduleOcrService extends ScheduleOcrService {
  TestScheduleOcrService({this.onScanGridImage});

  final Future<List<ParsedTimetableRow>> Function({
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  })?
  onScanGridImage;

  bool cancelWasCalled = false;

  @override
  void cancel() {
    super.cancel();
    cancelWasCalled = true;
  }

  @override
  Future<List<ParsedTimetableRow>> scanGridImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
    GridScanStats? stats,
  }) async {
    if (onScanGridImage != null) {
      return onScanGridImage!(onProgress: onProgress, isCancelled: isCancelled);
    }
    return super.scanGridImage(
      path,
      onProgress: onProgress,
      isCancelled: isCancelled,
      stats: stats,
    );
  }

  @override
  Future<void> dispose() async {
    // No-op for tests
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File sampleTimetableFile;

  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    sampleTimetableFile = File(
      '${Directory.systemTemp.path}/test_timetable_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await sampleTimetableFile.writeAsBytes([0, 1, 2, 3]);
  });

  tearDownAll(() async {
    if (await sampleTimetableFile.exists()) {
      await sampleTimetableFile.delete();
    }
  });

  Widget host({
    required Widget child,
    TargetPlatform platform = TargetPlatform.android,
  }) {
    return MaterialApp(
      theme: AppTheme.dark().copyWith(platform: platform),
      home: Scaffold(body: child),
    );
  }

  group('Cancel confirmation sheet', () {
    testWidgets(
      'Android modal bottom sheet shows and "Keep Scanning" keeps scan running',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          host(
            platform: TargetPlatform.android,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCancelScanConfirmation(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // Android bottom sheet contents
        expect(find.text('Stop this scan?'), findsOneWidget);
        expect(
          find.text(
            'Progress so far will be discarded. Your file stays selected, so you can scan again any time.',
          ),
          findsOneWidget,
        );
        expect(find.text('No classes will be added'), findsOneWidget);
        expect(
          find.text('Scanning again starts from the beginning'),
          findsOneWidget,
        );
        expect(find.text('Stop Scan'), findsOneWidget);
        expect(find.text('Keep Scanning'), findsOneWidget);

        // Keep scanning should dismiss and return false
        await tester.tap(find.text('Keep Scanning'));
        await tester.pumpAndSettle();

        expect(find.text('Stop this scan?'), findsNothing);
        expect(result, isFalse);
      },
    );

    testWidgets(
      'Android modal bottom sheet confirms cancellation on "Stop Scan"',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          host(
            platform: TargetPlatform.android,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCancelScanConfirmation(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Stop Scan'));
        await tester.pumpAndSettle();

        expect(find.text('Stop this scan?'), findsNothing);
        expect(result, isTrue);
      },
    );

    testWidgets(
      'iOS CupertinoActionSheet shows and "Keep Scanning" keeps scan running',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          host(
            platform: TargetPlatform.iOS,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCancelScanConfirmation(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoActionSheet), findsOneWidget);
        expect(find.text('Stop this scan?'), findsOneWidget);
        expect(
          find.text(
            'Progress so far will be discarded. Your file stays selected, so you can scan again any time.',
          ),
          findsOneWidget,
        );
        expect(find.text('Stop Scan'), findsOneWidget);
        expect(find.text('Keep Scanning'), findsOneWidget);

        await tester.tap(find.text('Keep Scanning'));
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoActionSheet), findsNothing);
        expect(result, isFalse);
      },
    );

    testWidgets(
      'iOS CupertinoActionSheet confirms cancellation on "Stop Scan"',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          host(
            platform: TargetPlatform.iOS,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCancelScanConfirmation(context);
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Stop Scan'));
        await tester.pumpAndSettle();

        expect(find.byType(CupertinoActionSheet), findsNothing);
        expect(result, isTrue);
      },
    );
  });

  group('Cancelling state widget layout and accessibility', () {
    testWidgets(
      'cancelling state shows activity indicator, step tags, and hides progress bar and cancel button',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            child: const ImportScanProgress(
              stage: ImportScanStage.detectingGrid,
              progress: 0.25,
              detail: 'Checking timetable layout',
              filePath: 'my_schedule.png',
              isCancelling: true,
            ),
          ),
        );

        // Selected file card is kept at the top
        expect(find.text('Selected file'), findsOneWidget);
        expect(find.text('my_schedule.png'), findsOneWidget);

        // Activity indicator and title
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Cancelling scan',
          ),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Cancelling scan'), findsOneWidget);
        expect(
          find.text(
            'Stopping after the current step. No classes will be added.',
          ),
          findsOneWidget,
        );

        // Step list tags
        expect(find.text('Preparing file'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);

        expect(find.text('Detecting grid'), findsOneWidget);
        expect(find.text('Finishing'), findsOneWidget);

        expect(find.text('Reading text'), findsOneWidget);
        expect(find.text('Organizing results'), findsOneWidget);
        expect(find.text('Skipped'), findsNWidgets(2));

        // Progress bar and Cancel scan button are hidden while cancelling
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Cancel scan'), findsNothing);

        handle.dispose();
      },
    );
  });

  group('Full cancel flow in ImportScheduleScreen', () {
    testWidgets(
      'confirmation shows, cancelling state shows until OCR completes, snackbar appears and screen returns to idle',
      (tester) async {
        final ocrStarted = Completer<void>();
        final ocrStopWait = Completer<List<ParsedTimetableRow>>();

        final testOcr = TestScheduleOcrService(
          onScanGridImage: ({required onProgress, isCancelled}) async {
            ocrStarted.complete();
            onProgress(0.25, 'Detecting grid');
            return ocrStopWait.future;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: ImportScheduleScreen(
              initialFilePath: sampleTimetableFile.path,
              ocrService: testOcr,
            ),
          ),
        );

        // First pump renders, second pump executes postFrameCallback
        await tester.pump();
        await tester.pump();
        expect(ocrStarted.isCompleted, isTrue);

        // 1. We are scanning; tap "Cancel scan"
        expect(find.text('Cancel scan'), findsOneWidget);
        await tester.tap(find.text('Cancel scan'));
        await tester.pumpAndSettle();

        // Confirmation sheet shows
        expect(find.text('Stop this scan?'), findsOneWidget);

        // Tapping Keep Scanning dismisses and keeps scanning
        await tester.tap(find.text('Keep Scanning'));
        await tester.pumpAndSettle();
        expect(find.text('Stop this scan?'), findsNothing);
        expect(testOcr.cancelWasCalled, isFalse);
        expect(find.text('Cancel scan'), findsOneWidget);

        // Tap Cancel scan again, and confirm Stop Scan
        await tester.tap(find.text('Cancel scan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stop Scan'));
        await tester.pump();

        // 2. OCR service cancel() was called
        expect(testOcr.cancelWasCalled, isTrue);
        expect(testOcr.isCancelled, isTrue);

        // 3. Cancelling state is visible while OCR task is running
        expect(find.text('Cancelling scan'), findsOneWidget);
        expect(
          find.text(
            'Stopping after the current step. No classes will be added.',
          ),
          findsOneWidget,
        );
        expect(find.text('Selected file'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('Finishing'), findsOneWidget);
        expect(find.text('Skipped'), findsNWidgets(2));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('Cancel scan'), findsNothing);

        // Complete the OCR task to signal that OCR work has actually stopped
        ocrStopWait.complete([]);
        await tester.pump();
        await tester.pumpAndSettle();

        // 4. Cancelling state is removed
        expect(find.text('Cancelling scan'), findsNothing);

        // 5. Result snackbar is displayed
        expect(
          find.text('Scan cancelled. No classes were added.'),
          findsOneWidget,
        );

        // 6. Screen has returned to idle state with selected file preserved
        expect(find.text('Bring in your timetable'), findsOneWidget);
        expect(find.text('Scan timetable'), findsOneWidget);

        // 7. Verify snackbar dismisses after 4 seconds
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(
          find.text('Scan cancelled. No classes were added.'),
          findsNothing,
        );
      },
    );
  });
}
