import 'dart:math' as math;
import 'dart:typed_data';

/// A fine-angle page tilt estimated from the text-line projection profile.
///
/// Unlike [estimateGridSkew] - which needs long horizontal dark runs and
/// therefore only sees near-level pages - this estimator works on phone
/// photos of a COR lying on a desk: it masks the bright paper region, weighs
/// the remaining horizontal glyph edges by their gradient magnitude, and
/// scores candidate tilts by how sharply the edge mass projects onto rows.
/// The score peaks when the text lines align, giving the tilt directly.
class ProfileSkewEstimate {
  const ProfileSkewEstimate({
    required this.degrees,
    required this.prominence,
  });

  /// Correction angle in degrees, positive rotating the page counter-
  /// clockwise as displayed - the same convention as PIL's Image.rotate and
  /// [rotateRgbaBuffer]. Feeding [degrees] back through that helper levels
  /// the text lines.
  final double degrees;

  /// Relative gain of the winning angle's projection sharpness over the
  /// unrotated profile: near 0 on a straight page, larger when the profile
  /// only sharpens once the tilt is removed. Acts as the confidence gate so
  /// straight pages never pay for a pointless rescue pass.
  final double prominence;

  static const ProfileSkewEstimate none = ProfileSkewEstimate(
    degrees: 0,
    prominence: 0,
  );

  /// True when the tilt is large enough that correcting it can change what
  /// OCR reads, and the profile signal is confident enough to trust the
  /// angle. Calibrated on the COR benchmark fixtures: the tilted photo
  /// measures prominence 0.17 at -4.5 degrees while every straight fixture
  /// measures 0.000.
  bool get shouldRescue => degrees.abs() >= 1.5 && prominence >= 0.10;
}

/// Estimates the page tilt of an enhanced grayscale buffer (one byte per
/// pixel, row-major). Returns [ProfileSkewEstimate.none] for tiny images or
/// pages with too little glyph edge mass to score.
ProfileSkewEstimate estimateSkewProfile({
  required Uint8List gray,
  required int width,
  required int height,
}) {
  if (width < 96 || height < 96) return ProfileSkewEstimate.none;

  // Paper band: rows whose 25th-percentile brightness is paper-bright. The
  // 25th percentile reads the page between text lines, where wood grain or
  // a dark desk still falls far below paper.
  final rowOk = List<bool>.filled(height, false);
  final hist = List<int>.filled(256, 0);
  var okRows = 0;
  for (var y = 0; y < height; y++) {
    for (var v = 0; v < 256; v++) {
      hist[v] = 0;
    }
    final base = y * width;
    for (var x = 0; x < width; x++) {
      hist[gray[base + x]]++;
    }
    final target = width ~/ 4;
    var cumulative = 0;
    var value = 255;
    for (var v = 0; v < 256; v++) {
      cumulative += hist[v];
      if (cumulative > target) {
        value = v;
        break;
      }
    }
    rowOk[y] = value > 140;
    if (value > 140) okRows++;
  }
  if (okRows < height * .15) {
    for (var y = 0; y < height; y++) {
      rowOk[y] = true;
    }
  }
  var y0 = 0;
  while (y0 < height && !rowOk[y0]) {
    y0++;
  }
  var y1 = height;
  while (y1 > y0 + 1 && !rowOk[y1 - 1]) {
    y1--;
  }
  final bandHeight = y1 - y0;
  if (bandHeight < 96) return ProfileSkewEstimate.none;

  // Column bounds inside the band, same percentile logic, so the wood left
  // and right of the page never contributes edge mass.
  final colOk = List<bool>.filled(width, false);
  var okCols = 0;
  for (var x = 0; x < width; x++) {
    for (var v = 0; v < 256; v++) {
      hist[v] = 0;
    }
    for (var y = y0; y < y1; y++) {
      hist[gray[y * width + x]]++;
    }
    final target = bandHeight ~/ 4;
    var cumulative = 0;
    var value = 255;
    for (var v = 0; v < 256; v++) {
      cumulative += hist[v];
      if (cumulative > target) {
        value = v;
        break;
      }
    }
    colOk[x] = value > 140;
    if (value > 140) okCols++;
  }
  if (okCols < width * .15) {
    for (var x = 0; x < width; x++) {
      colOk[x] = true;
    }
  }
  var x0 = 0;
  while (x0 < width && !colOk[x0]) {
    x0++;
  }
  var x1 = width;
  while (x1 > x0 + 1 && !colOk[x1 - 1]) {
    x1--;
  }
  final bandWidth = x1 - x0;
  if (bandWidth < 96) return ProfileSkewEstimate.none;

  // Samples: horizontal glyph edges inside the page, weighted by gradient
  // magnitude. Wood grain and flat fills carry little horizontal edge mass,
  // so text rows dominate the projection even on a busy background.
  var edgeCount = 0;
  for (var y = y0; y < y1; y++) {
    final base = y * width;
    var previous = gray[base + x0];
    for (var x = x0 + 1; x < x1; x++) {
      final current = gray[base + x];
      if ((current - previous).abs() > 0) edgeCount++;
      previous = current;
    }
  }
  if (edgeCount < 2000) return ProfileSkewEstimate.none;
  final stride = (edgeCount / 400000).ceil();
  final maxSamples = edgeCount ~/ stride + 1;
  final sampleX = Int32List(maxSamples);
  final sampleY = Int32List(maxSamples);
  final sampleW = Float32List(maxSamples);
  var samples = 0;
  var edgeIndex = 0;
  var weightSum = 0.0;
  for (var y = y0; y < y1; y++) {
    final base = y * width;
    var previous = gray[base + x0];
    for (var x = x0 + 1; x < x1; x++) {
      final current = gray[base + x];
      final magnitude = (current - previous).abs();
      previous = current;
      if (magnitude <= 0) continue;
      if (edgeIndex++ % stride != 0) continue;
      sampleX[samples] = x;
      sampleY[samples] = y;
      sampleW[samples] = magnitude.toDouble();
      weightSum += magnitude;
      samples++;
    }
  }
  if (samples < 2000 || weightSum <= 0) return ProfileSkewEstimate.none;

  var centerX = 0.0;
  for (var i = 0; i < samples; i++) {
    centerX += sampleW[i] * sampleX[i];
  }
  centerX /= weightSum;

  // Projection sharpness: shearing the edge mass by a candidate tilt and
  // summing the squared row projections peaks exactly when the text lines
  // align. Dividing by the band width keeps scores comparable across pages.
  double scoreFor(double degrees) {
    final tan = math.tan(degrees * math.pi / 180);
    final bins = Float64List(bandHeight);
    for (var i = 0; i < samples; i++) {
      final yi = (sampleY[i] - tan * (sampleX[i] - centerX)).round() - y0;
      if (yi < 0 || yi >= bandHeight) continue;
      bins[yi] += sampleW[i];
    }
    var sumSquares = 0.0;
    for (var i = 0; i < bandHeight; i++) {
      sumSquares += bins[i] * bins[i];
    }
    return sumSquares / bandWidth;
  }

  final scores = <double, double>{};
  var best = 0.0;
  var bestScore = -1.0;
  for (var degree = -9; degree <= 9; degree++) {
    final score = scoreFor(degree.toDouble());
    scores[degree.toDouble()] = score;
    if (score > bestScore) {
      bestScore = score;
      best = degree.toDouble();
    }
  }
  for (var i = 0; i < 9; i++) {
    final degree = best - 1.0 + 0.25 * i;
    final score = scoreFor(degree);
    scores[degree] = score;
    if (score > bestScore) {
      bestScore = score;
      best = degree;
    }
  }
  final flat = scores[0.0] ?? 0.0;
  final prominence = bestScore > 0 ? (bestScore - flat) / bestScore : 0.0;
  return ProfileSkewEstimate(degrees: best, prominence: prominence);
}

/// Rotates an RGBA buffer about its center by [degrees], counter-clockwise
/// as displayed (PIL Image.rotate convention), using inverse bilinear
/// sampling with a white fill outside the source. The canvas keeps its size.
Uint8List rotateRgbaBuffer(
  Uint8List rgba,
  int width,
  int height,
  double degrees,
) {
  final output = Uint8List(rgba.length);
  final radians = -degrees * math.pi / 180;
  if (radians.abs() < 1e-6) {
    output.setAll(0, rgba);
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
      final x0 = sx.floor();
      final y0 = sy.floor();
      final fx = sx - x0;
      final fy = sy - y0;
      final i00 = (y0 * width + x0) * 4;
      final i10 = i00 + 4;
      final i01 = i00 + width * 4;
      final i11 = i01 + 4;
      for (var channel = 0; channel < 4; channel++) {
        final top = rgba[i00 + channel] * (1 - fx) + rgba[i10 + channel] * fx;
        final bottom =
            rgba[i01 + channel] * (1 - fx) + rgba[i11 + channel] * fx;
        output[offset + channel] =
            (top * (1 - fy) + bottom * fy).round().clamp(0, 255);
      }
    }
  }
  return output;
}
