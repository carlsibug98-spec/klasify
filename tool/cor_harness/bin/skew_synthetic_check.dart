// Synthetic check mirroring test/skew_profile_estimator_test.dart without
// the flutter_test dependency, so the VM can verify the assertions the CI
// test will make.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../lib/features/schedule_import/utils/skew_profile_estimator.dart';

Uint8List syntheticPage({
  required int width,
  required int height,
  required double tiltDegrees,
}) {
  final gray = Uint8List(width * height)
    ..fillRange(0, width * height, 235);
  final drift = -math.tan(tiltDegrees * math.pi / 180);
  for (var band = 0; band < 16; band++) {
    final base = 120.0 + band * 32.0;
    for (var x = 40; x < width - 40; x++) {
      final center = base + drift * (x - width / 2);
      final top = center.round();
      for (var y = top; y < top + 7; y++) {
        if (y < 0 || y >= height) continue;
        if ((x ~/ 14).isOdd) continue;
        gray[y * width + x] = 40;
      }
    }
  }
  return gray;
}

void expectNear(num value, num target, num tolerance, String label) {
  final ok = (value - target).abs() <= tolerance;
  stdout.writeln(
    '$label: $value (expected $target +- $tolerance) ${ok ? 'OK' : 'FAIL'}',
  );
  if (!ok) exitCode = 1;
}

void main() {
  final straight = estimateSkewProfile(
    gray: syntheticPage(width: 900, height: 700, tiltDegrees: 0),
    width: 900,
    height: 700,
  );
  expectNear(straight.degrees, 0, 0.5, 'straight degrees');
  expectNear(straight.prominence, 0, 0.10, 'straight prominence');

  final ccw = estimateSkewProfile(
    gray: syntheticPage(width: 900, height: 700, tiltDegrees: -4.5),
    width: 900,
    height: 700,
  );
  expectNear(ccw.degrees, 4.5, 0.5, 'cw-tilted page -> +4.5 correction');
  stdout.writeln('ccw shouldRescue=${ccw.shouldRescue}');
  if (!ccw.shouldRescue) exitCode = 1;

  final cw = estimateSkewProfile(
    gray: syntheticPage(width: 900, height: 700, tiltDegrees: 6.0),
    width: 900,
    height: 700,
  );
  expectNear(cw.degrees, -6.0, 0.5, 'ccw-tilted page -> -6.0 correction');

  final tiny = estimateSkewProfile(
    gray: Uint8List(64 * 64),
    width: 64,
    height: 64,
  );
  expectNear(tiny.degrees, 0, 0, 'tiny degrees');

  // rotate-by-estimate levels the page
  const width = 900;
  const height = 700;
  final gray = syntheticPage(width: width, height: height, tiltDegrees: -4.5);
  final rgba = Uint8List(width * height * 4);
  for (var pixel = 0; pixel < width * height; pixel++) {
    final value = gray[pixel];
    final offset = pixel * 4;
    rgba[offset] = value;
    rgba[offset + 1] = value;
    rgba[offset + 2] = value;
    rgba[offset + 3] = 255;
  }
  final rotated = rotateRgbaBuffer(rgba, width, height, ccw.degrees);
  final rotatedGray = Uint8List(width * height);
  for (var pixel = 0; pixel < width * height; pixel++) {
    rotatedGray[pixel] = rotated[pixel * 4];
  }
  final residual = estimateSkewProfile(
    gray: rotatedGray,
    width: width,
    height: height,
  );
  expectNear(residual.degrees, 0, 0.5, 'residual after rotate');
  stdout.writeln('residual shouldRescue=${residual.shouldRescue}');
  if (residual.shouldRescue) exitCode = 1;

  final copy = rotateRgbaBuffer(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      2, 1, 0);
  final same = copy.length == 8 && copy[0] == 1 && copy[7] == 8;
  stdout.writeln('zero-degree copy: ${same ? 'OK' : 'FAIL'}');
  if (!same) exitCode = 1;

  stdout.writeln(exitCode == 0 ? '\nAll synthetic checks passed.' : '\nFAILED');
}
