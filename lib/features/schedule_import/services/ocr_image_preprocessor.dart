import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/adaptive_ocr_threshold.dart';
import '../utils/ocr_resample.dart';
import '../utils/skew_correction.dart';
import '../utils/skew_profile_estimator.dart';

class _OcrPixelTransformRequest {
  const _OcrPixelTransformRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.invertDarkBackground,
    required this.adaptiveThreshold,
    this.deskew = false,
    this.sharpen = false,
    this.upscaleTarget = 1800,
    this.rotateDegrees = 0,
    this.crisp = false,
    this.rotateBeforeEnhance = false,
    this.flattenIllumination = false,
    this.dewarp = false,
  });

  final TransferableTypedData rgba;
  final int width;
  final int height;
  final bool invertDarkBackground;
  final bool adaptiveThreshold;
  final bool deskew;
  final bool sharpen;

  /// Illumination-flatten rescue: divide the page by its large-scale
  /// background before the contrast stretch. A photographed page half in a
  /// hard cast shadow keeps its glyphs but loses the ink-to-paper contrast
  /// on the shaded side; no threshold or sharpen pass recovers that. The
  /// round-11 generalization sweep measured 1/10 -> 10/10 rows on the
  /// shadow fixture with this recipe.
  final bool flattenIllumination;

  /// Decode-time upscale floor: sources shorter than this are enlarged so
  /// thin glyphs keep enough pixels for the recognizer. The default matches
  /// the historical behavior; the scan cascade's high-res rescue raises it.
  final int upscaleTarget;

  /// Fine-angle correction applied after enhancement, counter-clockwise as
  /// displayed (PIL Image.rotate convention). Driven by the projection
  /// profile estimate the enhanced pass reports.
  final double rotateDegrees;

  /// High-res rescue recipe: decode at native size, Lanczos-upscale to
  /// [upscaleTarget] inside the isolate, then apply the gentle unsharp after
  /// enhancement. The round-10 sweep found the small-capture room column
  /// only survives this pairing - the engine's default resampler plus the
  /// same unsharp destroys the parse instead.
  final bool crisp;

  /// Deskew rescue recipe: apply [rotateDegrees] BEFORE the contrast
  /// enhancement. The round-10 sweep found tilted pages read best when the
  /// interpolation blur is contrast-stretched afterwards rather than before.
  final bool rotateBeforeEnhance;

  /// Dewarp rescue recipe (round 12): straighten a page photographed with a
  /// curl BEFORE the flatten/stretch steps consume it. The isolate estimates
  /// the vertical displacement field from the page's own horizontal rules
  /// and returns no pixels when the gate says the page is not curled, so
  /// the cascade simply skips the candidate.
  final bool dewarp;
}

class _OcrPixelTransformResult {
  const _OcrPixelTransformResult(
    this.pixels, {
    this.softness = 0,
    this.skewDegrees = 0,
    this.skewProminence = 0,
    this.resultWidth = 0,
    this.resultHeight = 0,
  });

  final TransferableTypedData? pixels;

  /// Pixel size of [pixels] - differs from the decoded source when the crisp
  /// rescue upscaled it inside the isolate.
  final int resultWidth;
  final int resultHeight;

  /// Variance of the 3x3 Laplacian over the enhanced grayscale: near zero on
  /// an out-of-focus or interpolation-soft photo, high on crisp text. Used
  /// by the scan cascade to decide whether a sharpened variant is worth one
  /// more recognition pass.
  final double softness;

  /// Projection-profile tilt of the enhanced page (see
  /// [estimateSkewProfile]). Consumed by the scan cascade's deskew rescue;
  /// computed on the enhanced pass, so no extra decode is needed.
  final double skewDegrees;

  /// Confidence of [skewDegrees]: relative sharpness gain over the
  /// unrotated profile. Near 0 on straight pages.
  final double skewProminence;
}

_OcrPixelTransformResult _transformOcrPixels(
  _OcrPixelTransformRequest request,
) {
  var rgba = request.rgba.materialize().asUint8List();
  var width = request.width;
  var height = request.height;

  // High-res rescue: the engine's decode-time resampler is too soft for the
  // small-capture rescue - swap it for the production Lanczos upscale before
  // any measurement happens (see [lanczosResizeRgba] for the round-10
  // findings). The rotation is applied first as well when the deskew rescue
  // asks for it: tilted pages read best enhanced after the correction.
  final longest = math.max(width, height);
  if (request.crisp && longest < request.upscaleTarget) {
    final ratio = request.upscaleTarget / longest;
    final targetWidth = math.max(1, (width * ratio).round());
    final targetHeight = math.max(1, (height * ratio).round());
    rgba = lanczosResizeRgba(rgba, width, height, targetWidth, targetHeight);
    width = targetWidth;
    height = targetHeight;
  }
  if (request.rotateBeforeEnhance && request.rotateDegrees.abs() >= .05) {
    rgba = rotateRgbaBuffer(rgba, width, height, request.rotateDegrees);
  }

  final total = width * height;
  final histogram = List<int>.filled(256, 0);
  final gray = Uint8List(total);
  for (var pixel = 0; pixel < total; pixel++) {
    final offset = pixel * 4;
    final luminance = (rgba[offset] * 299 +
            rgba[offset + 1] * 587 +
            rgba[offset + 2] * 114) ~/
        1000;
    gray[pixel] = luminance;
    histogram[luminance]++;
  }

  // The flatten rescue divides by the background BEFORE the stretch, so
  // both the gray buffer and the histogram it feeds are rebuilt. The dewarp
  // rescue re-aligns the columns even earlier: its vertical resampling
  // blurs the page slightly, and both the flatten quotient and the stretch
  // read cleaner once the rows are level (the round-12 warped fixture only
  // recovers its room column with this order).
  if (request.dewarp) {
    if (!_dewarpCurvedColumns(gray, width, height)) {
      return const _OcrPixelTransformResult(null);
    }
  }
  if (request.flattenIllumination) {
    _flattenIllumination(gray, width, height);
    histogram.fillRange(0, 256, 0);
    for (var pixel = 0; pixel < total; pixel++) {
      histogram[gray[pixel]]++;
    }
  }

  if (request.invertDarkBackground) {
    var cumulative = 0;
    var median = 0;
    for (var value = 0; value < 256; value++) {
      cumulative += histogram[value];
      if (cumulative >= total / 2) {
        median = value;
        break;
      }
    }
    if (median >= 128) return const _OcrPixelTransformResult(null);
  }

  final clip = math.max(1, (total * .01).round());
  var low = 0;
  var high = 255;
  var cumulative = 0;
  for (var value = 0; value < 256; value++) {
    cumulative += histogram[value];
    if (cumulative >= clip) {
      low = value;
      break;
    }
  }
  cumulative = 0;
  for (var value = 255; value >= 0; value--) {
    cumulative += histogram[value];
    if (cumulative >= clip) {
      high = value;
      break;
    }
  }
  if (high <= low) {
    low = 0;
    high = 255;
  }

  final enhancedPixels = Uint8List(total * 4);
  final enhancedGray = Uint8List(total);
  final range = high - low;
  for (var pixel = 0; pixel < total; pixel++) {
    final stretched = ((gray[pixel] - low) / range).clamp(0.0, 1.0);
    final enhancedValue =
        (math.pow(stretched, .85) * 255).round().clamp(0, 255).toInt();
    enhancedGray[pixel] = enhancedValue;
    final value =
        request.invertDarkBackground ? 255 - enhancedValue : enhancedValue;
    final offset = pixel * 4;
    enhancedPixels[offset] = value;
    enhancedPixels[offset + 1] = value;
    enhancedPixels[offset + 2] = value;
    enhancedPixels[offset + 3] = 255;
  }

  final softness =
      _laplacianVariance(enhancedPixels, width, height);

  // The projection profile reads the enhanced page once per scan; variant
  // calls (sharpen, rotate, threshold, invert) skip it - their results are
  // either unusable for the profile or already carry the angle from the
  // enhanced pass that triggered them.
  var skew = ProfileSkewEstimate.none;
  if (!request.invertDarkBackground &&
      !request.adaptiveThreshold &&
      !request.sharpen &&
      !request.crisp &&
      !request.flattenIllumination &&
      request.rotateDegrees.abs() < .05) {
    skew = estimateSkewProfile(
      gray: enhancedGray,
      width: width,
      height: height,
    );
  }

  Uint8List pixels;
  if (request.sharpen) {
    // Unsharp masking: add 1.5x the high-frequency residue the 3x3 gaussian
    // removes. Recovers glyph edges on out-of-focus phone photos; on sharp
    // photos it only amplifies noise, which is why the cascade gates it on
    // the softness metric instead of running it unconditionally.
    pixels = _unsharpRgba(enhancedPixels, width, height);
  } else if (request.crisp) {
    // High-res rescue sharpening: the gentle percent-based unsharp the
    // round-10 sweep calibrated (see [softUnsharpRgba]). Mild enough to keep
    // the parse intact, strong enough to reveal the small-capture room
    // column the plain enhancement leaves below the recognizer's floor.
    pixels = softUnsharpRgba(enhancedPixels, width, height);
  } else {
    pixels = enhancedPixels;
  }

  var thresholded = request.adaptiveThreshold
      ? adaptiveThresholdRgba(pixels, width, height)
      : pixels;

  if (!request.rotateBeforeEnhance && request.rotateDegrees.abs() >= .05) {
    thresholded = rotateRgbaBuffer(
      thresholded,
      width,
      height,
      request.rotateDegrees,
    );
  }

  if (request.deskew) {
    final deskewed = _deskewGrayscaleBuffer(
      thresholded,
      width,
      height,
    );
    if (deskewed != null) {
      return _OcrPixelTransformResult(
        TransferableTypedData.fromList([deskewed]),
        softness: softness,
        skewDegrees: skew.degrees,
        skewProminence: skew.prominence,
        resultWidth: width,
        resultHeight: height,
      );
    }
  }
  return _OcrPixelTransformResult(
    TransferableTypedData.fromList([thresholded]),
    softness: softness,
    skewDegrees: skew.degrees,
    skewProminence: skew.prominence,
    resultWidth: width,
    resultHeight: height,
  );
}

/// Variance of the 3x3 Laplacian across the grayscale channels of [rgba].
double _laplacianVariance(Uint8List rgba, int width, int height) {
  if (width < 3 || height < 3) return 0;
  var sum = 0.0;
  var sumSquares = 0.0;
  var count = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final offset = (y * width + x) * 4;
      final center = rgba[offset].toDouble();
      final lap = 4 * center -
          rgba[offset - 4] -
          rgba[offset + 4] -
          rgba[offset - width * 4] -
          rgba[offset + width * 4];
      sum += lap;
      sumSquares += lap * lap;
      count++;
    }
  }
  if (count == 0) return 0;
  final mean = sum / count;
  return sumSquares / count - mean * mean;
}

/// Illumination-flatten rescue: divides the page's grayscale by its
/// large-scale background so a hard cast shadow stops suppressing the
/// ink-to-paper contrast. The background is a box blur whose kernel is far
/// larger than any glyph (about 1/27 of the short side, clamped to
/// 33..129 px - the span the round-11 sweep validated) and the quotient is
/// rescaled to a 245 ceiling so paper stays near white. Runs on [gray] in
/// place, before the contrast stretch consumes it.
void _flattenIllumination(Uint8List gray, int width, int height) {
  final k = (math.min(width, height) ~/ 27).clamp(33, 129);
  final r = k ~/ 2;

  // Separable box blur, sliding window per row then per column.
  final horizontal = Float64List(width * height);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var windowSum = 0.0;
    for (var x = -r; x <= r; x++) {
      windowSum += gray[row + math.min(width - 1, math.max(0, x))];
    }
    final count = math.min(width - 1, r) + math.min(r, width - 1) + 1;
    for (var x = 0; x < width; x++) {
      horizontal[row + x] = windowSum / count;
      final outgoing = gray[row + math.max(0, x - r)];
      final incoming = gray[row + math.min(width - 1, x + r + 1)];
      windowSum += incoming - outgoing;
    }
  }
  final background = Float64List(width * height);
  for (var x = 0; x < width; x++) {
    var windowSum = 0.0;
    for (var y = -r; y <= r; y++) {
      windowSum += horizontal[math.min(height - 1, math.max(0, y)) * width + x];
    }
    final count = math.min(height - 1, r) + math.min(r, height - 1) + 1;
    for (var y = 0; y < height; y++) {
      background[y * width + x] = windowSum / count;
      final outgoing = horizontal[math.max(0, y - r) * width + x];
      final incoming =
          horizontal[math.min(height - 1, y + r + 1) * width + x];
      windowSum += incoming - outgoing;
    }
  }

  const ceiling = 245.0;
  for (var pixel = 0; pixel < gray.length; pixel++) {
    final bg = background[pixel];
    final value = bg < 1
        ? ceiling
        : (gray[pixel] / bg) * ceiling;
    gray[pixel] = value.round().clamp(0, 255);
  }
}

/// Rule-based curl correction (round 12). Detects the page's long
/// horizontal rules inside 10 vertical strips, matches them bottom-up
/// across strips (header underlines sit above the table and cannot shift
/// the order), references each rule against the median across strips, and
/// fits a linear vertical displacement over x. A real page curl produces a
/// small, smooth, near-linear field - the round-12 fixture measured a
/// 0.4 px residual - while shadows, blur, and missing rules fail the
/// residual gate. Applies out(x, y) = in(x, y - offset(x)) with bilinear
/// sampling when the gate fires. Returns true when [gray] was re-aligned.
bool _dewarpCurvedColumns(Uint8List gray, int width, int height) {
  const strips = 10;
  final edges = List<int>.generate(strips + 1, (i) => i * width ~/ strips);
  final centersPerStrip = <List<double>>[];
  for (var s = 0; s < strips; s++) {
    final x0 = edges[s];
    final x1 = math.max(edges[s] + 1, edges[s + 1]);
    final stripWidth = x1 - x0;
    final centers = <double>[];
    var runStart = -1;
    for (var y = 0; y < height; y++) {
      var dark = 0;
      final row = y * width;
      for (var x = x0; x < x1; x++) {
        if (gray[row + x] < 140) dark++;
      }
      final isRule = dark >= stripWidth * .55;
      if (isRule && runStart < 0) runStart = y;
      if (!isRule && runStart >= 0) {
        centers.add((runStart + y - 1) / 2);
        runStart = -1;
      }
    }
    centersPerStrip.add(centers);
  }
  final usable = <int>[];
  for (var s = 0; s < strips; s++) {
    if (centersPerStrip[s].length >= 3) usable.add(s);
  }
  if (usable.length < strips ~/ 2) return false;
  var common = centersPerStrip[usable.first].length;
  for (final s in usable) {
    if (centersPerStrip[s].length < common) {
      common = centersPerStrip[s].length;
    }
  }
  if (common < 3) return false;

  // Per-rule reference (median across strips) and per-strip offset
  // (median across rules) - both robust to a rule dropping out of one
  // strip or an extra underline sneaking into another.
  final offsets = List<double>.filled(strips, 0);
  final validX = <double>[];
  final validY = <double>[];
  for (final s in usable) {
    final centers = centersPerStrip[s];
    final samples = <double>[];
    for (var r = 0; r < common; r++) {
      final value = centers[centers.length - common + r];
      final reference = <double>[];
      for (final t in usable) {
        reference.add(
          centersPerStrip[t][centersPerStrip[t].length - common + r],
        );
      }
      samples.add(value - _medianOf(reference));
    }
    offsets[s] = _medianOf(samples);
    validX.add(((edges[s] + edges[s + 1]) / 2) / width);
    validY.add(offsets[s]);
  }

  // Linear least-squares fit offset(x) = a + b * (x / width).
  var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0;
  for (var i = 0; i < validX.length; i++) {
    sumX += validX[i];
    sumY += validY[i];
    sumXX += validX[i] * validX[i];
    sumXY += validX[i] * validY[i];
  }
  final n = validX.length.toDouble();
  final denominator = n * sumXX - sumX * sumX;
  if (denominator <= 1e-9) return false;
  final b = (n * sumXY - sumX * sumY) / denominator;
  final a = (sumY - b * sumX) / n;
  var amplitude = a.abs();
  if ((a + b).abs() > amplitude) amplitude = (a + b).abs();
  var residual = 0.0;
  for (var i = 0; i < validX.length; i++) {
    final fit = a + b * validX[i];
    final error = (fit - validY[i]).abs();
    if (error > residual) residual = error;
  }
  // A genuine curl is small AND smooth. Shadows and blur yield huge,
  // ragged rule offsets; clean pages yield none at all.
  if (amplitude < math.max(6.0, height * .004)) return false;
  if (residual > math.max(3.0, amplitude * .25)) return false;
  debugPrint(
    'Dewarping OCR image (curl drift ${amplitude.toStringAsFixed(1)} px, '
    'residual ${residual.toStringAsFixed(1)} px).',
  );

  final source = Uint8List.fromList(gray);
  // The fitted field is already median-referenced (each strip's offset was
  // measured against the median across strips), so applying it as-is moves
  // every column by half the curl - the gentlest correction that levels
  // the rows relative to each other. The round-12 measurement kept all
  // rows with this reference.
  for (var x = 0; x < width; x++) {
    final shift = a + b * (x / width);
    for (var y = 0; y < height; y++) {
      final srcY = y - shift;
      final y0 = srcY.floor();
      final frac = srcY - y0;
      final y0c = y0 < 0 ? 0 : (y0 > height - 1 ? height - 1 : y0);
      var y1c = y0 + 1;
      if (y1c < 0) y1c = 0;
      if (y1c > height - 1) y1c = height - 1;
      var value = source[y0c * width + x] * (1 - frac) +
          source[y1c * width + x] * frac;
      if (srcY < 0 || srcY > height - 1) value = 255;
      gray[y * width + x] = value.round().clamp(0, 255).toInt();
    }
  }
  return true;
}

/// Median of [values] (empty-safe).
double _medianOf(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.from(values)..sort();
  final n = sorted.length;
  return n.isOdd
      ? sorted[n ~/ 2]
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// Unsharp mask with a 3x3 gaussian (1 2 1 / 2 4 2 / 1 2 1) low-pass and a
/// 1.5x amount, matching the PIL recipe the benchmarks calibrated on.
Uint8List _unsharpRgba(Uint8List rgba, int width, int height) {
  final blurred = Uint8List(rgba.length);
  const amount = 1.5;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        final c = offset + channel;
        final up = y > 0 ? c - width * 4 : c;
        final down = y < height - 1 ? c + width * 4 : c;
        final left = x > 0 ? c - 4 : c;
        final right = x < width - 1 ? c + 4 : c;
        final lowPass = (rgba[up] +
                2 * rgba[left] +
                4 * rgba[c] +
                2 * rgba[right] +
                rgba[down]) /
            10;
        final value =
            (rgba[c] + amount * (rgba[c] - lowPass)).round().clamp(0, 255);
        blurred[c] = value;
      }
      blurred[offset + 3] = 255;
    }
  }
  return blurred;
}

/// Estimates the dominant horizontal-rule tilt and rotates the buffer back to
/// level. Returns null when the page is already straight or too small.
Uint8List? _deskewGrayscaleBuffer(Uint8List rgba, int width, int height) {
  // Downsample by 2 for speed: rules stay detectable at half resolution.
  final step = 2;
  final sampledWidth = width ~/ step;
  final sampledHeight = height ~/ step;
  if (sampledWidth < 32 || sampledHeight < 32) return null;
  final rowCounts = List<int>.filled(sampledHeight, 0);
  final rowCenters = List<double>.filled(sampledHeight, 0);
  for (var sy = 0; sy < sampledHeight; sy++) {
    var ink = 0;
    var centerSum = 0.0;
    for (var sx = 0; sx < sampledWidth; sx++) {
      final offset = ((sy * step) * width + sx * step) * 4;
      if (rgba[offset] < 105) {
        ink++;
        centerSum += sx;
      }
    }
    rowCounts[sy] = ink;
    rowCenters[sy] = ink == 0 ? 0 : centerSum / ink;
  }
  final estimate = estimateGridSkew(
    rowDarkCounts: rowCounts,
    rowDarkCenters: rowCenters,
    width: sampledWidth,
    height: sampledHeight,
  );
  if (!estimate.shouldCorrect) return null;
  debugPrint(
    'Deskewing OCR image by ${estimate.degrees.toStringAsFixed(2)} degrees '
    '(confidence ${estimate.confidence.toStringAsFixed(2)}).',
  );
  final output = Uint8List(rgba.length);
  // estimate.radians is the page's tilt; rotate by -radians to level rules.
  final cos = math.cos(-estimate.radians);
  final sin = math.sin(-estimate.radians);
  final cx = (width - 1) / 2;
  final cy = (height - 1) / 2;
  for (var y = 0; y < height; y++) {
    final dy = y - cy;
    for (var x = 0; x < width; x++) {
      final dx = x - cx;
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
      final i01 = i00 + width * 4;
      for (var channel = 0; channel < 4; channel++) {
        final top =
            rgba[i00 + channel] * (1 - fx) + rgba[i00 + 4 + channel] * fx;
        final bottom =
            rgba[i01 + channel] * (1 - fx) + rgba[i01 + 4 + channel] * fx;
        output[offset + channel] = (top * (1 - fy) + bottom * fy).round().clamp(
              0,
              255,
            );
      }
    }
  }
  return output;
}

/// Creates temporary, OCR-friendly variants while preserving image geometry.
class OcrImagePreprocessor {
  Future<PreparedOcrImage?> prepare(
    String path, {
    int quarterTurns = 0,
    bool adaptiveThreshold = false,
    bool invertDarkBackground = false,
    bool deskew = false,
    bool sharpen = false,
    int upscaleTarget = 1800,
    double rotateDegrees = 0,
    bool crisp = false,
    bool rotateBeforeEnhance = false,
    bool flattenIllumination = false,
    bool dewarp = false,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? normalized;
    ui.Image? output;
    try {
      final bytes = await File(path).readAsBytes();
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final originalWidth = descriptor.width;
      final originalHeight = descriptor.height;
      final longestSide = math.max(originalWidth, originalHeight);
      // The crisp rescue decodes at native size and Lanczos-upscales inside
      // the isolate, so the engine's softer decode-time resampler never
      // touches the pixels the recipe was calibrated on.
      final ratio = crisp
          ? math.min(1.0, 2400 / longestSide)
          : longestSide < upscaleTarget
              ? math.min(2.0, upscaleTarget / longestSide)
              : math.min(1.0, 2400 / longestSide);
      final targetWidth = math.max(1, (originalWidth * ratio).round());
      final targetHeight = math.max(1, (originalHeight * ratio).round());
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      source = (await codec.getNextFrame()).image;
      descriptor.dispose();
      descriptor = null;
      buffer.dispose();
      buffer = null;

      final byteData = await source.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;
      final transformed = await compute(
        _transformOcrPixels,
        _OcrPixelTransformRequest(
          rgba: TransferableTypedData.fromList([
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
          ]),
          width: source.width,
          height: source.height,
          invertDarkBackground: invertDarkBackground,
          adaptiveThreshold: adaptiveThreshold,
          deskew: deskew,
          sharpen: sharpen,
          upscaleTarget: upscaleTarget,
          rotateDegrees: rotateDegrees,
          crisp: crisp,
          rotateBeforeEnhance: rotateBeforeEnhance,
          flattenIllumination: flattenIllumination,
          dewarp: dewarp,
        ),
        debugLabel: 'Prepare OCR pixels',
      );
      final pixels = transformed.pixels?.materialize().asUint8List();
      if (pixels == null) return null;
      // The crisp rescue changes the pixel size inside the isolate; the
      // other paths keep the decoded size.
      final resultWidth = transformed.resultWidth == 0
          ? source.width
          : transformed.resultWidth;
      final resultHeight = transformed.resultHeight == 0
          ? source.height
          : transformed.resultHeight;
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        resultWidth,
        resultHeight,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      normalized = await decoded.future;

      final turns = quarterTurns % 4;
      final rotated = turns.isOdd;
      final outputWidth = rotated ? resultHeight : resultWidth;
      final outputHeight = rotated ? resultWidth : resultHeight;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (turns == 1) {
        canvas
          ..translate(outputWidth.toDouble(), 0)
          ..rotate(math.pi / 2);
      } else if (turns == 2) {
        canvas
          ..translate(outputWidth.toDouble(), outputHeight.toDouble())
          ..rotate(math.pi);
      } else if (turns == 3) {
        canvas
          ..translate(0, outputHeight.toDouble())
          ..rotate(-math.pi / 2);
      }
      canvas.drawImage(
        normalized,
        ui.Offset.zero,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      output = await recorder.endRecording().toImage(outputWidth, outputHeight);
      final png = await output.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;

      final temp = await getTemporaryDirectory();
      final imageFile = File(
        p.join(
          temp.path,
          'schedule_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await imageFile.writeAsBytes(png.buffer.asUint8List(), flush: true);
      final scale = resultWidth / originalWidth;
      return PreparedOcrImage(
        file: imageFile,
        scale: scale,
        softness: transformed.softness,
        sourceLongestSide: longestSide,
        skewDegrees: transformed.skewDegrees,
        skewProminence: transformed.skewProminence,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Could not prepare an enhanced timetable image: $error\n$stackTrace',
      );
      return null;
    } finally {
      output?.dispose();
      normalized?.dispose();
      source?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

class PreparedOcrImage {
  const PreparedOcrImage({
    required this.file,
    required this.scale,
    this.softness = 0,
    this.sourceLongestSide = 0,
    this.skewDegrees = 0,
    this.skewProminence = 0,
  });

  final File file;
  final double scale;

  /// Laplacian variance of the prepared grayscale (see
  /// [_OcrPixelTransformResult.softness]). Higher is crisper.
  final double softness;

  /// Longest side of the decoded source before any rescaling, so the scan
  /// cascade can gate rescues on tiny captures without re-decoding.
  final int sourceLongestSide;

  /// Projection-profile page tilt of the prepared grayscale (see
  /// [_OcrPixelTransformResult.skewDegrees]).
  final double skewDegrees;

  /// Confidence of [skewDegrees]; near 0 on straight pages.
  final double skewProminence;
}
