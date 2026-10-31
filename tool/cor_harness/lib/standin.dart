/// Mirror of the bench5/bench6 tesseract stand-in: runs the tesseract CLI the
/// exact same way (`tsv --psm 11`, level-5 words with conf >= 0, line-group
/// reconstruction with the 1.1x line-height merge) and produces OCR regions
/// with bounding boxes, the same shape the native PP-OCR engine returns.
library;

import 'dart:io';
import 'dart:math' as math;

class OcrRegion {
  OcrRegion({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
}

class _Word {
  const _Word(
    this.block,
    this.par,
    this.line,
    this.left,
    this.top,
    this.w,
    this.h,
    this.conf,
    this.text,
  );

  final int block;
  final int par;
  final int line;
  final int left;
  final int top;
  final int w;
  final int h;
  final double conf;
  final String text;
}

/// Runs tesseract and returns line-level regions, mirroring
/// `_TesseractOcrPlatform.recognize` in bench5/bench6.
List<OcrRegion> tesseractRegions(String imagePath) {
  final result = Process.runSync('tesseract', [
    imagePath,
    'stdout',
    'tsv',
    '--psm',
    '11',
  ]);
  final words = <_Word>[];
  for (final line in (result.stdout as String).split('\n').skip(1)) {
    if (line.trim().isEmpty) continue;
    final f = line.split('\t');
    if (f.length < 12) continue;
    if (f[0] != '5') continue;
    final text = f[11].trim();
    final conf = double.tryParse(f[10]) ?? -1;
    if (text.isEmpty || conf < 0) continue;
    words.add(
      _Word(
        int.parse(f[2]),
        int.parse(f[3]),
        int.parse(f[4]),
        int.parse(f[6]),
        int.parse(f[7]),
        int.parse(f[8]),
        int.parse(f[9]),
        conf,
        text,
      ),
    );
  }
  final groups = <String, List<_Word>>{};
  for (final w in words) {
    groups.putIfAbsent('${w.block}-${w.par}-${w.line}', () => []).add(w);
  }
  final regions = <OcrRegion>[];
  for (final ws in groups.values) {
    ws.sort((a, b) => a.left.compareTo(b.left));
    final heights = ws.map((w) => w.h).toList()..sort();
    final hMed = heights[heights.length ~/ 2].toDouble();
    final runs = <List<_Word>>[
      [ws.first],
    ];
    for (final w in ws.skip(1)) {
      final gap = w.left - (runs.last.last.left + runs.last.last.w);
      if (gap > 1.1 * hMed) {
        runs.add([w]);
      } else {
        runs.last.add(w);
      }
    }
    for (final run in runs) {
      final text = run.map((w) => w.text).join(' ').trim();
      if (text.isEmpty) continue;
      final left = run.map((w) => w.left).reduce(math.min).toDouble();
      final top = run.map((w) => w.top).reduce(math.min).toDouble();
      final right =
          run.map((w) => w.left + w.w).reduce(math.max).toDouble();
      final bottom =
          run.map((w) => w.top + w.h).reduce(math.max).toDouble();
      final conf =
          run.map((w) => w.conf).reduce((a, b) => a + b) / run.length / 100;
      regions.add(
        OcrRegion(
          text: text,
          confidence: conf,
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        ),
      );
    }
  }
  return regions;
}

/// Verbatim mirror of `ScheduleOcrService._joinOcrRegions` (banding by
/// vertical center with ` | ` separators), so the harness text is byte-for-
/// byte what the service would hand the parser chain. Since round 12 the
/// band reference also follows a least-squares tilt through the accepted
/// word centers, so a curled page's right-hand columns stay in their row.
String joinOcrRegions(List<OcrRegion> regions) {
  final sorted = regions.toList()
    ..sort((a, b) {
      final vertical = a.centerY.compareTo(b.centerY);
      return vertical == 0 ? a.left.compareTo(b.left) : vertical;
    });
  final lines = <String>[];
  var bandCenter = 0.0;
  var bandHeight = 0.0;
  var band = <OcrRegion>[];
  var bandSumX = 0.0;
  var bandSumY = 0.0;
  var bandSumXX = 0.0;
  var bandSumXY = 0.0;
  void flushBand() {
    if (band.isEmpty) return;
    band.sort((a, b) => a.left.compareTo(b.left));
    lines.add(band.map((region) => region.text.trim()).join(' | '));
    band = <OcrRegion>[];
    bandCenter = 0;
    bandHeight = 0;
    bandSumX = 0;
    bandSumY = 0;
    bandSumXX = 0;
    bandSumXY = 0;
  }

  for (final region in sorted) {
    final center = region.centerY;
    var reference = bandCenter;
    if (band.length >= 2) {
      final n = band.length.toDouble();
      final denominator = n * bandSumXX - bandSumX * bandSumX;
      if (denominator > 1e-9) {
        final slope =
            ((n * bandSumXY - bandSumX * bandSumY) / denominator)
                .clamp(-.35, .35)
                .toDouble();
        final meanX = bandSumX / n;
        final predicted = bandCenter + slope * (region.centerX - meanX);
        if (predicted > reference) reference = predicted;
      }
    }
    if (band.isNotEmpty &&
        center - reference >
            math.max(5.0, math.min(region.height, bandHeight) * .6)) {
      flushBand();
    }
    if (band.isEmpty) {
      bandCenter = center;
      bandHeight = region.height;
    } else {
      bandCenter = (bandCenter * band.length + center) / (band.length + 1);
      bandHeight =
          (bandHeight * band.length + region.height) / (band.length + 1);
    }
    band.add(region);
    bandSumX += region.centerX;
    bandSumY += center;
    bandSumXX += region.centerX * region.centerX;
    bandSumXY += region.centerX * center;
  }
  flushBand();
  return lines.join('\n');
}

class RegionDrift {
  const RegionDrift(this.drift, this.fired);

  final double drift;
  final bool fired;
}

/// Verbatim mirror of `ScheduleOcrService._regionColumnDrift` (round 12):
/// left-vs-right column drift of the word boxes, so the harness can emulate
/// the production stop gate - a drifted page keeps the cascade running so
/// the dewarp rescue gets a chance at the auxiliary fields.
RegionDrift regionColumnDrift(List<OcrRegion> regions) {
  if (regions.length < 12) return const RegionDrift(0, false);
  var width = 0.0;
  var maxBottom = 0.0;
  var heightSum = 0.0;
  for (final region in regions) {
    if (region.right > width) width = region.right;
    if (region.bottom > maxBottom) maxBottom = region.bottom;
    heightSum += region.height;
  }
  final medianHeight = heightSum / regions.length;
  final bin = math.max(8.0, medianHeight / 2);
  final bins = (maxBottom / bin).ceil() + 1;
  final left = List<double>.filled(bins, 0);
  final right = List<double>.filled(bins, 0);
  var leftCount = 0;
  var rightCount = 0;
  for (final region in regions) {
    final index = (region.centerY / bin).floor();
    if (index < 0 || index >= bins) continue;
    if (region.centerX <= width * .45) {
      left[index] += 1;
      leftCount++;
    } else if (region.centerX >= width * .55) {
      right[index] += 1;
      rightCount++;
    }
  }
  if (leftCount < 6 || rightCount < 6) return const RegionDrift(0, false);
  smoothProfile(left);
  smoothProfile(right);
  final maxShift = (bins * .12).round().clamp(2, 400).toInt();
  var bestShift = 0;
  var bestScore = -1.0;
  var total = 0.0;
  var samples = 0;
  for (var shift = -maxShift; shift <= maxShift; shift++) {
    var score = 0.0;
    for (var i = 0; i < bins; i++) {
      final j = i + shift;
      if (j < 0 || j >= bins) continue;
      score += left[i] * right[j];
    }
    total += score;
    samples++;
    if (score > bestScore) {
      bestScore = score;
      bestShift = shift;
    }
  }
  final prominence =
      samples == 0 || total <= 0 ? 0.0 : bestScore / (total / samples);
  final drift = bestShift * bin;
  final fired =
      prominence >= 1.5 && drift.abs() >= math.max(9.0, medianHeight * .5);
  return RegionDrift(drift, fired);
}

/// Verbatim mirror of `ScheduleOcrService._smoothProfile`.
void smoothProfile(List<double> profile) {
  var previous = profile[0];
  for (var i = 0; i < profile.length; i++) {
    final current = profile[i];
    final next = i + 1 < profile.length ? profile[i + 1] : current;
    profile[i] = (previous + 2 * current + next) / 4;
    previous = current;
  }
}
