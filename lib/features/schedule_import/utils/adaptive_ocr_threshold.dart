import 'dart:typed_data';

Uint8List adaptiveThresholdRgba(
  Uint8List rgba,
  int width,
  int height, {
  int blockSize = 32,
  int thresholdOffset = 8,
}) {
  if (width < 1 ||
      height < 1 ||
      blockSize < 1 ||
      rgba.length != width * height * 4) {
    throw ArgumentError('Invalid image dimensions or pixel buffer.');
  }

  final columns = (width + blockSize - 1) ~/ blockSize;
  final rows = (height + blockSize - 1) ~/ blockSize;
  final means = Float64List(columns * rows);
  for (var blockY = 0; blockY < rows; blockY++) {
    final top = blockY * blockSize;
    final bottom = (top + blockSize).clamp(0, height);
    for (var blockX = 0; blockX < columns; blockX++) {
      final left = blockX * blockSize;
      final right = (left + blockSize).clamp(0, width);
      var sum = 0;
      var count = 0;
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          sum += rgba[(y * width + x) * 4];
          count++;
        }
      }
      means[blockY * columns + blockX] = sum / count;
    }
  }

  final output = Uint8List(rgba.length);
  for (var y = 0; y < height; y++) {
    final gridY = (y + .5) / blockSize - .5;
    final top = gridY.floor().clamp(0, rows - 1).toInt();
    final bottom = (top + 1).clamp(0, rows - 1).toInt();
    final yWeight = (gridY - top).clamp(0.0, 1.0);
    for (var x = 0; x < width; x++) {
      final gridX = (x + .5) / blockSize - .5;
      final left = gridX.floor().clamp(0, columns - 1).toInt();
      final right = (left + 1).clamp(0, columns - 1).toInt();
      final xWeight = (gridX - left).clamp(0.0, 1.0);
      final topMean =
          means[top * columns + left] * (1 - xWeight) +
          means[top * columns + right] * xWeight;
      final bottomMean =
          means[bottom * columns + left] * (1 - xWeight) +
          means[bottom * columns + right] * xWeight;
      final localMean = topMean * (1 - yWeight) + bottomMean * yWeight;
      final threshold = localMean - thresholdOffset;
      final offset = (y * width + x) * 4;
      final value = rgba[offset] < threshold ? 0 : 255;
      output[offset] = value;
      output[offset + 1] = value;
      output[offset + 2] = value;
      output[offset + 3] = 255;
    }
  }
  return output;
}
