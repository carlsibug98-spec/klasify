import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/adaptive_ocr_threshold.dart';
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
  });

  final TransferableTypedData rgba;
  final int width;
  final int height;
  final bool invertDarkBackground;
  final bool adaptiveThreshold;
  final bool deskew;
  final bool sharpen;

  /// Decode-time upscale floor: sources shorter than this are enlarged so
  /// thin glyphs keep enough pixels for the recognizer. The default matches
  /// the historical behavior; the scan cascade's high-res rescue raises it.
  final int upscaleTarget;

  /// Fine-angle correction applied after enhancement, counter-clockwise as
  /// displayed (PIL Image.rotate convention). Driven by the projection
  /// profile estimate the enhanced pass reports.
  final double rotateDegrees;
}

class _OcrPixelTransformResult {
  const _OcrPixelTransformResult(
    this.pixels, {
    this.softness = 0,
    this.skewDegrees = 0,
    this.skewProminence = 0,
  });

  final TransferableTypedData? pixels;

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
  final rgba = request.rgba.materialize().asUint8List();
  final total = request.width * request.height;
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
      _laplacianVariance(enhancedPixels, request.width, request.height);

  // The projection profile reads the enhanced page once per scan; variant
  // calls (sharpen, rotate, threshold, invert) skip it - their results are
  // either unusable for the profile or already carry the angle from the
  // enhanced pass that triggered them.
  var skew = ProfileSkewEstimate.none;
  if (!request.invertDarkBackground &&
      !request.adaptiveThreshold &&
      !request.sharpen &&
      request.rotateDegrees.abs() < .05) {
    skew = estimateSkewProfile(
      gray: enhancedGray,
      width: request.width,
      height: request.height,
    );
  }

  Uint8List pixels;
  if (request.sharpen) {
    // Unsharp masking: add 1.5x the high-frequency residue the 3x3 gaussian
    // removes. Recovers glyph edges on out-of-focus phone photos; on sharp
    // photos it only amplifies noise, which is why the cascade gates it on
    // the softness metric instead of running it unconditionally.
    pixels = _unsharpRgba(enhancedPixels, request.width, request.height);
  } else {
    pixels = enhancedPixels;
  }

  var thresholded = request.adaptiveThreshold
      ? adaptiveThresholdRgba(pixels, request.width, request.height)
      : pixels;

  if (request.rotateDegrees.abs() >= .05) {
    thresholded = rotateRgbaBuffer(
      thresholded,
      request.width,
      request.height,
      request.rotateDegrees,
    );
  }

  if (request.deskew) {
    final deskewed = _deskewGrayscaleBuffer(
      thresholded,
      request.width,
      request.height,
    );
    if (deskewed != null) {
      return _OcrPixelTransformResult(
        TransferableTypedData.fromList([deskewed]),
        softness: softness,
        skewDegrees: skew.degrees,
        skewProminence: skew.prominence,
      );
    }
  }
  return _OcrPixelTransformResult(
    TransferableTypedData.fromList([thresholded]),
    softness: softness,
    skewDegrees: skew.degrees,
    skewProminence: skew.prominence,
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
      final ratio = longestSide < upscaleTarget
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
        ),
        debugLabel: 'Prepare OCR pixels',
      );
      final pixels = transformed.pixels?.materialize().asUint8List();
      if (pixels == null) return null;
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        source.width,
        source.height,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      normalized = await decoded.future;

      final turns = quarterTurns % 4;
      final rotated = turns.isOdd;
      final outputWidth = rotated ? normalized.height : normalized.width;
      final outputHeight = rotated ? normalized.width : normalized.height;
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
      final scale = normalized.width / originalWidth;
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
