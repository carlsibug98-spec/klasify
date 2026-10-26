import 'dart:math' as math;

/// A deskew estimate for a scanned timetable page.
class SkewEstimate {
  const SkewEstimate({required this.radians, required this.confidence});

  /// Rotation needed to make horizontal rules horizontal, in radians.
  final double radians;
  final double confidence;

  double get degrees => radians * 180 / math.pi;

  static const SkewEstimate none = SkewEstimate(radians: 0, confidence: 0);

  /// True when the angle is large enough that correcting it is worthwhile
  /// but small enough that resampling will not destroy the image.
  bool get shouldCorrect =>
      confidence >= .4 && radians.abs() > .006 && radians.abs() < .35;
}

/// Estimates page skew from long dark runs in a binarized RGBA buffer by
/// sampling each row's dark-pixel centroid across a vertical window and
/// fitting a least-squares line through those centroids. Straight table
/// rules are the dominant long-run feature on a timetable photo, so their
/// tilt is a robust proxy for page rotation.
SkewEstimate estimateGridSkew({
  required List<int> rowDarkCounts,
  required List<double> rowDarkCenters,
  required int width,
  required int height,
}) {
  if (width < 32 || height < 32) return SkewEstimate.none;

  // Keep only rows dominated by ink (candidate horizontal rules).
  final threshold = width * .45;
  final xs = <double>[];
  final ys = <double>[];
  for (var y = 0; y < height; y++) {
    if (rowDarkCounts[y] >= threshold) {
      xs.add(y.toDouble());
      ys.add(rowDarkCenters[y]);
    }
  }
  if (xs.length < 6) return SkewEstimate.none;

  // Least-squares fit of center against row index: slope = dx/dy.
  final n = xs.length;
  var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0;
  for (var i = 0; i < n; i++) {
    sumX += xs[i];
    sumY += ys[i];
    sumXX += xs[i] * xs[i];
    sumXY += xs[i] * ys[i];
  }
  final denom = n * sumXX - sumX * sumX;
  if (denom.abs() < 1e-9) return SkewEstimate.none;
  final slope = (n * sumXY - sumX * sumY) / denom;
  if (slope.abs() > .5) return SkewEstimate.none; // implausible page tilt

  // Goodness of fit: how tightly do rule centers follow the line?
  final intercept = (sumY - slope * sumX) / n;
  var ssRes = 0.0, ssTot = 0.0;
  for (var i = 0; i < n; i++) {
    final predicted = slope * xs[i] + intercept;
    ssRes += (ys[i] - predicted) * (ys[i] - predicted);
    ssTot += (ys[i] - sumY / n) * (ys[i] - sumY / n);
  }
  final r2 = ssTot <= 0 ? 0.0 : (1 - ssRes / ssTot).clamp(0.0, 1.0);
  // Convention: the estimate carries the page's own tilt (slope = dx/dy of
  // the rule centroids), so a right-drifting page yields a positive angle.
  // Callers rotate by -radians to level the rules; see [rotateRgba].
  final radians = math.atan(slope);
  return SkewEstimate(radians: radians, confidence: r2);
}

/// Rotates an RGBA buffer about its center by [radians] using inverse
/// bilinear sampling. Pixels projecting outside the source are painted white.
Uint8ListLike rotateRgba(
  Uint8ListLike pixels,
  int width,
  int height,
  double radians,
) {
  final output = Uint8ListLike.create(width, height);
  if (radians.abs() < 1e-6) {
    output.setAll(pixels);
    return output;
  }
  final cos = math.cos(radians);
  final sin = math.sin(radians);
  final cx = (width - 1) / 2;
  final cy = (height - 1) / 2;
  for (var y = 0; y < height; y++) {
    final dy = y - cy;
    for (var x = 0; x < width; x++) {
      final dx = x - cx;
      // Inverse map: where does this output pixel come from?
      final sx = cos * dx + sin * dy + cx;
      final sy = -sin * dx + cos * dy + cy;
      final offset = (y * width + x) * 4;
      if (sx < 0 || sx >= width - 1 || sy < 0 || sy >= height - 1) {
        output[offset] = 255;
        output[offset + 1] = 255;
        output[offset + 2] = 255;
        output[offset + 3] = 255;
        continue;
      }
      final x0 = sx.floor(), y0 = sy.floor();
      final fx = sx - x0, fy = sy - y0;
      final i00 = (y0 * width + x0) * 4;
      final i10 = i00 + 4;
      final i01 = i00 + width * 4;
      final i11 = i01 + 4;
      for (var channel = 0; channel < 4; channel++) {
        final top =
            pixels[i00 + channel] * (1 - fx) + pixels[i10 + channel] * fx;
        final bottom =
            pixels[i01 + channel] * (1 - fx) + pixels[i11 + channel] * fx;
        output[offset + channel] = (top * (1 - fy) + bottom * fy).round().clamp(
          0,
          255,
        );
      }
    }
  }
  return output;
}

/// Thin wrapper over [Uint8List] kept separate so tests can use plain lists.
class Uint8ListLike {
  Uint8ListLike._(this._data, this.length);

  factory Uint8ListLike.create(int width, int height) => Uint8ListLike._(
    List<int>.filled(width * height * 4, 255),
    width * height * 4,
  );

  factory Uint8ListLike.from(List<int> data) =>
      Uint8ListLike._([...data], data.length);

  final List<int> _data;
  final int length;

  int operator [](int index) => _data[index];
  void operator []=(int index, int value) => _data[index] = value;

  void setAll(Uint8ListLike other) {
    for (var i = 0; i < _data.length && i < other._data.length; i++) {
      _data[i] = other._data[i];
    }
  }

  List<int> toList() => [..._data];
}
