import 'dart:convert';
import 'dart:io';
import '../lib/standin.dart';
import '../../../lib/features/schedule_import/utils/domain_rescoring.dart';

/// Dump raw OCR lines sorted top-to-bottom so we can see what the OCR saw
/// around a missing row.
void main(List<String> args) {
  final path = args[0];
  final needle = args.length > 1 ? args[1] : '';
  final regions = tesseractRegions(path);
  regions.sort((a, b) => a.top.compareTo(b.top));
  for (final r in regions) {
    final line = r.text;
    final hit = needle.isEmpty || line.toLowerCase().contains(needle.toLowerCase());
    stdout.writeln(
        'y=${r.top.round().toString().padLeft(5)}..${r.bottom.round().toString().padLeft(5)} '
        'conf=${(r.confidence * 100).toStringAsFixed(0).padLeft(3)} '
        '${hit ? ">>" : "  "} $line');
  }
}
