import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/ocr_image_size.dart';

void main() {
  test('caps decoded raster dimensions while preserving aspect ratio', () {
    expect(ocrRasterSize(8000, 6000), (width: 3200, height: 2400));
    expect(ocrRasterSize(1000, 1600), (width: 1000, height: 1600));
  });
}
