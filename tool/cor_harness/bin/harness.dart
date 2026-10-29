/// COR benchmark harness: runs the REAL Klasify parser chain on REAL
/// tesseract output for the 6-sample COR fixture set and prints the bench
/// metrics. Mirrors the bench5/bench6/bench7 flutter-test pipeline minus the
/// grid stage (a COR has no weekday header band, so the grid scanner bails
/// and the text cascade owns the page - the flutter benches verify that).
library;

import 'dart:convert';
import 'dart:io';

import '../lib/standin.dart';
import '../lib/score.dart';
// The REAL app parser chain, imported straight from lib/.
import '../../../lib/features/schedule_import/utils/parse_chain.dart';
import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';

const fixturesDir = 'test/fixtures/cor';
const fixtures = [
  'cor_registry_clean.png',
  'cor_labs_online.png',
  'cor_phone_skewed.jpg',
  'cor_phone_blurred.png',
  'cor_lowres.png',
  'cor_dim_noise.png',
];

/// Optional override: fixture name -> full path of a pre-prepared variant to
/// OCR instead (emulates what an added preprocessor rescue pass would feed
/// the engine). Values are full paths so the canonical fixture directory
/// keeps only the six source images.
const rescueVariants = <String, String>{
  'cor_phone_blurred.png':
      '/home/z/my-project/scripts/rescue/cor_phone_blurred.rescued.png',
};

void main(List<String> args) {
  final dump = args.contains('--dump');
  final truth = jsonDecode(
    File('test/fixtures/cor_truth.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  var truthTotal = 0;
  var parsedTotal = 0;
  var matchedTotal = 0;
  var exactTotal = 0;
  var dayOkTotal = 0;
  var startOkTotal = 0;
  var endOkTotal = 0;
  var roomOkTotal = 0;
  var profOkTotal = 0;
  var fpTotal = 0;
  var missedTotal = 0;

  for (final name in fixtures) {
    final path = rescueVariants.containsKey(name)
        ? rescueVariants[name]!
        : '$fixturesDir/$name';
    final regions = tesseractRegions(path);
    final text = joinOcrRegions(regions);
    final confidences = regions
        .map((region) => region.confidence.clamp(0.0, 1.0).toDouble())
        .toList();
    final meanConfidence = confidences.isEmpty
        ? 0.0
        : confidences.reduce((a, b) => a + b) / confidences.length;

    // Exactly what the service returns to the review screen.
    final normalized = normalizeOcrTokens(text);
    final sectioned = ParseChain.sectionedRows(normalized);
    final rows = [
      for (final r in sectioned)
        ParsedRow(
          r.subject,
          r.day,
          r.startMinutes,
          r.endMinutes,
          r.room,
          r.professor,
        ),
    ];

    final classes = [
      for (final c in (truth[name]['truth_classes'] as List))
        TruthClass(
          subject: c['subject'] as String,
          day: dayIndex(c['day'] as String),
          start: minutes(c['start'] as String),
          end: minutes(c['end'] as String),
          room: c['room'] as String,
          professor: c['professor'] as String,
        ),
    ];

    final matches = matchGreedy(classes, rows);
    var exact = 0;
    var dayOk = 0;
    var startOk = 0;
    var endOk = 0;
    var roomOk = 0;
    var profOk = 0;
    final pairs = <String>[];
    for (final m in matches) {
      final t = classes[m.truthIndex];
      final r = rows[m.rowIndex];
      final sim = similarity(t.subject, r.subject);
      if (sim > 0.999) exact++;
      if (t.day == r.day) dayOk++;
      if (t.start == r.startMinutes) startOk++;
      if (t.end == r.endMinutes) endOk++;
      if (norm(t.room) == norm(r.room) && norm(t.room).isNotEmpty) roomOk++;
      if (similarity(t.professor, r.professor) >= 0.85) profOk++;
      pairs.add('${t.subject} <-> ${r.subject}');
    }
    final n = matches.length;
    final recall = classes.isEmpty ? 1.0 : n / classes.length;
    final precision = rows.isEmpty ? 1.0 : n / rows.length;
    final f1 = (recall + precision) == 0
        ? 0.0
        : 2 * recall * precision / (recall + precision);

    truthTotal += classes.length;
    parsedTotal += rows.length;
    matchedTotal += n;
    exactTotal += exact;
    dayOkTotal += dayOk;
    startOkTotal += startOk;
    endOkTotal += endOk;
    roomOkTotal += roomOk;
    profOkTotal += profOk;
    fpTotal += rows.length - n;
    missedTotal += classes.length - n;

    stdout.writeln(
      '$name: truth=${classes.length} parsed=${rows.length} matched=$n '
      'recall=${r3(recall)} precision=${r3(precision)} f1=${r3(f1)} '
      'exact=$exact day=$dayOk start=$startOk end=$endOk '
      'room=$roomOk prof=$profOk fp=${rows.length - n} '
      'missed=${classes.length - n}',
    );
    if (dump) {
      for (final pair in pairs) {
        stdout.writeln('    $pair');
      }
      stdout.writeln('    -- parsed rows:');
      for (final r in rows) {
        stdout.writeln(
          '       ${r.subject} | day=${r.day} | ${r.startMinutes}-${r.endMinutes}'
          ' | room="${r.room}" | prof="${r.professor}"',
        );
      }
      stdout.writeln('    -- joined text (first 40 lines):');
      var i = 0;
      for (final line in normalized.split('\n')) {
        if (i++ > 40) break;
        stdout.writeln('       > $line');
      }
    }
  }

  final recall = truthTotal == 0 ? 1.0 : matchedTotal / truthTotal;
  final precision = parsedTotal == 0 ? 1.0 : matchedTotal / parsedTotal;
  final f1 = (recall + precision) == 0
      ? 0.0
      : 2 * recall * precision / (recall + precision);
  stdout.writeln('---');
  stdout.writeln(
    'TOTAL: truth=$truthTotal parsed=$parsedTotal matched=$matchedTotal '
    'recall=${r3(recall)} precision=${r3(precision)} f1=${r3(f1)} '
    'exact=$exactTotal day=$dayOkTotal start=$startOkTotal end=$endOkTotal '
    'room=$roomOkTotal prof=$profOkTotal fp=$fpTotal missed=$missedTotal',
  );
}
