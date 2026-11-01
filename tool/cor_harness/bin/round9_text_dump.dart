// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import '../lib/standin.dart';
import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';
import '../../../lib/features/schedule_import/utils/cor_schedule_parser.dart';

/// Print the banded OCR text exactly as ParseChain hands it to the COR
/// parser, plus whether looksLikeCor fires and what parse() returns.
void main(List<String> args) {
  final fixture = args[0];
  final variant = args.length > 1 ? args[1] : null;
  final path = variant != null
      ? 'test/fixtures/cor/$variant'
      : 'test/fixtures/cor/$fixture';
  final regions = tesseractRegions(path);
  final text = joinOcrRegions(regions);
  final normalized = normalizeOcrTokens(text);
  stdout.writeln('--- banded text (normalizeOcrTokens) ---');
  var i = 0;
  for (final line in normalized.split('\n')) {
    i++;
    stdout.writeln('${i.toString().padLeft(3)}| $line');
  }
  stdout.writeln('--- looksLikeCor: ${CorScheduleParser.looksLikeCor(normalized)}');
  final rows = CorScheduleParser.parse(normalized);
  stdout.writeln('--- cor rows: ${rows.length}');
  for (final r in rows) {
    String mm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    stdout.writeln(
        '  day=${r.day} ${mm(r.startMinutes)}-${mm(r.endMinutes)} ${r.subject} | room=${r.room} | prof=${r.professor}');
  }
}
