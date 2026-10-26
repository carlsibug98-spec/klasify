import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/services/ocr_image_preprocessor.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';

/// Round-3 OCR import benchmark.
///
/// Drives the REAL import pipeline (TimetableGridScanner + TimetableParser)
/// inside `flutter test`, with the on-device PP-OCRv6 engine replaced by
/// tesseract (the native ONNX runtime cannot run in the test VM). Tesseract
/// word boxes are merged into per-cell line boxes with a column-gutter split
/// so the geometry approximates what the paddle detector returns.
///
/// Tiers per photo:
///   t1: ground-truth lines -> TimetableParser   (parser ceiling, list styles)
///   t2: tesseract flattened text -> TimetableParser (flat fallback path)
///   t3: tesseract boxes -> TimetableGridScanner (full grid path)
///
/// Output: build/bench3_out.json
// ignore: invalid_annotation_target
@Timeout(Duration(minutes: 40))
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final benchDir = '${Directory.current.path}/test/fixtures/bench3';
  final tmp = Directory.systemTemp.createTempSync('bench3');
  final results = <String, Map<String, dynamic>>{};

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getTemporaryDirectory') return tmp.path;
          return null;
        });
  });

  tearDownAll(() {
    final out = File('${Directory.current.path}/build/bench3_out.json');
    out.createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
    tmp.deleteSync(recursive: true);
  });

  String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> encodeRows(List<ParsedTimetableRow> rows) => [
    for (final r in rows)
      {
        'subject': r.subject,
        'room': r.room,
        'professor': r.professor,
        'day': r.day,
        'start': hhmm(r.startMinutes),
        'end': hhmm(r.endMinutes),
        'conf': r.ocrConfidence,
      },
  ];

  Future<OcrRunResult> tesseract(String path) async {
    final proc = await Process.run('tesseract', [
      path,
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

  // The bench3 screenshot folder is optional in a checkout (the t3 cases
  // skip themselves when a photo is absent), so never resolve fixtures
  // through $benchDir — the `bench3/..` path fails to open whenever the
  // folder itself isn't shipped. Read the JSONs straight from test/fixtures.
  final truth =
      jsonDecode(
            File(
              '${Directory.current.path}/test/fixtures/bench3_truth.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final ocrFixture =
      jsonDecode(
            File(
              '${Directory.current.path}/test/fixtures/bench3_ocr_lines.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  // ---------------- T1: ground-truth lines -> parser (list styles only) ----
  String groundTruthLines(String photo) {
    final classes = (truth[photo]['truth_classes'] as List)
        .cast<Map<String, dynamic>>();
    if (photo == 'r3_am_pm_noon.png') {
      return classes
          .map(
            (c) =>
                '${c['day']} ${_to12(c['start'] as String)} - '
                '${_to12(c['end'] as String)} ${c['subject']}',
          )
          .join('\n');
    }
    if (photo == 'r3_phone_screenshot.png') {
      final buf = <String>[];
      var currentDay = '';
      for (final c in classes) {
        if (c['day'] != currentDay) {
          currentDay = c['day'] as String;
          buf.add(currentDay.toUpperCase());
        }
        buf.add('${c['start']} - ${c['end']} ${c['subject']}');
      }
      return buf.join('\n');
    }
    return '';
  }

  String flatRows(List<dynamic> fragments) {
    // Row-join: group fragments whose vertical centers are within 40% of the
    // tallest fragment height (mimics OCR engines that merge a whole visual
    // row into one line, e.g. paddle det on sparse lists).
    final frags = fragments.map((f) => f as Map).toList()
      ..sort((a, b) => (a['top'] as int).compareTo(b['top'] as int));
    final lines = <String>[];
    var current = <Map>[];
    double? currentCenter;
    var currentH = 0;
    void flush() {
      if (current.isEmpty) return;
      current.sort((a, b) => (a['left'] as int).compareTo(b['left'] as int));
      lines.add(current.map((f) => f['text'] as String).join(' '));
      current = <Map>[];
    }

    for (final f in frags) {
      final top = f['top'] as int;
      final bottom = f['bottom'] as int;
      final center = (top + bottom) / 2;
      final h = bottom - top;
      if (currentCenter == null ||
          (center - currentCenter).abs() <=
              0.4 * (h > currentH ? h : currentH)) {
        current.add(f);
        currentCenter = currentCenter == null
            ? center
            : (currentCenter + center) / 2;
        currentH = h > currentH ? h : currentH;
      } else {
        flush();
        current = [f];
        currentCenter = center.toDouble();
        currentH = h;
      }
    }
    flush();
    return lines.join('\n');
  }

  test('t1/t2: parser tiers for all photos', () async {
    for (final photo in truth.keys) {
      final per = <String, dynamic>{};
      final gt = groundTruthLines(photo);
      if (gt.isNotEmpty) {
        per['t1'] = encodeRows(TimetableParser.parse(gt));
      }
      final frags = ocrFixture[photo] as List;
      final cellSplit = frags
          .map((l) => (l as Map)['text'] as String)
          .join('\n');
      per['t2a'] = encodeRows(TimetableParser.parse(cellSplit));
      per['t2b'] = encodeRows(TimetableParser.parse(flatRows(frags)));
      results[photo] = {
        if (per.containsKey('t1')) 't1': per['t1'],
        't2a': per['t2a'],
        't2b': per['t2b'],
      };
    }
  });

  // ---------------- T3: full grid scanner per photo ------------------------
  Future<void> runScanner(String photo) async {
    final scanner = TimetableGridScanner(
      recognize: tesseract,
      preprocessor: OcrImagePreprocessor(),
    );
    final rows = await scanner.scan('$benchDir/$photo', onProgress: (_, __) {});
    results.putIfAbsent(photo, () => <String, dynamic>{})['t3'] = encodeRows(
      rows,
    );
  }

  // Each case needs its source photo. Like the hard set below, checkouts that
  // ship without the bench3 screenshots skip the case — a missing image is an
  // absent fixture, not a scanner regression.
  const scannerPhotos = [
    'r3_sat_column.png',
    'r3_merged_cells.png',
    'r3_vertical_headers.png',
    'r3_am_pm_noon.png',
    'r3_dot_times.png',
    'r3_pastel_blocks.png',
    'r3_two_line_wrap.png',
    'r3_no_time_column.png',
    'r3_portal_screenshot.png',
    'r3_alternating_slot.png',
    'r3_phone_screenshot.png',
    'r3_spreadsheet.png',
  ];
  for (final photo in scannerPhotos) {
    final shipped = File('$benchDir/$photo').existsSync();
    test(
      't3 scanner: ${photo.substring(0, photo.length - 4)}',
      () => runScanner(photo),
      skip: shipped ? false : 'fixture $photo is not in this checkout',
    );
  }

  // ---------------- Cross-check: round-2 hard set (real photos) ------------
  // Only runs when the benchmark upload folder is present (dev machine);
  // skipped elsewhere so the shipped test suite stays green.
  final hardDir = '/home/z/my-project/upload/ocr_timetables_hard';
  if (Directory(hardDir).existsSync()) {
    final hardTruth =
        jsonDecode(File('$hardDir/answer_key.json').readAsStringSync())
            as Map<String, dynamic>;

    Future<void> runHardScanner(String photo) async {
      final scanner = TimetableGridScanner(
        recognize: tesseract,
        preprocessor: OcrImagePreprocessor(),
      );
      final rows = await scanner.scan(
        '$hardDir/$photo',
        onProgress: (_, __) {},
      );
      results.putIfAbsent(photo, () => <String, dynamic>{})['t3'] = encodeRows(
        rows,
      );
    }

    test('hard set: parser tiers from truth text_lines', () {
      for (final photo in hardTruth.keys) {
        final entry = hardTruth[photo] as Map<String, dynamic>;
        final text = (entry['text_lines'] as List).join('\n');
        results.putIfAbsent(photo, () => <String, dynamic>{})['t1'] =
            encodeRows(TimetableParser.parse(text));
      }
    });

    for (final photo in hardTruth.keys) {
      test('hard set t3: $photo', () => runHardScanner(photo));
    }
  }
}

String _to12(String hhmm) {
  final parts = hhmm.split(':');
  var h = int.parse(parts[0]);
  final suffix = h >= 12 ? 'PM' : 'AM';
  h = h % 12;
  if (h == 0) h = 12;
  return '$h:${parts[1]} $suffix';
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
