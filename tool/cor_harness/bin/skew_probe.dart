// ignore_for_file: avoid_relative_lib_imports
// Round-8 verification probe: runs the production skew estimator and RGBA
// rotation on real fixture data prepared by scripts/round8_probe_data.py.
//
// Usage (from klasify-cor-extracted/):
//   dart run tool/cor_harness/bin/skew_probe.dart estimate <gray.bin> <w> <h>
//   dart run tool/cor_harness/bin/skew_probe.dart rotate <rgba.bin> <w> <h> <degrees> <out.bin>
import 'dart:io';
import 'dart:typed_data';

import '../../../lib/features/schedule_import/utils/skew_profile_estimator.dart';

void main(List<String> args) {
  final mode = args[0];
  if (mode == 'estimate') {
    final gray = Uint8List.fromList(File(args[1]).readAsBytesSync());
    final width = int.parse(args[2]);
    final height = int.parse(args[3]);
    final estimate = estimateSkewProfile(
      gray: gray,
      width: width,
      height: height,
    );
    stdout.writeln(
      'dart degrees=${estimate.degrees.toStringAsFixed(2)} '
      'prominence=${estimate.prominence.toStringAsFixed(3)} '
      'shouldRescue=${estimate.shouldRescue}',
    );
  } else if (mode == 'rotate') {
    final rgba = Uint8List.fromList(File(args[1]).readAsBytesSync());
    final width = int.parse(args[2]);
    final height = int.parse(args[3]);
    final degrees = double.parse(args[4]);
    final stopwatch = Stopwatch()..start();
    final rotated = rotateRgbaBuffer(rgba, width, height, degrees);
    stopwatch.stop();
    File(args[5]).writeAsBytesSync(rotated);
    stdout.writeln(
      'rotated ${width}x$height by $degrees deg in '
      '${stopwatch.elapsedMilliseconds} ms',
    );
  } else {
    stderr.writeln('unknown mode: $mode');
    exitCode = 2;
  }
}
