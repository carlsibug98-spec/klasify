import 'dart:typed_data';

class TimetableGridPixelAnalysis {
  const TimetableGridPixelAnalysis({
    required this.leftEdge,
    required this.bounds,
    required this.timeRules,
    required this.rules,
    required this.strongRules,
  });

  final int leftEdge;
  final Map<int, List<double>> bounds;
  final List<int> timeRules;
  final Map<int, List<int>> rules;
  final Map<int, List<int>> strongRules;
}

TimetableGridPixelAnalysis analyzeTimetableGridPixels({
  required Uint8List pixels,
  required int width,
  required int height,
  required List<int> sortedDays,
  required Map<int, double> headers,
}) {
  normalizeGridPixels(pixels);
  final gridTop = (height * .025).round().clamp(0, height - 1).toInt();
  final gridBottom = (height * .91).round().clamp(gridTop + 1, height).toInt();
  final verticalInk = List<int>.generate(width, (x) {
    if (x < 2 || x >= width - 2) return 0;
    var count = 0;
    for (var y = gridTop; y < gridBottom; y++) {
      final offset = (y * width + x) * 4;
      final nearby = (pixels[offset - 8] + pixels[offset + 8]) / 2;
      if (nearby - pixels[offset] >= 6) count++;
    }
    return count;
  });

  int strongestVertical(double from, double to) {
    final lo = from.round().clamp(0, width - 1).toInt();
    final hi = to.round().clamp(lo + 1, width).toInt();
    var bestX = lo;
    var bestCount = -1;
    for (var x = lo; x < hi; x++) {
      if (verticalInk[x] > bestCount) {
        bestCount = verticalInk[x];
        bestX = x;
      }
    }
    return bestX;
  }

  final centers = sortedDays.map((day) => headers[day]!).toList();
  final dayEdges = <double>[];
  final firstCenter = centers.first;
  final firstGap = centers.length > 1 ? centers[1] - firstCenter : width * .15;
  final leftSearchStart = (firstCenter - firstGap * .68)
      .clamp(0, firstCenter - 1)
      .round();
  final leftSearchEnd = (firstCenter - firstGap * .12)
      .clamp(leftSearchStart + 1, width)
      .round();
  final leftThreshold = (gridBottom - gridTop) * .22;
  var leftEdge = -1;
  for (var x = leftSearchStart; x < leftSearchEnd; x++) {
    if (verticalInk[x] >= leftThreshold) leftEdge = x;
  }
  if (leftEdge < 0) leftEdge = strongestVertical(width * .16, firstCenter - 1);
  dayEdges.add(leftEdge.toDouble());
  for (var i = 0; i < centers.length - 1; i++) {
    final midpoint = (centers[i] + centers[i + 1]) / 2;
    final radius = (centers[i + 1] - centers[i]) * .22;
    dayEdges.add(
      strongestVertical(midpoint - radius, midpoint + radius).toDouble(),
    );
  }
  final lastCenter = centers.last;
  final lastGap = centers.length > 1
      ? centers.last - centers[centers.length - 2]
      : width * .15;
  var rightEdge = strongestVertical(
    lastCenter + lastGap * .18,
    width.toDouble(),
  );
  if (verticalInk[rightEdge] < (gridBottom - gridTop) * .22) {
    rightEdge = width - 1;
  }
  dayEdges.add(rightEdge.toDouble());

  final bounds = <int, List<double>>{
    for (var i = 0; i < sortedDays.length; i++)
      sortedDays[i]: [dayEdges[i], dayEdges[i + 1]],
  };
  final gutterRight = (leftEdge - 2).clamp(1, width).toInt();
  final gutterSpan = gutterRight - 1;
  final timeRules = <int>[];
  for (var y = gridTop; y < gridBottom; y++) {
    var darkCount = 0;
    for (var x = 1; x < gutterRight; x++) {
      if (isDarkGridPixel(pixels, width, x, y)) darkCount++;
    }
    if (darkCount >= gutterSpan * .5) {
      if (timeRules.isEmpty || y - timeRules.last > 2) {
        timeRules.add(y);
      } else {
        timeRules[timeRules.length - 1] = y;
      }
    }
  }

  final rules = <int, List<int>>{};
  final strongRules = <int, List<int>>{};
  for (final day in sortedDays) {
    final left = bounds[day]![0];
    final right = bounds[day]![1];
    final x1 = (left + 3).round().clamp(0, width - 1).toInt();
    final x2 = (right - 3).round().clamp(x1 + 1, width).toInt();
    rules[day] = horizontalGridRuleRows(
      pixels,
      width: width,
      height: height,
      left: x1,
      right: x2,
    );

    final span = x2 - x1;
    final strong = <int>[];
    for (var y = 2; y < height - 2; y++) {
      var count = 0;
      for (var x = x1; x < x2; x++) {
        final offset = (y * width + x) * 4;
        final nearby =
            (pixels[offset - width * 8] + pixels[offset + width * 8]) / 2;
        if (pixels[offset] <= 170 && nearby - pixels[offset] >= 12) count++;
      }
      if (count >= span * .68) {
        if (strong.isEmpty || y - strong.last > 2) {
          strong.add(y);
        } else {
          strong[strong.length - 1] = y;
        }
      }
    }
    strongRules[day] = strong;
  }

  return TimetableGridPixelAnalysis(
    leftEdge: leftEdge,
    bounds: bounds,
    timeRules: timeRules,
    rules: rules,
    strongRules: strongRules,
  );
}

bool normalizeGridPixels(Uint8List pixels) {
  if (pixels.isEmpty || pixels.length % 4 != 0) {
    throw ArgumentError('Invalid RGBA pixel buffer.');
  }
  final histogram = List<int>.filled(256, 0);
  for (var offset = 0; offset < pixels.length; offset += 4) {
    histogram[_sourceLuminance(pixels, offset)]++;
  }

  var total = 0;
  var median = 0;
  for (var value = 0; value < histogram.length; value++) {
    total += histogram[value];
    if (total >= pixels.length / 8) {
      median = value;
      break;
    }
  }
  final invert = median < 128;
  for (var offset = 0; offset < pixels.length; offset += 4) {
    final sourceLuminance = _sourceLuminance(pixels, offset);
    final gray = invert ? 255 - sourceLuminance : sourceLuminance;
    pixels[offset] = gray;
    pixels[offset + 1] = gray;
    pixels[offset + 2] = gray;
    pixels[offset + 3] = 255;
  }
  return invert;
}

bool isDarkGridPixel(Uint8List pixels, int width, int x, int y) =>
    pixels[(y * width + x) * 4] < 105;

List<int> horizontalGridRuleRows(
  Uint8List pixels, {
  required int width,
  required int height,
  required int left,
  required int right,
}) {
  final x1 = left.clamp(0, width).toInt();
  final x2 = right.clamp(0, width).toInt();
  final span = x2 - x1;
  if (span < 1 || height < 5) return [];

  final rules = <int>[];
  for (var y = 2; y < height - 2; y++) {
    var contrastingPixels = 0;
    for (var x = x1; x < x2; x++) {
      final offset = (y * width + x) * 4;
      final nearby =
          (pixels[offset - width * 8] + pixels[offset + width * 8]) / 2;
      if (nearby - pixels[offset] >= 6) contrastingPixels++;
    }
    if (contrastingPixels < span * .6) continue;
    if (rules.isEmpty || y - rules.last > 2) {
      rules.add(y);
    } else {
      rules[rules.length - 1] = y;
    }
  }
  return rules;
}

int _sourceLuminance(Uint8List pixels, int offset) {
  final alpha = pixels[offset + 3];
  final inverseAlpha = 255 - alpha;
  final red = (pixels[offset] * alpha + 255 * inverseAlpha + 127) ~/ 255;
  final green = (pixels[offset + 1] * alpha + 255 * inverseAlpha + 127) ~/ 255;
  final blue = (pixels[offset + 2] * alpha + 255 * inverseAlpha + 127) ~/ 255;
  return (red * 299 + green * 587 + blue * 114 + 500) ~/ 1000;
}
