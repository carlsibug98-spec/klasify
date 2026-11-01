// ignore_for_file: avoid_relative_lib_imports
// Round-11 diagnosis: dump the parsed rows for one gen fixture so the
// failing room/professor fields can be compared with truth.
// Usage: dart run tool/cor_harness/bin/round11_diag.dart <truth.json> <fixture> <image>
import 'dart:convert';
import 'dart:io';

import '../lib/standin.dart';
import '../../../lib/features/schedule_import/utils/parse_chain.dart';
import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';

void main(List<String> args) {
  final truthAll =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final fixture = args[1];
  final path = args[2];
  final regions = tesseractRegions(path);
  final text = joinOcrRegions(regions);
  final normalized = normalizeOcrTokens(text);
  if (args.length > 3 && args[3] == '--raw') {
    stdout.writeln('=== raw OCR lines ===');
    final sorted = [...regions]..sort((a, b) => a.top.compareTo(b.top));
    for (final r in sorted) {
      stdout.writeln('  y=${r.top.round()}..${r.bottom.round()} '
          'x=${r.left.round()}..${r.right.round()} '
          'conf=${(r.confidence * 100).round()} ${r.text}');
    }
    stdout.writeln('=== joined+normalized text ===');
    for (final line in normalized.split('\n')) {
      stdout.writeln('  | $line');
    }
    return;
  }
  final sectioned = ParseChain.sectionedRows(normalized);
  stdout.writeln('=== truth ($fixture) ===');
  for (final c in (truthAll[fixture]['truth_classes'] as List)) {
    stdout.writeln('  ${c['subject']} | ${c['day']} | ${c['start']}-${c['end']}'
        ' | room=${c['room']} | prof=${c['professor']}');
  }
  stdout.writeln('=== parsed (${sectioned.length} rows) ===');
  for (final r in sectioned) {
    stdout.writeln('  ${r.subject} | ${r.day} | ${r.startMinutes}-${r.endMinutes}'
        ' | room=${r.room} | prof=${r.professor}');
  }
}
