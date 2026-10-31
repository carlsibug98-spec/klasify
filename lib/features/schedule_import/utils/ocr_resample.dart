/// Production pixel resampling and rescue sharpening for the OCR scan
/// cascade, kept free of Flutter imports so the benchmark harness can run
/// the exact same code in the VM.
///
/// Round 10 findings (tesseract stand-in, six-fixture COR benchmark):
///  * the high-res rescue (2160 target) reads the small capture's room
///    column only when the decode-time upscale is Lanczos-quality and a
///    gentle unsharp follows the contrast enhancement; with the engine's
///    default resampler the same unsharp destroys the parse instead
///    (bicubic halos amplify into noise);
///  * the deskew rescue reads tilted pages best when the fine rotation
///    happens BEFORE the contrast enhancement.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Lanczos3 (a = 3) resample of an RGBA buffer from [srcWidth] x [srcHeight]
/// to [dstWidth] x [dstHeight], separable horizontal-then-vertical. Matches
/// the PIL `Image.LANCZOS` recipe the round-10 sweep calibrated on: for
/// upscales the support window is the raw a = 3 neighborhood (no downscale
/// sharpening floor). Resamples all four channels.
Uint8List lanczosResizeRgba(
  Uint8List rgba,
  int srcWidth,
  int srcHeight,
  int dstWidth,
  int dstHeight,
) {
  if (srcWidth == dstWidth && srcHeight == dstHeight) return rgba;
  final horizontal = _lanczosAxis(
    rgba,
    srcLength: srcWidth,
    dstLength: dstWidth,
    srcOther: srcHeight,
    inRowStride: srcWidth,
    inPixelStride: 1,
    outRowStride: dstWidth,
    outPixelStride: 1,
  );
  return _lanczosAxis(
    horizontal,
    srcLength: srcHeight,
    dstLength: dstHeight,
    srcOther: dstWidth,
    inRowStride: 1,
    inPixelStride: dstWidth,
    outRowStride: 1,
    outPixelStride: dstWidth,
  );
}

/// One separable Lanczos axis. The input holds srcOther rows of srcLength
/// pixels (row-major, 4 channels); the output holds srcOther rows of
/// dstLength pixels. inRowStride/inPixelStride step between input rows and
/// between pixels along the axis (in pixels); outRowStride/outPixelStride
/// do the same for the output.
Uint8List _lanczosAxis(
  Uint8List rgba, {
  required int srcLength,
  required int dstLength,
  required int srcOther,
  required int inRowStride,
  required int inPixelStride,
  required int outRowStride,
  required int outPixelStride,
}) {
  if (srcLength == dstLength) return rgba;
  final scale = dstLength / srcLength;
  final filterScale = scale < 1 ? 1 / scale : 1;
  final support = 3 * filterScale;
  final result = Uint8List(dstLength * srcOther * 4);

  // Precompute the per-output-pixel tap weights (at most ceil(2*support)+1).
  final maxTaps = (2 * support).ceil() + 1;
  final weights = Float64List(dstLength * maxTaps);
  final starts = Int32List(dstLength);
  final counts = Int32List(dstLength);
  for (var i = 0; i < dstLength; i++) {
    final center = (i + .5) / scale - .5;
    final start = math.max(0, (center - support + .5).floor());
    final end = math.min(srcLength - 1, (center + support - .5).ceil());
    var sum = 0.0;
    var count = 0;
    for (var s = start; s <= end && count < maxTaps; s++, count++) {
      final w = _lanczos3((s - center) / filterScale);
      weights[i * maxTaps + count] = w;
      sum += w;
    }
    if (sum != 0) {
      for (var c = 0; c < count; c++) {
        weights[i * maxTaps + c] /= sum;
      }
    }
    starts[i] = start;
    counts[i] = count;
  }

  for (var row = 0; row < srcOther; row++) {
    final inRowBytes = row * inRowStride * 4;
    final inStrideBytes = inPixelStride * 4;
    final outRowBytes = row * outRowStride * 4;
    final outStrideBytes = outPixelStride * 4;
    for (var i = 0; i < dstLength; i++) {
      final count = counts[i];
      final start = starts[i];
      final wBase = i * maxTaps;
      final inBase = inRowBytes + start * inStrideBytes;
      final outBase = outRowBytes + i * outStrideBytes;
      for (var channel = 0; channel < 4; channel++) {
        var acc = 0.0;
        for (var c = 0; c < count; c++) {
          acc +=
              weights[wBase + c] * rgba[inBase + c * inStrideBytes + channel];
        }
        result[outBase + channel] = acc.round().clamp(0, 255);
      }
    }
  }
  return result;
}

double _lanczos3(double x) {
  if (x == 0) return 1;
  if (x.abs() >= 3) return 0;
  final px = math.pi * x;
  return 3 * math.sin(px) * math.sin(px / 3) / (px * px);
}

/// Gentle unsharp mask mirroring PIL's `UnsharpMask(radius: 2, percent: 35,
/// threshold: 2)`, the round-10 winner on the small-capture rescue: a
/// gaussian low-pass (Pillow's three-box approximation), then
/// `out = in + amount * (in - blur)` wherever `|in - blur| > threshold`.
/// Runs on the shared grayscale value (the rescue buffers are gray in RGB),
/// writing all three channels. Returns a new buffer; the input is untouched.
Uint8List softUnsharpRgba(
  Uint8List rgba,
  int width,
  int height, {
  double sigma = 2.0,
  double percent = 35.0,
  double threshold = 2.0,
}) {
  final blurred = _gaussianBlurGray(rgba, width, height, sigma: sigma);
  final amount = percent / 100;
  final out = Uint8List(rgba.length);
  for (var pixel = 0; pixel < width * height; pixel++) {
    final offset = pixel * 4;
    final value = rgba[offset];
    final low = blurred[pixel];
    final diff = value - low;
    var corrected = value;
    if (diff > threshold || -diff > threshold) {
      corrected = (value + amount * diff).round().clamp(0, 255);
    }
    out[offset] = corrected;
    out[offset + 1] = corrected;
    out[offset + 2] = corrected;
    out[offset + 3] = 255;
  }
  return out;
}

/// Grayscale gaussian blur mirroring Pillow's C implementation: three box
/// blur passes whose widths approximate a gaussian of [sigma] (the classic
/// boxes-for-gauss algorithm), accumulated in float, with edge clamping.
/// Returns one byte per pixel.
Uint8List _gaussianBlurGray(
  Uint8List rgba,
  int width,
  int height, {
  required double sigma,
}) {
  final gray = Float32List(width * height);
  for (var pixel = 0; pixel < width * height; pixel++) {
    gray[pixel] = rgba[pixel * 4].toDouble();
  }
  final boxes = _boxesForGauss(sigma, 3);
  var front = gray;
  var back = Float32List(width * height);
  for (final box in boxes) {
    final r = ((box - 1) ~/ 2);
    if (r < 1) continue;
    _boxBlurGrayH(front, back, width, height, r);
    _boxBlurGrayV(back, front, width, height, r);
  }
  final out = Uint8List(width * height);
  for (var pixel = 0; pixel < width * height; pixel++) {
    out[pixel] = front[pixel].round().clamp(0, 255);
  }
  return out;
}

/// Pillow's boxes-for-gauss: n odd box widths approximating a gaussian of
/// [sigma] (well-known Ivan Kutskir algorithm, the one gaussian_blur.c uses).
List<int> _boxesForGauss(double sigma, int n) {
  final wIdeal = math.sqrt((12 * sigma * sigma / n) + 1);
  var wl = wIdeal.floor();
  if (wl % 2 == 0) wl--;
  final wu = wl + 2;
  final mIdeal =
      (12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4);
  final m = mIdeal.round();
  return [for (var i = 0; i < n; i++) i < m ? wl : wu];
}

/// One horizontal box pass, [r] = half width, sliding sum, edge clamped.
void _boxBlurGrayH(
  Float32List src,
  Float32List dst,
  int width,
  int height,
  int r,
) {
  final window = 2 * r + 1;
  final inv = 1.0 / window;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    var acc = src[row] * (r + 1);
    for (var x = 1; x <= r; x++) {
      acc += src[row + math.min(x, width - 1)];
    }
    for (var x = 0; x < width; x++) {
      dst[row + x] = acc * inv;
      final add = src[row + math.min(x + r + 1, width - 1)];
      final sub = src[row + math.max(x - r, 0)];
      acc += add - sub;
    }
  }
}

/// One vertical box pass, [r] = half width, sliding sum, edge clamped.
void _boxBlurGrayV(
  Float32List src,
  Float32List dst,
  int width,
  int height,
  int r,
) {
  final window = 2 * r + 1;
  final inv = 1.0 / window;
  for (var x = 0; x < width; x++) {
    var acc = src[x] * (r + 1);
    for (var y = 1; y <= r; y++) {
      acc += src[math.min(y, height - 1) * width + x];
    }
    for (var y = 0; y < height; y++) {
      dst[y * width + x] = acc * inv;
      final add = src[math.min(y + r + 1, height - 1) * width + x];
      final sub = src[math.max(y - r, 0) * width + x];
      acc += add - sub;
    }
  }
}
