// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';
import 'dart:typed_data';

import '../../../lib/features/schedule_import/utils/ocr_resample.dart';

/// Round-10 VM probe: runs the production resample/unsharp code on raw
/// buffers so the harness measures exactly what the app will run.
///
///   `lanczos <in.bin> <w> <h> <dw> <dh> <out.bin>`   rgba -> rgba
///   `unsharp <in.bin> <w> <h> <out.bin>`             rgba -> rgba
void main(List<String> args) {
  final cmd = args[0];
  final sw = Stopwatch()..start();
  if (cmd == 'lanczos') {
    final rgba = File(args[1]).readAsBytesSync();
    final w = int.parse(args[2]);
    final h = int.parse(args[3]);
    final dw = int.parse(args[4]);
    final dh = int.parse(args[5]);
    final out = lanczosResizeRgba(
      Uint8List.fromList(rgba),
      w,
      h,
      dw,
      dh,
    );
    File(args[6]).writeAsBytesSync(out);
    stdout.writeln('lanczos ${w}x$h -> ${dw}x$dh in ${sw.elapsedMilliseconds} ms');
  } else if (cmd == 'unsharp') {
    final rgba = File(args[1]).readAsBytesSync();
    final w = int.parse(args[2]);
    final h = int.parse(args[3]);
    final sigma = args.length > 5 ? double.parse(args[5]) : 2.0;
    final percent = args.length > 6 ? double.parse(args[6]) : 35.0;
    final threshold = args.length > 7 ? double.parse(args[7]) : 2.0;
    final out = softUnsharpRgba(
      Uint8List.fromList(rgba),
      w,
      h,
      sigma: sigma,
      percent: percent,
      threshold: threshold,
    );
    File(args[4]).writeAsBytesSync(out);
    stdout.writeln(
        'unsharp ${w}x$h sigma=$sigma pct=$percent thr=$threshold in ${sw.elapsedMilliseconds} ms');
  } else {
    stderr.writeln('unknown command $cmd');
    exit(2);
  }
}
