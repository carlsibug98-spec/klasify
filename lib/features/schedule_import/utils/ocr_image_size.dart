import 'dart:math' as math;

const maxOcrRasterSide = 3200;

({int width, int height}) ocrRasterSize(int width, int height) {
  if (width < 1 || height < 1) throw ArgumentError('Invalid image dimensions.');
  final scale = math.min(1.0, maxOcrRasterSide / math.max(width, height));
  return (
    width: math.max(1, (width * scale).round()).toInt(),
    height: math.max(1, (height * scale).round()).toInt(),
  );
}
