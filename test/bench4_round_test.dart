import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/services/ocr_image_preprocessor.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';
import 'package:klasify/features/schedule_import/utils/domain_rescoring.dart';
import 'package:klasify/features/schedule_import/utils/parse_chain.dart';
import 'package:klasify/features/schedule_import/utils/sectioned_schedule_parser.dart';
import 'package:klasify/features/schedule_import/utils/schedule_line_preparation.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';

/// Round-4 OCR import benchmark: NON-timetable schedule formats.
///
/// Photos (test/fixtures/bench4/r4_*.png): handwritten planner x2, chat
/// screenshot x2, email/memo x2, notice board x2. These formats never reach
/// the grid scanner on device: scanImage's multi-candidate OCR returns text,
/// and the review screen runs the parser chain (SectionedScheduleParser
/// first, then TimetableParser).
///
/// Tiers per photo:
///   t1: exact rendered text_lines -> parser chain   (parser ceiling)
///   t2: tesseract candidates -> best-candidate selection (mirrors
///       _scoreOcrCandidate) -> normalizeOcrTokens -> parser chain
///       t2a = per-fragment lines, t2b = row-joined lines
///   t3: tesseract boxes -> TimetableGridScanner (documents the grid bail)
///
/// Output: build/bench4_out.json
// ignore: invalid_annotation_target
@Timeout(Duration(minutes: 40))
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final benchDir = '${Directory.current.path}/test/fixtures/bench4';
  final tmp = Directory.systemTemp.createTempSync('bench4');
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
    final out = File('${Directory.current.path}/build/bench4_out.json');
    out.createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
    tmp.deleteSync(recursive: true);
  });

  String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> encodeSectioned(List<SectionedRow> rows) => [
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

  List<Map<String, dynamic>> encodeList(List<ParsedTimetableRow> rows) => [
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

  final truth =
      jsonDecode(File('$benchDir/../bench4_truth.json').readAsStringSync())
          as Map<String, dynamic>;
  final ocrFixture =
      jsonDecode(
            File(
              '${Directory.current.path}/test/fixtures/bench4_ocr_lines.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  // Row-join: group fragments whose vertical centers are within 40% of the
  // tallest fragment height (mimics OCR engines that merge a whole visual
  // row into one line).
  // Kept as the reference implementation for the round-4 variants below.
  // ignore: unused_element
  String flatRows(List<dynamic> fragments) {
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

  // ---------------- T1: exact rendered text -> parser chain ----------------
  test('t1: parser chain on exact rendered text', () {
    for (final photo in truth.keys) {
      final text = (truth[photo]['text_lines'] as List).join('\n');
      final chain = ParseChain.parse(text);
      final sectioned = SectionedScheduleParser.parse(
        prepareScheduleLines(text).join('\n'),
      );
      final list = TimetableParser.parse(text);
      final used = sectioned.isNotEmpty
          ? 'sectioned'
          : (list.isNotEmpty ? 'list' : 'none');
      results[photo] = {
        'style': truth[photo]['style'],
        't1': {
          'used': used,
          'chain_used': chain.used,
          'sectioned_rows': encodeSectioned(sectioned),
          'list_rows': encodeList(list),
          'rows': chain.sectioned.isNotEmpty
              ? encodeSectioned(chain.sectioned)
              : encodeList(chain.list),
        },
      };
    }
  });

  /// Geometric line reconstruction from raw word boxes — the faithful
  /// stand-in for PP-OCR det (which returns per-line boxes natively).
  /// Mirrors schedule_ocr_service._joinOcrRegions: sort by vertical center,
  /// band when within max(5, min(height, bandHeight) * .6) of the band
  /// center, then join left-to-right with spaces.
  String geometricLines(List<dynamic> words) {
    final ws = words.map((w) => w as Map).toList()
      ..sort((a, b) {
        final ca = ((a['top'] as int) + (a['h'] as int) / 2);
        final cb = ((b['top'] as int) + (b['h'] as int) / 2);
        return ca.compareTo(cb);
      });
    final lines = <String>[];
    var band = <Map>[];
    var bandCenter = 0.0;
    var bandHeight = 0.0;
    void flush() {
      if (band.isEmpty) return;
      band.sort((a, b) => (a['left'] as int).compareTo(b['left'] as int));
      lines.add(band.map((w) => w['text'] as String).join(' '));
      band = <Map>[];
      bandCenter = 0;
      bandHeight = 0;
    }

    for (final w in ws) {
      final top = w['top'] as int;
      final h = w['h'] as int;
      final center = top + h / 2;
      if (band.isNotEmpty &&
          center - bandCenter >
              math.max(5.0, math.min(h.toDouble(), bandHeight) * .6)) {
        flush();
      }
      if (band.isEmpty) {
        bandCenter = center;
        bandHeight = h.toDouble();
      } else {
        bandCenter = (bandCenter * band.length + center) / (band.length + 1);
        bandHeight = (bandHeight * band.length + h) / (band.length + 1);
      }
      band.add(w);
    }
    flush();
    return lines.join('\n');
  }

  // ---------------- T2: OCR candidates -> best -> chain --------------------
  // Mirrors schedule_ocr_service._scoreOcrCandidate's primary ordering:
  // most parsed rows wins (max of sectioned/list), meanConf breaks ties.
  // Two line reconstructions compete (both plausible det proxies):
  //   t2a: geometric banding of raw word boxes (PP-OCR det stand-in)
  //   t2b: tesseract's own line ids (can interleave adjacent full-width
  //        lines; kept to document the risk)
  test('t2: best-candidate OCR -> parser chain', () {
    for (final photo in truth.keys) {
      final cands = (ocrFixture[photo]['candidates'] as List).cast<Map>();
      ({String label, double conf, String geoText})? best;
      var bestScore = -1.0;
      for (final cand in cands) {
        final words = (cand['word_boxes'] as List).cast<Map>();
        final geoText = geometricLines(words);
        // Either confidence key can be present; casting before the fallback
        // threw on candidates that only carry 'meanConf'.
        final conf = ((cand['meanWordConf'] ?? cand['meanConf']) as num)
            .toDouble();
        final score = ParseChain.score(geoText, conf);
        if (score > bestScore) {
          bestScore = score;
          best = (label: cand['label'] as String, conf: conf, geoText: geoText);
        }
      }
      if (best == null) continue;
      final frags =
          (ocrFixture[photo]['candidates'] as List).cast<Map>().firstWhere(
                (c) => c['label'] == best!.label,
              )['frags']
              as List;
      final geoJoin = normalizeOcrTokens(best.geoText);
      final tessJoin = normalizeOcrTokens(
        frags.map((f) => f['text'] as String).join('\n'),
      );
      final geoRes = ParseChain.parse(geoJoin);
      final tessRes = ParseChain.parse(tessJoin);
      final geoRows = geoRes.sectioned.isNotEmpty
          ? encodeSectioned(geoRes.sectioned)
          : encodeList(geoRes.list);
      final tessRows = tessRes.sectioned.isNotEmpty
          ? encodeSectioned(tessRes.sectioned)
          : encodeList(tessRes.list);
      final geoWins = geoRows.length >= tessRows.length;
      results.putIfAbsent(
        photo,
        () => {'style': truth[photo]['style']},
      )['t2'] = {
        'candidate': best.label,
        'candidate_conf': best.conf,
        't2a': {'used': geoRes.used, 'rows': geoRows},
        't2b': {'used': tessRes.used, 'rows': tessRows},
        'rows': geoWins ? geoRows : tessRows,
        'variant': geoWins ? 't2a' : 't2b',
      };
    }
  });

  // ---------------- T3: full grid scanner (documents the bail) -------------
  Future<void> runScanner(String photo) async {
    final scanner = TimetableGridScanner(
      recognize: tesseract,
      preprocessor: OcrImagePreprocessor(),
    );
    final rows = await scanner.scan('$benchDir/$photo', onProgress: (_, __) {});
    results.putIfAbsent(photo, () => {'style': truth[photo]['style']})['t3'] =
        encodeList(rows);
  }

  for (final photo in truth.keys) {
    test('t3 grid scanner: $photo', () => runScanner(photo));
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
