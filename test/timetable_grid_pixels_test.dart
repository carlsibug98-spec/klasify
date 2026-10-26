import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/timetable_grid_pixels.dart';

Uint8List _image(int width, int height, int gray, {int alpha = 255}) {
  final pixels = Uint8List(width * height * 4);
  for (var offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = gray;
    pixels[offset + 1] = gray;
    pixels[offset + 2] = gray;
    pixels[offset + 3] = alpha;
  }
  return pixels;
}

void main() {
  test('finds a line by local contrast on a gray photo background', () {
    const width = 40;
    const height = 40;
    final pixels = _image(width, height, 240);
    for (var x = 0; x < width; x++) {
      final offset = (20 * width + x) * 4;
      pixels[offset] = 220;
      pixels[offset + 1] = 220;
      pixels[offset + 2] = 220;
    }

    expect(normalizeGridPixels(pixels), isFalse);
    expect(
      horizontalGridRuleRows(
        pixels,
        width: width,
        height: height,
        left: 0,
        right: width,
      ),
      [20],
    );
  });

  test('composites transparent pixels and normalizes dark backgrounds', () {
    const width = 40;
    const height = 40;
    final transparent = _image(width, height, 0, alpha: 0);
    normalizeGridPixels(transparent);
    expect(isDarkGridPixel(transparent, width, 10, 10), isFalse);
    expect(
      horizontalGridRuleRows(
        transparent,
        width: width,
        height: height,
        left: 0,
        right: width,
      ),
      isEmpty,
    );

    final dark = _image(width, height, 20);
    for (var x = 0; x < width; x++) {
      final offset = (20 * width + x) * 4;
      dark[offset] = 230;
      dark[offset + 1] = 230;
      dark[offset + 2] = 230;
    }
    expect(normalizeGridPixels(dark), isTrue);
    expect(
      horizontalGridRuleRows(
        dark,
        width: width,
        height: height,
        left: 0,
        right: width,
      ),
      [20],
    );
  });

  test('does not treat a flat tinted background as grid rules', () {
    const width = 40;
    const height = 40;
    final pixels = _image(width, height, 240);
    normalizeGridPixels(pixels);
    expect(
      horizontalGridRuleRows(
        pixels,
        width: width,
        height: height,
        left: 0,
        right: width,
      ),
      isEmpty,
    );
  });
}
