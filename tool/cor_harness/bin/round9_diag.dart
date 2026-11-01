// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';
import '../lib/standin.dart';
import '../lib/score.dart';
import '../../../lib/features/schedule_import/utils/parse_chain.dart';
import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';

/// Round-9 diagnostics: dump parsed rows for a fixture and show which truth
/// classes match, which don't, and why.
void main(List<String> args) {
  final fixture = args[0]; // e.g. cor_phone_skewed.jpg
  final variant = args.length > 1 ? args[1] : null; // optional rescue variant
  final path = variant != null
      ? 'test/fixtures/cor/$variant'
      : 'test/fixtures/cor/$fixture';
  final truth = jsonDecode(
    File('test/fixtures/cor_truth.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final regions = tesseractRegions(path);
  final text = joinOcrRegions(regions);
  final normalized = normalizeOcrTokens(text);
  final sectioned = ParseChain.sectionedRows(normalized);
  final rows = [
    for (final r in sectioned)
      ParsedRow(r.subject, r.day, r.startMinutes, r.endMinutes, r.room, r.professor),
  ];

  stdout.writeln('--- parsed rows (${rows.length}) for $fixture ---');
  for (final r in rows) {
    String mm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    stdout.writeln(
        '${r.day} ${mm(r.startMinutes)}-${mm(r.endMinutes)} ${r.subject} | room=${r.room} | prof=${r.professor}');
  }

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
  final matchedT = matches.map((m) => m.truthIndex).toSet();
  stdout.writeln('--- unmatched truth ---');
  for (var i = 0; i < classes.length; i++) {
    if (matchedT.contains(i)) continue;
    final c = classes[i];
    String mm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    stdout.writeln(
        '${c.day} ${mm(c.start)}-${mm(c.end)} ${c.subject} | room=${c.room} | prof=${c.professor}');
    // find nearest candidate rows on same day for hint
    for (final r in rows) {
      if (r.day != c.day) continue;
      final sim = similarity(c.subject, r.subject);
      if (sim > 0.15) {
        stdout.writeln('    candidate: day=${r.day} ${mm(r.startMinutes)}-${mm(r.endMinutes)} '
            'sim=${sim.toStringAsFixed(2)} "${r.subject}"');
      }
    }
  }
  stdout.writeln('matched=${matches.length}/${classes.length}');
}
