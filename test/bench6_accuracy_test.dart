import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/services/schedule_ocr_service.dart';
import 'package:klasify/features/schedule_import/services/timetable_grid_scanner.dart';
import 'package:klasify/features/schedule_import/utils/parse_chain.dart';
import 'package:klasify/features/schedule_import/utils/timetable_parser.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
// The platform interface is not exported publicly; bench-only injection
// (same mocking seam flutter's PlatformInterface pattern provides).
// ignore: implementation_imports
import 'package:paddle_ocr_native/src/paddle_ocr_platform.dart';

/// Round-6 scan-ACCURACY benchmark: what does one imported picture COST in
/// correctness, before vs after the round-5 speed optimization?
///
/// Runs the exact bench5 orchestration (real ScheduleOcrService + real
/// OcrImagePreprocessor + tesseract 5.5.0 stand-in for the native ONNX
/// engine) and scores the FINAL parsed rows against hand-labeled ground
/// truth, so a speed win can never hide a recognition regression.
///
/// Ground truth: `test/fixtures/bench4_truth.json` -> `truth_classes`
/// (subject / day / start / end per class, 65 classes across 8 photos) plus
/// the round-7 student COR set `test/fixtures/cor_truth.json` (57 classes
/// across 6 samples, which also carry room and faculty labels).
/// The three `timetable_grid_*.png` fixtures are EXCLUDED from scoring:
/// they are deliberately text-free grid photos (verified visually and by
/// bench5: zero rows in every run), so they have no accuracy meaning.
///
/// Matching: a truth class and a parsed row pair 1-to-1 when their days are
/// equal, their [start,end) intervals overlap, and the normalized subject
/// similarity is >= 0.34; pairs are chosen greedily by descending similarity.
///
/// Metrics per fixture:
///   recall        matched / truth classes
///   precision     matched / parsed rows
///   f1            harmonic mean of the two
///   subject_exact normalized subject strings equal
///   subject_sim   mean normalized-Levenshtein similarity over matches
///   subject_cer   mean char error rate (lev / truth length) over matches
///   day_ok/start_ok/end_ok  fraction of matches with the field exactly right
///   room_ok/professor_ok    COR-only field checks (null for non-COR photos)
///   false_positives  parsed rows matched to no truth class
///   missed           truth classes matched to no parsed row
///
/// Output: build/bench6_accuracy.json
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
  final tmp = Directory.systemTemp.createTempSync('bench6');
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
    final out = File('${Directory.current.path}/build/bench6_accuracy.json');
    out.createSync(recursive: true);
    out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
    tmp.deleteSync(recursive: true);
  });

  final bench4Truth =
      jsonDecode(File('$fixturesDir/bench4_truth.json').readAsStringSync())
          as Map<String, dynamic>;
  final corTruth =
      jsonDecode(File('$fixturesDir/cor_truth.json').readAsStringSync())
          as Map<String, dynamic>;
  // The round-11 generalization fixtures ship their truth in the *_gen
  // files; merge them so every fixture in bench4/ has ground truth.
  final bench4TruthGen =
      jsonDecode(File('$fixturesDir/bench4_truth_gen.json').readAsStringSync())
          as Map<String, dynamic>;
  final corTruthGen =
      jsonDecode(File('$fixturesDir/cor_truth_gen.json').readAsStringSync())
          as Map<String, dynamic>;
  final truth = <String, Map<String, dynamic>>{
    ...bench4Truth.cast<String, Map<String, dynamic>>(),
    ...bench4TruthGen.cast<String, Map<String, dynamic>>(),
    ...corTruth.cast<String, Map<String, dynamic>>(),
    ...corTruthGen.cast<String, Map<String, dynamic>>(),
  };

  final fixtures = [
    ...Directory('$fixturesDir/bench4')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .map((file) => file.path)
        .toList()
      ..sort(),
    // Round-7 student COR samples: 6 different photos, 57 ground-truth
    // classes, room and faculty labels included.
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
    // File paths use the platform separator; truth keys are bare file names.
    final name = fixture.split(Platform.pathSeparator).last;
    test('scan accuracy: $name', skip: benchSkip, () async {
      tesseractPlatform.calls = 0;
      final classes = (truth[name]!['truth_classes'] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (c) => _TruthClass(
              subject: c['subject'] as String,
              day: _dayIndex(c['day'] as String),
              start: _minutes(c['start'] as String),
              end: _minutes(c['end'] as String),
              room: c['room'] as String?,
              professor: c['professor'] as String?,
            ),
          )
          .toList();

      // ---- Pipeline, exactly as the import screen runs it ----------------
      final gridStats = GridScanStats();
      final gridRows = await service.scanGridImage(
        fixture,
        onProgress: (_, __) {},
        stats: gridStats,
      );
      // Mirrors import_schedule_screen: the flat-text cascade is skipped when
      // the grid geometry mapped the page, and also runs for a SUSPICIOUS
      // grid result (<= 2 rows from a page that read far more lines than it
      // mapped - a notice board locking onto a stray line); the stronger
      // ParseChain candidate wins. On pre-rescue trees the text stage either
      // ran (grid empty) or was discarded, so the final rows this benchmark
      // scores stay comparable.
      final gridSuspicious =
          gridRows.isNotEmpty &&
          gridRows.length <= 2 &&
          gridStats.lineCount > gridRows.length * 8;
      String text = '';
      if (gridRows.isEmpty || gridSuspicious) {
        text = await service.scanImage(fixture, onProgress: (_, __) {});
      }

      final rows = _finalRows(gridRows, gridSuspicious, text);
      final calls = tesseractPlatform.calls;

      // ---- Score against truth -------------------------------------------
      final matches = _matchGreedy(classes, rows);
      var exact = 0;
      var simSum = 0.0;
      var cerSum = 0.0;
      var dayOk = 0;
      var startOk = 0;
      var endOk = 0;
      var roomOk = 0;
      var profOk = 0;
      var roomScored = 0;
      for (final m in matches) {
        final t = classes[m.truthIndex];
        final r = rows[m.rowIndex];
        final sim = _similarity(t.subject, r.subject);
        if (_norm(t.subject) == _norm(r.subject)) exact++;
        simSum += sim;
        cerSum += t.subject.isEmpty
            ? 0
            : _levenshtein(_norm(t.subject), _norm(r.subject)) /
                  t.subject.length;
        if (t.day == r.day) dayOk++;
        if (t.start == r.startMinutes) startOk++;
        if (t.end == r.endMinutes) endOk++;
        if (t.room != null) {
          roomScored++;
          if (_norm(t.room!) == _norm(r.room) && _norm(t.room!).isNotEmpty) {
            roomOk++;
          }
        }
        if (t.professor != null &&
            _similarity(t.professor!, r.professor) >= .85) {
          profOk++;
        }
      }
      final n = matches.length;
      final recall = classes.isEmpty ? 1.0 : n / classes.length;
      final precision = rows.isEmpty ? 1.0 : n / rows.length;
      final f1 = (recall + precision) == 0
          ? 0.0
          : 2 * recall * precision / (recall + precision);

      results[name] = {
        'style': truth[name]!['style'],
        'truth_classes': classes.length,
        'parsed_rows': rows.length,
        'matched': n,
        'recall': _r(recall),
        'precision': _r(precision),
        'f1': _r(f1),
        'subject_exact': exact,
        'subject_sim': n == 0 ? null : _r(simSum / n),
        'subject_cer': n == 0 ? null : _r(cerSum / n),
        'day_ok': n == 0 ? null : _r(dayOk / n),
        'start_ok': n == 0 ? null : _r(startOk / n),
        'end_ok': n == 0 ? null : _r(endOk / n),
        'room_ok': roomScored == 0 ? null : _r(roomOk / roomScored),
        'professor_ok': roomScored == 0 ? null : _r(profOk / roomScored),
        'false_positives': rows.length - n,
        'missed': classes.length - n,
        'recognize_calls': calls,
        'parsed': [
          for (final r in rows)
            {
              'subject': r.subject,
              'day': r.day,
              'start': _hhmm(r.startMinutes),
              'end': _hhmm(r.endMinutes),
              'room': r.room,
              'professor': r.professor,
            },
        ],
        'matched_pairs': [
          for (final m in matches)
            '${classes[m.truthIndex].subject} <-> ${rows[m.rowIndex].subject}',
        ],
      };
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  test('summary: micro-averaged accuracy across fixtures', skip: benchSkip, () {
    var truthTotal = 0;
    var parsedTotal = 0;
    var matchedTotal = 0;
    var exactTotal = 0;
    var callsTotal = 0;
    var simSum = 0.0;
    var simN = 0;
    for (final entry in results.values) {
      truthTotal += entry['truth_classes'] as int;
      parsedTotal += entry['parsed_rows'] as int;
      matchedTotal += entry['matched'] as int;
      exactTotal += entry['subject_exact'] as int;
      callsTotal += entry['recognize_calls'] as int;
      final sim = entry['subject_sim'] as double?;
      if (sim != null) {
        simSum += sim;
        simN++;
      }
    }
    final recall = truthTotal == 0 ? 1.0 : matchedTotal / truthTotal;
    final precision = parsedTotal == 0 ? 1.0 : matchedTotal / parsedTotal;
    final f1 = (recall + precision) == 0
        ? 0.0
        : 2 * recall * precision / (recall + precision);
    // Structural sanity, not pinned OCR numbers: every fixture must produce
    // a scored entry and every fixture must carry ground truth.
    expect(results, hasLength(fixtures.length));
    for (final entry in results.values) {
      expect(entry['truth_classes'] as int, greaterThan(0));
      expect(entry.keys, containsAll(['recall', 'f1', 'subject_cer']));
    }
    results['__summary__'] = {
      'fixtures': fixtures.length,
      'engine': 'tesseract 5.5.0 stand-in (native ONNX cannot run in the VM)',
      'truth_classes_total': truthTotal,
      'parsed_rows_total': parsedTotal,
      'matched_total': matchedTotal,
      'recall_micro': _r(recall),
      'precision_micro': _r(precision),
      'f1_micro': _r(f1),
      'subject_exact_total': exactTotal,
      'subject_exact_rate': matchedTotal == 0
          ? null
          : _r(exactTotal / matchedTotal),
      'subject_sim_macro': simN == 0 ? null : _r(simSum / simN),
      'recognize_calls_total': callsTotal,
    };
  });
}

// ---------------- Final selection (mirrors the import screen) ---------------

List<_Row> _finalRows(
  List<ParsedTimetableRow> gridRows,
  bool gridSuspicious,
  String text,
) {
  if (gridRows.isNotEmpty && !gridSuspicious) {
    return [
      for (final r in gridRows)
        _Row(r.subject, r.day, r.startMinutes, r.endMinutes, r.room,
            r.professor),
    ];
  }
  if (gridRows.isNotEmpty) {
    // Weak-grid rescue, scored exactly like the screen: the text candidate
    // only wins when it parses more on the shared ParseChain scale.
    if (text.isEmpty) {
      return [
        for (final r in gridRows)
          _Row(r.subject, r.day, r.startMinutes, r.endMinutes, r.room,
              r.professor),
      ];
    }
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
    final textScore = ParseChain.score(text, 0);
    if (textScore <= gridScore) {
      return [
        for (final r in gridRows)
          _Row(r.subject, r.day, r.startMinutes, r.endMinutes, r.room,
              r.professor),
      ];
    }
  }
  final hasWeekdayHeaders =
      RegExp(
        r'\b(?:MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|FRI(?:DAY)?)\b',
        caseSensitive: false,
      ).allMatches(text).length >=
      2;
  final chain = ParseChain.parse(text);
  final sectioned = chain.sectioned;
  if (sectioned.isNotEmpty) {
    return [
      for (final r in sectioned)
        _Row(r.subject, r.day, r.startMinutes, r.endMinutes, r.room,
            r.professor),
    ];
  }
  final listRows = TimetableParser.parse(text);
  final chosen = hasWeekdayHeaders && listRows.isNotEmpty
      ? listRows
      : chain.list;
  return [
    for (final r in chosen)
      _Row(r.subject, r.day, r.startMinutes, r.endMinutes, r.room, r.professor),
  ];
}

// ---------------- Ground-truth model + matching -----------------------------

class _TruthClass {
  const _TruthClass({
    required this.subject,
    required this.day,
    required this.start,
    required this.end,
    this.room,
    this.professor,
  });

  final String subject;
  final int day;
  final int start;
  final int end;

  /// COR fixtures also label the room and faculty cells; bench4 photos do
  /// not, so both are null there and the field checks report null.
  final String? room;
  final String? professor;
}

class _Row {
  const _Row(
    this.subject,
    this.day,
    this.startMinutes,
    this.endMinutes,
    this.room,
    this.professor,
  );

  final String subject;
  final int day;
  final int startMinutes;
  final int endMinutes;
  final String room;
  final String professor;
}

class _Match {
  const _Match(this.truthIndex, this.rowIndex, this.score);

  final int truthIndex;
  final int rowIndex;
  final double score;
}

/// Greedy 1-to-1 matching: day equal + interval overlap + subject similarity.
List<_Match> _matchGreedy(List<_TruthClass> truth, List<_Row> rows) {
  final candidates = <_Match>[];
  for (var t = 0; t < truth.length; t++) {
    for (var r = 0; r < rows.length; r++) {
      if (truth[t].day != rows[r].day) continue;
      final overlaps =
          truth[t].start < rows[r].endMinutes &&
          rows[r].startMinutes < truth[t].end;
      if (!overlaps) continue;
      final score = _similarity(truth[t].subject, rows[r].subject);
      if (score >= 0.34) candidates.add(_Match(t, r, score));
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final usedT = <int>{};
  final usedR = <int>{};
  final matches = <_Match>[];
  for (final c in candidates) {
    if (usedT.contains(c.truthIndex) || usedR.contains(c.rowIndex)) continue;
    usedT.add(c.truthIndex);
    usedR.add(c.rowIndex);
    matches.add(c);
  }
  return matches;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double _similarity(String a, String b) {
  final x = _norm(a);
  final y = _norm(b);
  if (x.isEmpty && y.isEmpty) return 1.0;
  final longest = math.max(x.length, y.length);
  if (longest == 0) return 1.0;
  return 1.0 - _levenshtein(x, y) / longest;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = math.min(
        math.min(curr[j] + 1, prev[j + 1] + 1),
        prev[j] + cost,
      );
    }
    final swap = prev;
    prev = curr;
    curr = swap;
  }
  return prev[b.length];
}

int _dayIndex(String name) {
  final key = name.toLowerCase().trim();
  const days = {
    'mon': 1,
    'monday': 1,
    'tue': 2,
    'tues': 2,
    'tuesday': 2,
    'wed': 3,
    'weds': 3,
    'wednesday': 3,
    'thu': 4,
    'thur': 4,
    'thurs': 4,
    'thursday': 4,
    'fri': 5,
    'friday': 5,
    'sat': 6,
    'saturday': 6,
    'sun': 7,
    'sunday': 7,
  };
  return days[key] ?? 0;
}

int _minutes(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.parse(parts[0]);
  final m = parts.length > 1 ? int.parse(parts[1]) : 0;
  return h * 60 + m;
}

String _hhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

double _r(double value) => (value * 1000).roundToDouble() / 1000;

// ---------------- Tesseract stand-in (bench5 pattern) -----------------------

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
      // (mirrors bench3/bench5's per-line reconstruction).
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
