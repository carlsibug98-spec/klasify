import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart' as pdfrx;

/// Encodes a rendered PDF page ([pdfrx.PdfImage], BGRA8888 raw pixels) into
/// PNG bytes and disposes the rendered raster.
///
/// pdfrx renders pages as raw BGRA buffers, while the on-device OCR pipeline
/// and the grid scanner consume image files, so the raster of every scanned
/// PDF page is wrapped in a PNG container here.
Future<Uint8List> encodePdfImagePng(pdfrx.PdfImage image) async {
  ui.Image? decoded;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(image.pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.bgra8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    decoded = frame.image;
    final data = await decoded.toByteData(format: ui.ImageByteFormat.png);
    codec.dispose();
    descriptor.dispose();
    if (data == null) {
      throw StateError('PDF page PNG encoding produced no data');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    decoded?.dispose();
    image.dispose();
  }
}
