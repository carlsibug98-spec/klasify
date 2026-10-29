// Single-fixture scorer for round-8 sweeps: scores one COR fixture (or a
// generated variant of it) against its ground truth using the same chain as
// the full harness (tesseract stand-in -> band join -> normalize ->
// sectioned parser -> greedy match).
//
// Usage:
//   dart run tool/cor_harness/bin/score_one.dart cor_phone_skewed.jpg
//   dart run tool/cor_harness/bin/score_one.dart cor_phone_skewed.jpg \
//       test/fixtures/cor/sweep_skew_r-6.0.png
import 'dart:convert';
import 'dart:io';

import '../lib/standin.dart';
import '../lib/score.dart';
import '../../../lib/features/schedule_import/utils/parse_chain.dart';
import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';

void main(List<String> args) {
  final fixture = args[0];
  final path = args.length > 1 ? args[1] : 'test/fixtures/cor/$fixture';
  final truth = jsonDecode(
    File('test/fixtures/cor_truth.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final regions = tesseractRegions(path);
  final text = joinOcrRegions(regions);
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
    for (final c in (truth[fixture]['truth_classes'] as List))
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
  var roomOk = 0;
  var profOk = 0;
  for (final m in matches) {
    if (similarity(classes[m.truthIndex].room, rows[m.rowIndex].room) >= .5) {
      roomOk++;
    }
    if (similarity(
          classes[m.truthIndex].professor,
          rows[m.rowIndex].professor,
        ) >=
        .5) {
      profOk++;
    }
  }
  stdout.writeln(
    '$fixture matched=${matches.length}/${classes.length} '
    'parsed=${rows.length} room=$roomOk prof=$profOk',
  );
}
