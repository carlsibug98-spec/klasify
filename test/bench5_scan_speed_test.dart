import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/services/schedule_ocr_service.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';
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

  // The benchmark needs the tesseract CLI as its OCR stand-in. It is not an
  // app dependency and is absent from most developer machines, so skip the
  // benchmark cleanly instead of reporting nine fixture failures.
  final benchSkip = _tesseractAvailable()
      ? false
      : 'tesseract is not installed; benchmark needs the CLI OCR stand-in';

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
    // Round-7 student COR samples: a clean registry, labs/online columns,
    // a skewed phone photo, an out-of-focus shot, a low-res capture and a
    // dim noisy shot. The soft ones exercise the sharpen rescue pass, so
    // the call counts show exactly what the rescue costs.
    ...const [
      'cor_registry_clean.png',
      'cor_labs_online.png',
      'cor_phone_skewed.jpg',
      'cor_phone_blurred.png',
      'cor_lowres.png',
      'cor_dim_noise.png',
    ].map((name) => '$fixturesDir/cor/$name'),
  ];

  final service = ScheduleOcrService();

  for (final fixture in fixtures) {
    // fixture paths mix separators: fixturesDir is OS-native, the tail is
    // written with '/'. Split on either so the label stays readable on
    // Windows too.
    final name = fixture.split(RegExp(r'[\\/]')).last;
    test('scan pipeline: $name', skip: benchSkip, () async {
      tesseractPlatform.calls = 0;
      tesseractPlatform.paths.clear();
      final entry = <String, dynamic>{};

      // ---- Stage 1: grid scan (as the import screen runs it) -------------
      final gridStats = GridScanStats();
      final gridWatch = Stopwatch()..start();
      final gridRows = await service.scanGridImage(
        fixture,
        onProgress: (_, __) {},
        stats: gridStats,
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
      // when the grid geometry mapped the page (rows carry the structure),
      // and also runs for a SUSPICIOUS grid result (<= 2 rows from a page
      // that read far more lines than it mapped - a notice board locking
      // onto a stray line); the stronger ParseChain candidate wins.
      final gridSuspicious =
          gridRows.isNotEmpty &&
          gridRows.length <= 2 &&
          gridStats.lineCount > gridRows.length * 8;
      final runTextStage = gridRows.isEmpty || gridSuspicious;
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
      final chain = ParseChain.parse(text);
      final sectioned = chain.sectioned;
      final listRows = sectioned.isEmpty
          ? TimetableParser.parse(text)
          : <ParsedTimetableRow>[];
      ({String source, List<Map<String, dynamic>> rows, int count})
      textResult() {
        if (sectioned.isNotEmpty) {
          return (
            source: 'sectioned',
            rows: encodeSectioned(sectioned),
            count: sectioned.length,
          );
        }
        if (hasWeekdayHeaders && listRows.isNotEmpty) {
          return (
            source: 'list',
            rows: encodeList(listRows),
            count: listRows.length,
          );
        }
        return (
          source: chain.list.isEmpty ? 'none' : 'list',
          rows: encodeList(chain.list),
          count: chain.list.length,
        );
      }

      String finalSource;
      int finalRows;
      if (gridRows.isEmpty) {
        final resolved = textResult();
        finalSource = resolved.source;
        finalRows = resolved.count;
        entry['final_rows'] = resolved.rows;
      } else if (!gridSuspicious) {
        finalSource = 'grid';
        finalRows = gridRows.length;
        entry['final_rows'] = encodeGrid(gridRows);
      } else {
        // Weak-grid rescue, scored exactly like the screen: parsed rows win
        // on the shared scale, an empty text candidate never displaces grid
        // rows.
        final confidences = gridRows
            .map((row) => row.ocrConfidence)
            .whereType<double>()
            .toList();
        final gridMeanConfidence = confidences.isEmpty
            ? 0.0
            : confidences.reduce((a, b) => a + b) / confidences.length;
        final gridScore = ParseChain.scoreRows(
          gridRows,
          meanConfidence: gridMeanConfidence,
        );
        final textScore = text.isEmpty
            ? double.negativeInfinity
            : ParseChain.score(text, 0);
        final candidate = textResult();
        if (candidate.count > 0 && textScore > gridScore) {
          finalSource = candidate.source;
          finalRows = candidate.count;
          entry['final_rows'] = candidate.rows;
          entry['rescued_from_grid'] = true;
        } else {
          finalSource = 'grid';
          finalRows = gridRows.length;
          entry['final_rows'] = encodeGrid(gridRows);
        }
      }
      entry['rescued_from_grid'] ??= false;
      entry['final'] = {
        'source': finalSource,
        'rows': finalRows,
        'recognize_calls': gridCalls + textCalls,
        'seconds': _round(_sec(gridWatch) + textSeconds),
      };
      results[name] = entry;
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  test('summary: totals across fixtures', skip: benchSkip, () {
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
/// True when the tesseract CLI used by the benchmark stand-in is runnable.
bool _tesseractAvailable() {
  try {
    return Process.runSync('tesseract', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

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
