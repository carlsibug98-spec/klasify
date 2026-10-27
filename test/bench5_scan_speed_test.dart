import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/services/schedule_ocr_service.dart';
import 'package:klasify/features/schedule_import/utils/parse_chain.dart';
import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
// The platform interface is not exported publicly; bench-only injection
// (same mocking seam flutter's PlatformInterface pattern provides).
// ignore: implementation_imports
import 'package:paddle_ocr_native/src/paddle_ocr_platform.dart';

/// Round-5 scan-speed benchmark: END-TO-END cost of importing ONE picture.
///
/// Drives the real ScheduleOcrService exactly the way the import screen
/// orchestrates an image (scanGridImage first, then scanImage) with the real
/// OcrImagePreprocessor, inside `flutter test`, with the native ONNX runtime
/// replaced by tesseract 5.5.0 through `PaddleOcrNativePlatform.instance`
/// (the same stand-in as bench3/bench4: the native engine cannot run in the
/// test VM). Tesseract's seconds-per-call models the device's seconds-per-call
/// well enough for before/after RATIO comparison; the recognition-pass COUNT
/// is the engine-independent part of the result.
///
/// Fixtures: the three shipped weekly-grid photos plus the eight round-4
/// list-style photos (planner x2, chat x2, email x2, notice board x2).
///
/// Output: build/bench5_out.json with per-fixture call counts, wall seconds
/// per stage, and the final parsed rows (the before/after quality gate).
// ignore: invalid_annotation_target
@Timeout(Duration(minutes: 45))
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixturesDir = '${Directory.current.path}/test/fixtures';
  final tmp = Directory.systemTemp.createTempSync('bench5');
  final results = <String, Map<String, dynamic>>{};

  final tesseractPlatform = _TesseractOcrPlatform();

  // Inject BEFORE the service is constructed: PaddleOcr is a singleton that
  // captures the platform instance at first construction.
  PaddleOcrNativePlatform.instance = tesseractPlatform;

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getTemporaryDirectory') return tmp.path;
          return null;
        });
  });

  tearDownAll(() {
    final out = File('${Directory.current.path}/build/bench5_out.json');
    out.createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
    tmp.deleteSync(recursive: true);
  });

  String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> encodeGrid(List<ParsedTimetableRow> rows) => [
    for (final r in rows)
      {
        'subject': r.subject,
        'room': r.room,
        'day': r.day,
        'start': hhmm(r.startMinutes),
        'end': hhmm(r.endMinutes),
      },
  ];

  List<Map<String, dynamic>> encodeSectioned(List<SectionedRow> rows) => [
    for (final r in rows)
      {
        'subject': r.subject,
        'room': r.room,
        'day': r.day,
        'start': hhmm(r.startMinutes),
        'end': hhmm(r.endMinutes),
      },
  ];

  List<Map<String, dynamic>> encodeList(List<ParsedTimetableRow> rows) =>
      encodeGrid(rows);

  final fixtures = [
    ...[
      'timetable_grid_afternoon.png',
      'timetable_grid_no_gutter.png',
      'timetable_grid_period_rail.png',
    ].map((name) => '$fixturesDir/$name'),
    ...Directory('$fixturesDir/bench4')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .map((file) => file.path)
        .toList()
      ..sort(),
  ];

  final service = ScheduleOcrService();

  for (final fixture in fixtures) {
    final name = fixture.split('/').last;
    test('scan pipeline: $name', () async {
      tesseractPlatform.calls = 0;
      tesseractPlatform.paths.clear();
      final entry = <String, dynamic>{};

      // ---- Stage 1: grid scan (as the import screen runs it) -------------
      final gridWatch = Stopwatch()..start();
      final gridRows = await service.scanGridImage(
        fixture,
        onProgress: (_, __) {},
      );
      gridWatch.stop();
      final gridCalls = tesseractPlatform.calls;
      entry['grid'] = {
        'recognize_calls': gridCalls,
        'seconds': _sec(gridWatch),
        'rows': encodeGrid(gridRows),
      };

      // ---- Stage 2: text scan (as the import screen runs it) -------------
      // Mirrors import_schedule_screen: the flat-text cascade is skipped
      // when the grid stage already found rows (its result was discarded
      // by the selection logic).
      const skipTextStageWhenGridFoundRows = true;
      final runTextStage = gridRows.isEmpty || !skipTextStageWhenGridFoundRows;
      String text = '';
      var textCalls = 0;
      double textSeconds = 0;
      if (runTextStage) {
        final textWatch = Stopwatch()..start();
        text = await service.scanImage(fixture, onProgress: (_, __) {});
        textWatch.stop();
        textCalls = tesseractPlatform.calls - gridCalls;
        textSeconds = _sec(textWatch);
      }
      entry['text'] = {
        'recognize_calls': textCalls,
        'seconds': _round(textSeconds),
        'skipped': !runTextStage,
        'text_chars': text.length,
      };

      // ---- Final selection (mirrors the screen's logic) -------------------
      final hasWeekdayHeaders =
          RegExp(
            r'\b(?:MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|FRI(?:DAY)?)\b',
            caseSensitive: false,
          ).allMatches(text).length >=
          2;
      String finalSource;
      int finalRows;
      if (gridRows.isNotEmpty) {
        finalSource = 'grid';
        finalRows = gridRows.length;
        entry['final_rows'] = encodeGrid(gridRows);
      } else {
        final chain = ParseChain.parse(text);
        final sectioned = chain.sectioned;
        final listRows = sectioned.isNotEmpty
            ? <ParsedTimetableRow>[]
            : TimetableParser.parse(text);
        if (sectioned.isNotEmpty) {
          finalSource = 'sectioned';
          finalRows = sectioned.length;
          entry['final_rows'] = encodeSectioned(sectioned);
        } else if (hasWeekdayHeaders && listRows.isNotEmpty) {
          finalSource = 'list';
          finalRows = listRows.length;
          entry['final_rows'] = encodeList(listRows);
        } else {
          finalSource = chain.list.isNotEmpty ? 'list' : 'none';
          finalRows = chain.list.length;
          entry['final_rows'] = encodeList(chain.list);
        }
      }
      entry['final'] = {
        'source': finalSource,
        'rows': finalRows,
        'recognize_calls': gridCalls + textCalls,
        'seconds': _round(_sec(gridWatch) + textSeconds),
      };
      results[name] = entry;
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  test('summary: totals across fixtures', () {
    var calls = 0;
    var seconds = 0.0;
    var gridCalls = 0;
    var textCalls = 0;
    for (final entry in results.values) {
      calls += (entry['final']['recognize_calls'] as num).toInt();
      seconds += entry['final']['seconds'] as double;
      gridCalls += (entry['grid']['recognize_calls'] as num).toInt();
      textCalls += (entry['text']['recognize_calls'] as num).toInt();
    }
    results['__summary__'] = {
      'fixtures': results.length,
      'recognize_calls_total': calls,
      'recognize_calls_grid_stage': gridCalls,
      'recognize_calls_text_stage': textCalls,
      'seconds_total': _round(seconds),
    };
  });
}

double _sec(Stopwatch watch) => _round(watch.elapsedMicroseconds / 1e6);

double _round(double value) => (value * 100).roundToDouble() / 100;

/// Tesseract stand-in for the native PP-OCR engine (bench3/bench4 pattern).
class _TesseractOcrPlatform extends PaddleOcrNativePlatform {
  int calls = 0;
  final List<String> paths = [];

  @override
  Future<Map<String, dynamic>> init({
    required PaddleOcrConfig config,
    required EngineConfig engine,
  }) async => {};

  @override
  Future<void> release() async {}

  @override
  Future<OcrRunResult> recognize(String imagePath) async {
    calls++;
    paths.add(imagePath);
    final proc = await Process.run('tesseract', [
      imagePath,
      'stdout',
      'tsv',
      '--psm',
      '11',
    ]);
    final words = <_Word>[];
    for (final line in proc.stdout.toString().split('\n').skip(1)) {
      if (line.trim().isEmpty) continue;
      final f = line.split('\t');
      if (f.length < 12) continue;
      if (f[0] != '5') continue;
      final text = f[11].trim();
      final conf = double.tryParse(f[10]) ?? -1;
      if (text.isEmpty || conf < 0) continue;
      words.add(
        _Word(
          int.parse(f[2]),
          int.parse(f[3]),
          int.parse(f[4]),
          int.parse(f[6]),
          int.parse(f[7]),
          int.parse(f[8]),
          int.parse(f[9]),
          conf,
          text,
        ),
      );
    }
    final groups = <String, List<_Word>>{};
    for (final w in words) {
      groups.putIfAbsent('${w.block}-${w.par}-${w.line}', () => []).add(w);
    }
    final regions = <OcrResult>[];
    for (final ws in groups.values) {
      ws.sort((a, b) => a.left.compareTo(b.left));
      final heights = ws.map((w) => w.h).toList()..sort();
      final hMed = heights[heights.length ~/ 2].toDouble();
      // Merge words whose horizontal gap is at most 1.1x the line height
      // into one run, so multi-word cell labels come out as one line box
      // (mirrors bench3's per-line reconstruction).
      final runs = <List<_Word>>[
        [ws.first],
      ];
      for (final w in ws.skip(1)) {
        final gap = w.left - (runs.last.last.left + runs.last.last.w);
        if (gap > 1.1 * hMed) {
          runs.add([w]);
        } else {
          runs.last.add(w);
        }
      }
      for (final run in runs) {
        final text = run.map((w) => w.text).join(' ').trim();
        if (text.isEmpty) continue;
        final left = run.map((w) => w.left).reduce(math.min);
        final top = run.map((w) => w.top).reduce(math.min);
        final right = run.map((w) => w.left + w.w).reduce(math.max);
        final bottom = run.map((w) => w.top + w.h).reduce(math.max);
        final conf =
            run.map((w) => w.conf).reduce((a, b) => a + b) / run.length / 100;
        regions.add(
          OcrResult(
            text: text,
            confidence: conf,
            points: [
              OcrPoint(x: left, y: top),
              OcrPoint(x: right, y: top),
              OcrPoint(x: right, y: bottom),
              OcrPoint(x: left, y: bottom),
            ],
          ),
        );
      }
    }
    return OcrRunResult(
      results: regions,
      detectionTimeMs: 0,
      recognitionTimeMs: 0,
    );
  }
}

class _Word {
  const _Word(
    this.block,
    this.par,
    this.line,
    this.left,
    this.top,
    this.w,
    this.h,
    this.conf,
    this.text,
  );

  final int block;
  final int par;
  final int line;
  final int left;
  final int top;
  final int w;
  final int h;
  final double conf;
  final String text;
}
