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
/// byte what the service would hand the parser chain.
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
  void flushBand() {
    if (band.isEmpty) return;
    band.sort((a, b) => a.left.compareTo(b.left));
    lines.add(band.map((region) => region.text.trim()).join(' | '));
    band = <OcrRegion>[];
    bandCenter = 0;
    bandHeight = 0;
  }

  for (final region in sorted) {
    final center = region.centerY;
    if (band.isNotEmpty &&
        center - bandCenter >
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
  }
  flushBand();
  return lines.join('\n');
}
