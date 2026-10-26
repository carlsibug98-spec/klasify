import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/pdf_page_image.dart';
import 'package:pdfrx/pdfrx.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int readUint32(List<int> bytes, int offset) {
    return (bytes[offset] << 24) +
        (bytes[offset + 1] << 16) +
        (bytes[offset + 2] << 8) +
        bytes[offset + 3];
  }

  test('encodePdfImagePng writes a PNG header with the raster dimensions', () async {
    final raster = PdfImage.createFromBgraData(
      Uint8List.fromList(List.filled(2 * 3 * 4, 0xff)),
      width: 2,
      height: 3,
    );
    final png = await encodePdfImagePng(raster);

    expect(
      png.sublist(0, 8),
      const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    );
    // IHDR holds the big-endian width at offset 16 and height at offset 20.
    expect(readUint32(png, 16), 2);
    expect(readUint32(png, 20), 3);
    expect(png.length, greaterThan(30));
  });

  test('encodePdfImagePng preserves BGRA pixel order through the PNG roundtrip', () async {
    // BGRA order: blue 0x20, green 0x40, red 0x80, alpha 0xff.
    final raster = PdfImage.createFromBgraData(
      Uint8List.fromList(const [0x20, 0x40, 0x80, 0xff]),
      width: 1,
      height: 1,
    );
    final png = await encodePdfImagePng(raster);

    final buffer = await ui.ImmutableBuffer.fromUint8List(png);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final rgba = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    codec.dispose();
    descriptor.dispose();
    expect(rgba, isNotNull);
    final pixels = rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
    // RGBA order returned by the decoder: red, green, blue, alpha.
    expect(pixels, [0x80, 0x40, 0x20, 0xff]);
  });
}
