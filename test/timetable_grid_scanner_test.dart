import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import 'package:klasify/features/schedule_import/services/ocr_image_preprocessor.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

class _NoPreprocessing extends OcrImagePreprocessor {
  @override
  Future<PreparedOcrImage?> prepare(
    String path, {
    int quarterTurns = 0,
    bool adaptiveThreshold = false,
    bool invertDarkBackground = false,
    bool deskew = true,
    bool sharpen = false,
    int upscaleTarget = 1800,
    double rotateDegrees = 0,
    bool crisp = false,
    bool rotateBeforeEnhance = false,
    bool flattenIllumination = false,
    bool dewarp = false,
  }) async => null;
}

OcrResult _region(String text, int left, int top, int right, int bottom) =>
    OcrResult(
      text: text,
      confidence: .99,
      points: [
        OcrPoint(x: left, y: top),
        OcrPoint(x: right, y: top),
        OcrPoint(x: right, y: bottom),
        OcrPoint(x: left, y: bottom),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('maps afternoon grid cells to their weekday and PM times', () async {
    final directory = await Directory.systemTemp.createTemp('klasify_grid_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _pathProvider,
          (call) async => directory.path,
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, null);
      await directory.delete(recursive: true);
    });

    final file = File(
      '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}timetable_grid_afternoon.png',
    );
    final regions = [
      _region('Monday', 680, 80, 720, 110),
      _region('Tuesday', 1280, 80, 1320, 110),
      _region('1:00 PM', 80, 590, 150, 610),
      _region('2:00 PM', 80, 790, 150, 810),
      _region('3:00 PM', 80, 990, 150, 1010),
      _region('Data Structures', 600, 550, 800, 580),
      _region('Chemistry', 1200, 750, 1400, 780),
    ];
    final scanner = TimetableGridScanner(
      preprocessor: _NoPreprocessing(),
      recognize: (path) async => path == file.path
          ? OcrRunResult(
              results: regions,
              detectionTimeMs: 0,
              recognitionTimeMs: 0,
            )
          : OcrRunResult.empty,
    );

    final rows = await scanner.scan(file.path, onProgress: (_, _) {});

    expect(
      rows
          .map(
            (row) =>
                '${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}',
          )
          .toSet(),
      {'Data Structures|1|780|840', 'Chemistry|2|840|900'},
      reason:
          'Scanned rows: ${rows.map((row) => "${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}").toList()}',
    );
    expect(rows.every((row) => row.ocrConfidence == .99), isTrue);
  });

  test(
    'keeps a multiline class together when a grid rule crosses its text',
    () async {
      final directory = await Directory.systemTemp.createTemp('klasify_grid_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _pathProvider,
            (call) async => directory.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_pathProvider, null);
        await directory.delete(recursive: true);
      });

      final file = File(
        '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}timetable_grid_afternoon.png',
      );
      final regions = [
        _region('Monday', 680, 80, 720, 110),
        _region('Tuesday', 1280, 80, 1320, 110),
        _region('1:00 PM', 80, 590, 150, 610),
        _region('2:00 PM', 80, 790, 150, 810),
        _region('3:00 PM', 80, 990, 150, 1010),
        _region('Social and Professional', 580, 680, 880, 700),
        _region('Issues in IT', 580, 700, 820, 720),
        _region('Room R4', 580, 720, 700, 740),
        _region('J. Sarmiento', 580, 740, 820, 760),
      ];
      final scanner = TimetableGridScanner(
        preprocessor: _NoPreprocessing(),
        recognize: (path) async => path == file.path
            ? OcrRunResult(
                results: regions,
                detectionTimeMs: 0,
                recognitionTimeMs: 0,
              )
            : OcrRunResult.empty,
      );

      final rows = await scanner.scan(file.path, onProgress: (_, _) {});

      expect(rows, hasLength(1));
      expect(rows.single.subject, 'Social and Professional Issues in IT');
      expect(rows.single.day, 1);
      expect(rows.single.startMinutes, 13 * 60);
      expect(rows.single.endMinutes, 15 * 60);
      expect(rows.single.room, 'Room R4');
      expect(rows.single.professor, 'J. Sarmiento');
    },
  );

  test('builds rows from a period-only rail and flags them for review', () async {
    final directory = await Directory.systemTemp.createTemp('klasify_grid_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _pathProvider,
          (call) async => directory.path,
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, null);
      await directory.delete(recursive: true);
    });

    final file = File(
      '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}timetable_grid_period_rail.png',
    );
    // Left gutter carries P1..P6 only; no clock is printed anywhere.
    final regions = [
      _region('Monday', 290, 80, 350, 110),
      _region('Tuesday', 530, 80, 590, 110),
      _region('Wednesday', 770, 80, 830, 110),
      _region('Thursday', 1010, 80, 1070, 110),
      _region('Friday', 1248, 80, 1308, 110),
      _region('P1', 60, 340, 160, 380),
      _region('P2', 60, 460, 160, 500),
      _region('P3', 60, 580, 160, 620),
      _region('P4', 60, 700, 160, 740),
      _region('P5', 60, 820, 160, 860),
      _region('P6', 60, 940, 160, 980),
      _region('Mathematics', 230, 340, 410, 380),
      _region('Science', 230, 460, 410, 500),
      _region('History', 470, 580, 650, 620),
    ];
    final scanner = TimetableGridScanner(
      preprocessor: _NoPreprocessing(),
      recognize: (path) async => path == file.path
          ? OcrRunResult(
              results: regions,
              detectionTimeMs: 0,
              recognitionTimeMs: 0,
            )
          : OcrRunResult.empty,
    );

    final rows = await scanner.scan(file.path, onProgress: (_, _) {});

    expect(
      rows
          .map(
            (row) =>
                '${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}',
          )
          .toSet(),
      {
        'Mathematics|1|480|540', // P1 08:00-09:00 nominal
        'Science|1|540|600', // P2 09:00-10:00 nominal
        'History|2|600|660', // P3 10:00-11:00 nominal
      },
      reason:
          'Scanned rows: ${rows.map((row) => "${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}").toList()}',
    );
    expect(rows.every((row) => row.ocrConfidence == .74), isTrue);
  });

  test('anchors rows on start clocks printed inside cells', () async {
    final directory = await Directory.systemTemp.createTemp('klasify_grid_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _pathProvider,
          (call) async => directory.path,
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, null);
      await directory.delete(recursive: true);
    });

    final file = File(
      '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}timetable_grid_no_gutter.png',
    );
    // No left gutter at all: each cell prints its subject and start clock.
    final regions = [
      _region('Monday', 140, 80, 200, 110),
      _region('Tuesday', 400, 80, 460, 110),
      _region('Wednesday', 660, 80, 720, 110),
      _region('Thursday', 920, 80, 980, 110),
      _region('Friday', 1180, 80, 1240, 110),
      _region('Mathematics', 90, 315, 250, 345),
      _region('8:00', 110, 345, 230, 375),
      _region('Science', 90, 435, 250, 465),
      _region('9:00', 110, 465, 230, 495),
      _region('Chemistry', 350, 315, 510, 345),
      _region('8:00', 370, 345, 490, 375),
      _region('History', 610, 555, 770, 585),
      _region('10:00', 630, 585, 750, 615),
    ];
    final scanner = TimetableGridScanner(
      preprocessor: _NoPreprocessing(),
      recognize: (path) async => path == file.path
          ? OcrRunResult(
              results: regions,
              detectionTimeMs: 0,
              recognitionTimeMs: 0,
            )
          : OcrRunResult.empty,
    );

    final rows = await scanner.scan(file.path, onProgress: (_, _) {});

    expect(
      rows
          .map(
            (row) =>
                '${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}',
          )
          .toSet(),
      {
        'Mathematics|1|480|540',
        'Science|1|540|600',
        'Chemistry|2|480|540',
        'History|3|600|660',
      },
      reason:
          'Scanned rows: ${rows.map((row) => "${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}").toList()}',
    );
    // Times come from printed clocks, so no review flag is added.
    expect(rows.every((row) => row.ocrConfidence == .99), isTrue);
  });
}
