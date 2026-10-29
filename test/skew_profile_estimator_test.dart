import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/skew_profile_estimator.dart';

/// Builds a synthetic "document" as an enhanced grayscale buffer: dark text
/// bands on bright paper. [tiltDegrees] is the angle that created the tilt,
/// PIL convention (positive = counter-clockwise as displayed, lifting the
/// right end of each line); the estimator under test must return its
/// negation, the leveling angle.
Uint8List _syntheticPage({
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
        // Dashed band: short runs of ink separated by small gaps, so the
        // profile reads text-like edges rather than one long rule.
        if ((x ~/ 14).isOdd) continue;
        gray[y * width + x] = 40;
      }
    }
  }
  return gray;
}

void main() {
  group('estimateSkewProfile', () {
    test('straight page is reported as none and never rescues', () {
      final estimate = estimateSkewProfile(
        gray: _syntheticPage(width: 900, height: 700, tiltDegrees: 0),
        width: 900,
        height: 700,
      );
      expect(estimate.degrees.abs(), lessThan(0.5));
      expect(estimate.prominence, lessThan(0.10));
      expect(estimate.shouldRescue, isFalse);
    });

    test('clockwise-tilted page gets a counter-clockwise correction', () {
      // tiltDegrees is the angle that CREATED the tilt (PIL convention, so
      // -4.5 tilts lines down to the right). The estimator reports the
      // leveling angle: the opposite sign.
      final estimate = estimateSkewProfile(
        gray: _syntheticPage(width: 900, height: 700, tiltDegrees: -4.5),
        width: 900,
        height: 700,
      );
      expect(estimate.degrees, closeTo(4.5, 0.5));
      expect(estimate.shouldRescue, isTrue);
    });

    test('counter-clockwise tilt gets the mirrored correction', () {
      final estimate = estimateSkewProfile(
        gray: _syntheticPage(width: 900, height: 700, tiltDegrees: 6.0),
        width: 900,
        height: 700,
      );
      expect(estimate.degrees, closeTo(-6.0, 0.5));
      expect(estimate.shouldRescue, isTrue);
    });

    test('tiny buffers bail out without estimating', () {
      final estimate = estimateSkewProfile(
        gray: Uint8List(64 * 64),
        width: 64,
        height: 64,
      );
      expect(estimate.degrees, 0);
      expect(estimate.shouldRescue, isFalse);
    });
  });

  group('rotateRgbaBuffer', () {
    test('rotating by the estimate levels the page', () {
      const width = 900;
      const height = 700;
      final gray = _syntheticPage(
        width: width,
        height: height,
        tiltDegrees: -4.5,
      );
      final estimate = estimateSkewProfile(
        gray: gray,
        width: width,
        height: height,
      );

      final rgba = Uint8List(width * height * 4);
      for (var pixel = 0; pixel < width * height; pixel++) {
        final value = gray[pixel];
        final offset = pixel * 4;
        rgba[offset] = value;
        rgba[offset + 1] = value;
        rgba[offset + 2] = value;
        rgba[offset + 3] = 255;
      }
      final rotated = rotateRgbaBuffer(rgba, width, height, estimate.degrees);
      expect(rotated.length, rgba.length);

      final rotatedGray = Uint8List(width * height);
      for (var pixel = 0; pixel < width * height; pixel++) {
        rotatedGray[pixel] = rotated[pixel * 4];
      }
      final residual = estimateSkewProfile(
        gray: rotatedGray,
        width: width,
        height: height,
      );
      expect(residual.degrees.abs(), lessThan(0.5));
      expect(residual.shouldRescue, isFalse);
    });

    test('zero degrees copies the buffer', () {
      final rgba = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final rotated = rotateRgbaBuffer(rgba, 2, 1, 0);
      expect(rotated, rgba);
    });
  });
}
