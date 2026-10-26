import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/adaptive_ocr_threshold.dart';

void main() {
  test('thresholds dark text locally on a bright background', () {
    final rgba = Uint8List(8 * 8 * 4);
    for (var pixel = 0; pixel < 8 * 8; pixel++) {
      final offset = pixel * 4;
      rgba[offset] = 240;
      rgba[offset + 1] = 240;
      rgba[offset + 2] = 240;
      rgba[offset + 3] = 255;
    }
    final textOffset = (3 * 8 + 3) * 4;
    rgba[textOffset] = 30;

    final result = adaptiveThresholdRgba(
      rgba,
      8,
      8,
      blockSize: 8,
      thresholdOffset: 8,
    );

    expect(result[textOffset], 0);
    expect(result[(0 * 8 + 0) * 4], 255);
  });

  test('adapts to a darker background without turning it into foreground', () {
    final rgba = Uint8List(16 * 8 * 4);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 16; x++) {
        final value = x < 8 ? 240 : 120;
        final offset = (y * 16 + x) * 4;
        rgba[offset] = value;
        rgba[offset + 1] = value;
        rgba[offset + 2] = value;
        rgba[offset + 3] = 255;
      }
    }
    final textOffset = (3 * 16 + 11) * 4;
    rgba[textOffset] = 25;

    final result = adaptiveThresholdRgba(
      rgba,
      16,
      8,
      blockSize: 8,
      thresholdOffset: 8,
    );

    expect(result[textOffset], 0);
    expect(result[(3 * 16 + 12) * 4], 255);
    expect(result[(3 * 16 + 4) * 4], 255);
  });
}
