// Round-11 generalization audit: production-faithful multi-candidate scorer.
//
// Takes a truth file + fixture key + one or more candidate images (the pass
// variants the scan cascade would produce), runs each through the REAL chain
// (tesseract stand-in -> band join -> normalize), selects the winner exactly
// like ScheduleOcrService does (ParseChain.score, best first), then scores
// the winner against ground truth with the bench6 matcher.
//
// Usage (from klasify-cor-extracted/):
//   dart run tool/cor_harness/bin/cascade_score.dart \
//       test/fixtures/cor_truth_gen.json cor_gen_shadow.png \
//       /tmp/v_raw.png /tmp/v_enh.png ...
//
// Prints one JSON object:
//   { fixture, candidates: [{label, path, score, conf, sectioned, list}],
//     best: <path>, metrics: {recall, precision, f1, matched, truth, rows,
//     room_ok, prof_ok, fp, missed} }
import 'dart:convert';
import 'dart:io';

import '../lib/standin.dart';
import '../lib/score.dart';
import '../../../lib/features/schedule_import/utils/parse_chain.dart';
import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';

void main(List<String> args) {
  final truthPath = args[0];
  final fixture = args[1];
  final paths = args.sublist(2);

  final truthAll = jsonDecode(File(truthPath).readAsStringSync())
      as Map<String, dynamic>;
  final entry = truthAll[fixture];
  if (entry == null) {
    stderr.writeln('no truth for fixture $fixture');
    exit(2);
  }
  final hasCorFields = (entry['truth_classes'] as List)
      .any((c) => c['room'] != null || c['professor'] != null);

  final classes = [
    for (final c in (entry['truth_classes'] as List))
      TruthClass(
        subject: c['subject'] as String,
        day: dayIndex(c['day'] as String),
        start: minutes(c['start'] as String),
        end: minutes(c['end'] as String),
        room: (c['room'] as String?) ?? '',
        professor: (c['professor'] as String?) ?? '',
      ),
  ];

  final candidates = <Map<String, dynamic>>[];
  for (var i = 0; i < paths.length; i++) {
    final path = paths[i];
    if (!File(path).existsSync()) {
      stderr.writeln('missing candidate: $path');
      exit(2);
    }
    final regions = tesseractRegions(path);
    final drift = regionColumnDrift(regions);
    final text = joinOcrRegions(regions);
    final confidences = regions
        .map((r) => r.confidence.clamp(0.0, 1.0).toDouble())
        .toList();
    final meanConfidence = confidences.isEmpty
        ? 0.0
        : confidences.reduce((a, b) => a + b) / confidences.length;
    final chain = ParseChain.parse(text);
    final score = ParseChain.score(text, meanConfidence);

    // Per-candidate truth metrics, so the caller can emulate the
    // production early-stop trajectory without re-running the engine.
    final normalizedC = normalizeOcrTokens(text);
    final sectionedC = ParseChain.sectionedRows(normalizedC);
    final rowsC = [
      for (final r in sectionedC)
        ParsedRow(r.subject, r.day, r.startMinutes, r.endMinutes, r.room,
            r.professor),
    ];
    final matchesC = matchGreedy(classes, rowsC);
    var roomOkC = 0;
    var profOkC = 0;
    for (final m in matchesC) {
      if (hasCorFields &&
          fieldOk(classes[m.truthIndex].room, rowsC[m.rowIndex].room)) {
        roomOkC++;
      }
      if (hasCorFields &&
          fieldOk(classes[m.truthIndex].professor,
              rowsC[m.rowIndex].professor)) {
        profOkC++;
      }
    }
    final recallC = classes.isEmpty ? 0.0 : matchesC.length / classes.length;
    final precisionC = rowsC.isEmpty ? 0.0 : matchesC.length / rowsC.length;
    final f1C = recallC + precisionC == 0
        ? 0.0
        : 2 * recallC * precisionC / (recallC + precisionC);

    candidates.add({
      'label': i == 0 ? 'raw' : path.split('/').last.replaceAll('.png', ''),
      'path': path,
      'score': (score * 1000).roundToDouble() / 1000,
      'conf': (meanConfidence * 1000).roundToDouble() / 1000,
      'sectioned': chain.sectioned.length,
      'list': chain.list.length,
      'matched': matchesC.length,
      'fp': rowsC.length - matchesC.length,
      'recall': (recallC * 1000).roundToDouble() / 1000,
      'precision': (precisionC * 1000).roundToDouble() / 1000,
      'f1': (f1C * 1000).roundToDouble() / 1000,
      'room_ok': hasCorFields ? roomOkC : null,
      'prof_ok': hasCorFields ? profOkC : null,
      'drift': (drift.drift * 100).roundToDouble() / 100,
      'drift_fired': drift.fired,
      '_text': text,
      '_rows': rowsC,
    });
  }

  // Production selection: highest ParseChain.score wins (candidates sorted
  // by score descending, stable, first taken).
  candidates.sort((a, b) => (b['score'] as double).compareTo(a['score']));
  final best = candidates.first;
  final rows = best['_rows'] as List<ParsedRow>;

  final matches = matchGreedy(classes, rows);
  var roomOk = 0;
  var profOk = 0;
  for (final m in matches) {
    if (hasCorFields &&
        fieldOk(classes[m.truthIndex].room, rows[m.rowIndex].room)) {
      roomOk++;
    }
    if (hasCorFields &&
        fieldOk(classes[m.truthIndex].professor,
            rows[m.rowIndex].professor)) {
      profOk++;
    }
  }

  final recall = classes.isEmpty ? 0.0 : matches.length / classes.length;
  final precision = rows.isEmpty ? 0.0 : matches.length / rows.length;
  final f1 = recall + precision == 0
      ? 0.0
      : 2 * recall * precision / (recall + precision);

  // Diagnostics: which truth classes were missed (first line of subject).
  final matchedT = matches.map((m) => m.truthIndex).toSet();
  final missed = <String>[
    for (var t = 0; t < classes.length; t++)
      if (!matchedT.contains(t))
        '${classes[t].subject} ${classes[t].day} '
            '${classes[t].start}-${classes[t].end}',
  ];

  for (final c in candidates) {
    c.remove('_text');
    c.remove('_rows');
  }

  // stdout.writeln(...) below; fieldOk is defined after main for clarity.

  stdout.writeln(jsonEncode({
    'fixture': fixture,
    'candidates': candidates,
    'best': best['path'],
    'metrics': {
      'truth': classes.length,
      'rows': rows.length,
      'matched': matches.length,
      'recall': (recall * 1000).roundToDouble() / 1000,
      'precision': (precision * 1000).roundToDouble() / 1000,
      'f1': (f1 * 1000).roundToDouble() / 1000,
      'room_ok': hasCorFields ? roomOk : null,
      'prof_ok': hasCorFields ? profOk : null,
      'fp': rows.length - matches.length,
      'missed': missed,
    },
  }));
}

/// Auxiliary-field check. A truth cell printed "tba" and a scan that left
/// the cell empty carry the same information (no assignment yet), so they
/// count as equivalent; everything else needs the usual 0.5 similarity.
bool fieldOk(String truth, String parsed) {
  final t = norm(truth);
  final p = norm(parsed);
  final truthOpen = t == 'tba' || t.isEmpty;
  final parsedOpen = p == 'tba' || p.isEmpty;
  if (truthOpen && parsedOpen) return true;
  return similarity(truth, parsed) >= 0.5;
}
