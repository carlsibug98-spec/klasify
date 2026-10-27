import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/schedule_text_parser.dart';
import '../utils/ocr_image_size.dart';
import '../utils/timetable_clock_ticks.dart';
import '../utils/timetable_grid_geometry.dart';
import '../utils/timetable_grid_pixels.dart';
import '../utils/timetable_parser.dart';
import 'ocr_image_preprocessor.dart';

class _GridPixelAnalysisRequest {
  const _GridPixelAnalysisRequest({
    required this.pixels,
    required this.width,
    required this.height,
    required this.sortedDays,
    required this.headers,
  });

  final TransferableTypedData pixels;
  final int width;
  final int height;
  final List<int> sortedDays;
  final Map<int, double> headers;
}

TimetableGridPixelAnalysis _analyzeGridPixelsInBackground(
  _GridPixelAnalysisRequest request,
) => analyzeTimetableGridPixels(
  pixels: request.pixels.materialize().asUint8List(),
  width: request.width,
  height: request.height,
  sortedDays: request.sortedDays,
  headers: request.headers,
);

/// Reads weekday headers, time rules, and class cells from weekly grid images.
class TimetableGridScanner {
  TimetableGridScanner({required this.recognize, required this._preprocessor});

  final Future<OcrRunResult> Function(String path) recognize;
  final OcrImagePreprocessor _preprocessor;

  static bool _sameOcrRegion(_SpatialText first, _SpatialText second) {
    final overlapWidth =
        math.min(first.box.right, second.box.right) -
        math.max(first.box.left, second.box.left);
    final overlapHeight =
        math.min(first.box.bottom, second.box.bottom) -
        math.max(first.box.top, second.box.top);
    if (overlapWidth <= 0 || overlapHeight <= 0) return false;

    final intersection = overlapWidth * overlapHeight;
    final firstArea = first.box.width * first.box.height;
    final secondArea = second.box.width * second.box.height;
    final smallerArea = math.min(firstArea, secondArea);
    return smallerArea > 0 && intersection / smallerArea >= .55;
  }

  static bool _preferOcrCandidate(
    _SpatialText candidate,
    _SpatialText current,
  ) {
    final confidenceDifference = candidate.confidence - current.confidence;
    if (confidenceDifference > .1) return true;
    if (confidenceDifference < -.1) return false;
    return candidate.text.trim().length > current.text.trim().length;
  }

  static List<_SpatialText> _mergeLineFragments(List<_SpatialText> blocks) {
    final ordered = blocks.toList()
      ..sort((a, b) {
        final vertical = a.box.center.dy.compareTo(b.box.center.dy);
        return vertical == 0 ? a.box.left.compareTo(b.box.left) : vertical;
      });
    final lines = <List<_SpatialText>>[];
    for (final block in ordered) {
      if (lines.isEmpty) {
        lines.add([block]);
        continue;
      }
      final previousLine = lines.last;
      final previousCenter =
          previousLine
              .map((part) => part.box.center.dy)
              .reduce((a, b) => a + b) /
          previousLine.length;
      final previousHeight = previousLine
          .map((part) => part.box.height)
          .reduce((a, b) => a < b ? a : b);
      final sameBaseline =
          (block.box.center.dy - previousCenter).abs() <=
          math.min(previousHeight, block.box.height) * .65;
      if (sameBaseline) {
        previousLine.add(block);
      } else {
        lines.add([block]);
      }
    }

    return lines.map((line) {
      line.sort((a, b) => a.box.left.compareTo(b.box.left));
      final left = line.map((part) => part.box.left).reduce(math.min);
      final top = line.map((part) => part.box.top).reduce(math.min);
      final right = line.map((part) => part.box.right).reduce(math.max);
      final bottom = line.map((part) => part.box.bottom).reduce(math.max);
      final confidence =
          line.map((part) => part.confidence).reduce((a, b) => a + b) /
          line.length;
      return _SpatialText(
        line
            .map((part) => part.text.trim())
            .where((text) => text.isNotEmpty)
            .join(' '),
        ui.Rect.fromLTRB(left, top, right, bottom),
        confidence,
      );
    }).toList();
  }

  /// Geometry-aware fallback for weekly timetable screenshots. Unlike a plain
  /// OCR string, this keeps weekday columns and uses the table's horizontal
  /// rules to estimate the start/end slot for each class cell.
  ///
  /// When [stats] is provided, it is filled with what the scan read, so the
  /// caller can judge whether rotated rescans (a purely ORIENTATION fix) could
  /// still add anything.
  Future<List<ParsedTimetableRow>> scan(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
    GridScanStats? stats,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    if (cancelled()) return [];
    onProgress(.09, 'Loading the timetable image');
    final bytes = await File(path).readAsBytes();
    if (cancelled()) return [];
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    late final int sourceWidth;
    late final int targetWidth;
    late final int targetHeight;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      sourceWidth = descriptor.width;
      final size = ocrRasterSize(descriptor.width, descriptor.height);
      targetWidth = size.width;
      targetHeight = size.height;
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    final bitmap = frame.image;
    final data = await bitmap.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      bitmap.dispose();
      codec.dispose();
      return [];
    }
    final w = bitmap.width;
    final h = bitmap.height;
    final pixels = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    File? enlargedOcrFile;
    PreparedOcrImage? enhancedOcrImage;
    PreparedOcrImage? adaptiveOcrImage;
    PreparedOcrImage? invertedOcrImage;
    File? boundedOcrFile;
    final columnOcrFiles = <File>[];
    try {
      if (cancelled()) return [];
      onProgress(.12, 'Reading the full timetable image');
      var recognitionPath = path;
      var recognitionScale = sourceWidth / w;
      if (recognitionScale > 1.001) {
        final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) return [];
        final temp = await getTemporaryDirectory();
        boundedOcrFile = File(
          p.join(
            temp.path,
            'schedule_ocr_bounded_${DateTime.now().microsecondsSinceEpoch}.png',
          ),
        );
        await boundedOcrFile.writeAsBytes(
          png.buffer.asUint8List(),
          flush: true,
        );
        recognitionPath = boundedOcrFile.path;
        recognitionScale = 1;
      }
      final result = await recognize(recognitionPath);
      if (cancelled()) return [];
      // Keep Paddle's detected text boxes so weekday columns and timetable
      // cells can be mapped from their image coordinates.
      final lines = <_SpatialText>[];
      void collectLines(
        OcrRunResult recognition, {
        double scale = 1,
        double offsetX = 0,
        double offsetY = 0,
        List<_SpatialText>? destination,
      }) {
        final collectedLines = destination ?? lines;
        for (final region in recognition.results) {
          final box = region.boundingBox;
          final scaledBox = ui.Rect.fromLTRB(
            box.left / scale + offsetX,
            box.top / scale + offsetY,
            box.right / scale + offsetX,
            box.bottom / scale + offsetY,
          );
          final normalized = region.text
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (normalized.isEmpty || scaledBox.isEmpty) continue;
          final candidate = _SpatialText(
            region.text,
            scaledBox,
            region.confidence,
          );
          final duplicateIndex = collectedLines.indexWhere(
            (existing) => _sameOcrRegion(existing, candidate),
          );
          if (duplicateIndex < 0) {
            collectedLines.add(candidate);
          } else if (_preferOcrCandidate(
            candidate,
            collectedLines[duplicateIndex],
          )) {
            // OCR retries often return a fragment and a fuller reading for
            // the same text region. Keep one hypothesis, preferring a clear
            // confidence win or the more complete reading when scores are
            // close, instead of concatenating both as separate class text.
            collectedLines[duplicateIndex] = candidate;
          }
        }
      }

      collectLines(result, scale: recognitionScale);
      onProgress(.17, 'Checking text positions');
      enhancedOcrImage = await _preprocessor.prepare(path);
      if (cancelled()) return [];
      if (enhancedOcrImage != null) {
        onProgress(.2, 'Enhancing image contrast');
        try {
          final enhancedResult = await recognize(enhancedOcrImage.file.path);
          if (cancelled()) return [];
          collectLines(
            enhancedResult,
            scale: enhancedOcrImage.scale * sourceWidth / w,
          );
          onProgress(.25, 'Contrast-enhanced scan complete');
        } catch (error) {
          debugPrint('Enhanced grid OCR retry failed: $error');
        }
      }
      adaptiveOcrImage = await _preprocessor.prepare(
        path,
        adaptiveThreshold: true,
      );
      if (cancelled()) return [];
      if (adaptiveOcrImage != null) {
        onProgress(.27, 'Checking a high-contrast version');
        try {
          final adaptiveResult = await recognize(adaptiveOcrImage.file.path);
          if (cancelled()) return [];
          collectLines(
            adaptiveResult,
            scale: adaptiveOcrImage.scale * sourceWidth / w,
          );
          onProgress(.32, 'High-contrast scan complete');
        } catch (error) {
          debugPrint('Adaptive-threshold grid OCR retry failed: $error');
        }
      }
      invertedOcrImage = await _preprocessor.prepare(
        path,
        invertDarkBackground: true,
      );
      if (cancelled()) return [];
      if (invertedOcrImage != null) {
        onProgress(.33, 'Checking a dark-background version');
        try {
          final invertedResult = await recognize(invertedOcrImage.file.path);
          if (cancelled()) return [];
          collectLines(
            invertedResult,
            scale: invertedOcrImage.scale * sourceWidth / w,
          );
        } catch (error) {
          debugPrint('Dark-background grid OCR retry failed: $error');
        }
      }
      // A second PaddleOCR pass on small, enlarged screenshots recovers short
      // labels that can be missed at the original image resolution. Scale its text
      // bounds back to the original coordinates before mapping timetable cells.
      if (!cancelled() && w < 1800 && h < 1800) {
        onProgress(.34, 'Enlarging small timetable text');
        final enlargementScale = math
            .min(2.0, maxOcrRasterSide / math.max(w, h))
            .toDouble();
        ui.Codec? enlargedCodec;
        ui.Image? enlargedBitmap;
        try {
          enlargedCodec = await ui.instantiateImageCodec(
            bytes,
            targetWidth: (w * enlargementScale).round(),
            targetHeight: (h * enlargementScale).round(),
          );
          enlargedBitmap = (await enlargedCodec.getNextFrame()).image;
          final png = await enlargedBitmap.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png != null) {
            final temp = await getTemporaryDirectory();
            final ocrFile = File(
              p.join(
                temp.path,
                'schedule_ocr_enlarged_${DateTime.now().microsecondsSinceEpoch}.png',
              ),
            );
            enlargedOcrFile = ocrFile;
            await ocrFile.writeAsBytes(png.buffer.asUint8List(), flush: true);
            final enlargedResult = await recognize(ocrFile.path);
            if (cancelled()) return [];
            collectLines(
              enlargedResult,
              scale: enlargementScale * sourceWidth / w,
            );
            onProgress(.38, 'Enlarged text scan complete');
          }
        } catch (e) {
          debugPrint('Enlarged timetable OCR retry failed: $e');
        } finally {
          enlargedBitmap?.dispose();
          enlargedCodec?.dispose();
        }
      }
      if (lines.isEmpty) return [];
      if (stats != null) {
        stats
          ..lineCount = lines.length
          ..alnumChars = lines.fold<int>(
            0,
            (sum, line) =>
                sum + line.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length,
          )
          ..meanLineConfidence =
              lines.map((line) => line.confidence).reduce((a, b) => a + b) /
              lines.length;
      }
      String norm(String s) =>
          s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      bool isPlausibleCourseLabel(String value) {
        final words = value.split(RegExp(r'\s+'));
        if (words.isEmpty) return false;
        // OCR sometimes turns a room/professor fragment into its own class
        // when it lands between two horizontal grid rules. A one-word label
        // is accepted only when it looks like a course code, acronym, or
        // internally capitalized name. Lowercase fragments such as surnames
        // and connective words must stay attached to their neighboring cell.
        if (words.length == 1) {
          final word = words.single.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
          if (word.length < 2 ||
              RegExp(
                r'^(?:and|or|the|of|to|in|at|on|lec|lecture|lab|room)$',
                caseSensitive: false,
              ).hasMatch(word)) {
            return false;
          }
          return RegExp(r'^[A-Z]{2,}[A-Z0-9]*$').hasMatch(word) ||
              RegExp(r'^[A-Z]+\d+[A-Z0-9]*$').hasMatch(word) ||
              RegExp(r'^[A-Za-z]+[A-Z][A-Za-z0-9]*$').hasMatch(word) ||
              RegExp(r'^[A-Z][a-z][A-Za-z0-9]*$').hasMatch(word);
        }
        // Reject OCR debris made mostly of punctuation or isolated digits,
        // while allowing ordinary course codes and mixed text.
        final meaningfulWords = words
            .where((word) => RegExp(r'[A-Za-z]{2,}').hasMatch(word))
            .length;
        return meaningfulWords >= 2 ||
            RegExp(r'^[A-Z]{2,}\d+[A-Z0-9]*$').hasMatch(value);
      }

      bool isClockArtifact(String value) =>
          RegExp(r'^[A-Z]:\d{2}$', caseSensitive: false).hasMatch(value);

      int? dayOf(String s) {
        final v = norm(s);
        if (v.contains('monday')) return 1;
        if (v.contains('tuesday')) return 2;
        if (v.contains('wednesday')) return 3;
        if (v.contains('thursday')) return 4;
        if (v.contains('friday')) return 5;
        if (v.contains('saturday')) return 6;
        if (v.contains('sunday')) return 7;
        if (v == 'mon') return 1;
        if (v == 'tue' || v == 'tues') return 2;
        if (v == 'wed') return 3;
        if (v == 'thu' || v == 'thur' || v == 'thurs') return 4;
        if (v == 'fri') return 5;
        if (v == 'sat') return 6;
        if (v == 'sun') return 7;
        if (v == 'm') return 1;
        if (v == 't') return 2;
        if (v == 'w') return 3;
        if (v == 'th' || v == 'r') return 4;
        if (v == 'f') return 5;
        if (v == 'sa' || v == 's') return 6;
        if (v == 'su' || v == 'u') return 7;
        return null;
      }

      final shortTHeaders =
          lines
              .where((line) => norm(line.text) == 't' && line.box.top < h * .22)
              .toList()
            ..sort((a, b) => a.box.center.dx.compareTo(b.box.center.dx));
      final headers = <int, double>{};
      // Collect every box that reads as a weekday so the header row can be
      // found even when a tall title block pushes it below the top 22%.
      final dayCandidates = <_SpatialText, int>{};
      for (final b in lines) {
        final d = dayOf(b.text);
        if (d != null) dayCandidates[b] = d;
      }
      for (final e in dayCandidates.entries) {
        if (norm(e.key.text) == 't' && shortTHeaders.length == 2) continue;
        if (e.key.box.top < h * .22) {
          headers[e.value] = e.key.box.center.dx;
        }
      }
      if (headers.length < 2 && dayCandidates.isNotEmpty) {
        // Fallback: cluster the weekday boxes by vertical center. The band
        // covering the most distinct weekdays is the printed header row,
        // wherever on the page it sits.
        final sorted = dayCandidates.keys.toList()
          ..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
        final bands = <List<_SpatialText>>[];
        for (final b in sorted) {
          if (bands.isNotEmpty &&
              (b.box.center.dy - bands.last.last.box.center.dy).abs() <=
                  math.max(8.0, b.box.height * 1.2)) {
            bands.last.add(b);
          } else {
            bands.add([b]);
          }
        }
        List<_SpatialText>? bestBand;
        var bestDays = 0;
        for (final band in bands) {
          final days = band.map((b) => dayCandidates[b]!).toSet();
          if (days.length > bestDays) {
            bestDays = days.length;
            bestBand = band;
          }
        }
        if (bestBand != null && bestDays >= 2) {
          for (final b in bestBand) {
            headers[dayCandidates[b]!] = b.box.center.dx;
          }
        }
      }
      if (shortTHeaders.length == 2) {
        headers[2] = shortTHeaders.first.box.center.dx;
        headers[4] = shortTHeaders.last.box.center.dx;
      }
      if (headers.length < 2) return [];
      final sortedDays = headers.keys.toList()
        ..sort((a, b) => headers[a]!.compareTo(headers[b]!));

      final gridTop = (h * .025).round().clamp(0, h - 1).toInt();
      final gridBottom = (h * .91).round().clamp(gridTop + 1, h).toInt();
      onProgress(.395, 'Analyzing timetable grid pixels');
      final pixelAnalysis = await compute(
        _analyzeGridPixelsInBackground,
        _GridPixelAnalysisRequest(
          pixels: TransferableTypedData.fromList([pixels]),
          width: w,
          height: h,
          sortedDays: sortedDays,
          headers: headers,
        ),
        debugLabel: 'Analyze timetable grid pixels',
      );
      if (cancelled()) return [];
      final bounds = pixelAnalysis.bounds;
      final leftEdge = pixelAnalysis.leftEdge;
      // Re-run OCR on each weekday column in isolation at higher resolution.
      // Small timetable labels need more pixels while neighboring columns must
      // stay separate.
      final columnLines = <_SpatialText>[];
      final columnLinesByDay = <int, List<_SpatialText>>{};
      for (var dayIndex = 0; dayIndex < sortedDays.length; dayIndex++) {
        if (cancelled()) return [];
        final day = sortedDays[dayIndex];
        onProgress(
          .4 + .025 * dayIndex / sortedDays.length,
          'Checking weekday columns (${dayIndex + 1} of ${sortedDays.length})',
        );
        final dayBounds = bounds[day]!;
        final cropLeft = (dayBounds[0] - 2).clamp(0, w - 1).toDouble();
        final cropRight = (dayBounds[1] + 2).clamp(cropLeft + 1, w).toDouble();
        final cropTop = gridTop.toDouble();
        final cropBottom = gridBottom.toDouble();
        final cropScale = math
            .min(
              4.0,
              maxOcrRasterSide /
                  math.max(cropRight - cropLeft, cropBottom - cropTop),
            )
            .toDouble();
        final cropWidth = ((cropRight - cropLeft) * cropScale).ceil();
        final cropHeight = ((cropBottom - cropTop) * cropScale).ceil();
        ui.Image? croppedImage;
        try {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawImageRect(
            bitmap,
            ui.Rect.fromLTRB(cropLeft, cropTop, cropRight, cropBottom),
            ui.Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
            Paint()..filterQuality = FilterQuality.high,
          );
          croppedImage = await recorder.endRecording().toImage(
            cropWidth,
            cropHeight,
          );
          final png = await croppedImage.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null) continue;
          final temp = await getTemporaryDirectory();
          final cropFile = File(
            p.join(
              temp.path,
              'schedule_ocr_column_${day}_${DateTime.now().microsecondsSinceEpoch}.png',
            ),
          );
          columnOcrFiles.add(cropFile);
          await cropFile.writeAsBytes(png.buffer.asUint8List(), flush: true);
          final cropResult = await recognize(cropFile.path);
          if (cancelled()) return [];
          final dayLines = <_SpatialText>[];
          collectLines(
            cropResult,
            scale: cropScale,
            offsetX: cropLeft,
            offsetY: cropTop,
            destination: dayLines,
          );
          columnLinesByDay[day] = dayLines;
          columnLines.addAll(dayLines);
        } catch (e) {
          debugPrint('Column $day timetable OCR retry failed: $e');
        } finally {
          croppedImage?.dispose();
        }
        onProgress(
          .4 + .025 * (dayIndex + 1) / sortedDays.length,
          'Checked weekday column ${dayIndex + 1} of ${sortedDays.length}',
        );
      }
      onProgress(.43, 'Weekday columns checked');
      // Read ONLY the first (start-time) column in the left gutter. The
      // timetable prints both start and end labels side-by-side; mixing both
      // columns creates duplicate/non-monotonic ticks and corrupts all times.
      final clock = RegExp(r'(\d{1,2})[.:](\d{2})');
      final clockCandidates = <List<double>>[];
      for (final b in lines) {
        if (b.box.center.dx >= leftEdge) continue;
        final m = clock.firstMatch(b.text);
        if (m == null) continue;
        final minute = parseOcrClockMinute(b.text);
        if (minute == null) continue;
        clockCandidates.add([
          b.box.center.dx,
          b.box.center.dy,
          minute.toDouble(),
        ]);
      }
      final clockX = clockCandidates.map((candidate) => candidate[0]).toList()
        ..sort();
      var startClockRight = double.infinity;
      // Find the largest horizontal gap between the two printed clock
      // columns. This adapts to screenshots with different left gutters and
      // avoids relying on a percentage of the full image width.
      var largestGap = 0.0;
      var largestGapIndex = -1;
      for (var i = 1; i < clockX.length; i++) {
        final gap = clockX[i] - clockX[i - 1];
        if (gap > largestGap) {
          largestGap = gap;
          largestGapIndex = i;
        }
      }
      if (largestGapIndex >= 0 && largestGap >= leftEdge * .08) {
        startClockRight =
            (clockX[largestGapIndex - 1] + clockX[largestGapIndex]) / 2;
      }
      final rawTicks = <List<double>>[];
      for (final candidate in clockCandidates) {
        if (candidate[0] <= startClockRight) {
          rawTicks.add([candidate[1], candidate[2]]);
        }
      }
      // Timetables that print no clock times at all often label rows with
      // period numbers ("P1".."P6", "Period 1".."Period 8") in the left
      // gutter. Synthesize a nominal rail from those labels (P1 = 08:00,
      // 60-minute periods - the same default the PDF list parser assumes)
      // so the grid path can still build rows. Every row built on this rail
      // is flagged for review because the times are assumed, not printed.
      var syntheticRail = false;
      // Gutter clock rails anchor labels at their own line centers, which
      // coincide with row centers. Synthesized rails should do the same:
      // when horizontal rules are known, a label belongs to the row band it
      // falls into, so its tick sits at that band's center. Without rules
      // (aesthetic grids that draw no row lines) the label center is the
      // best available anchor.
      final railRules =
          pixelAnalysis.timeRules.map((y) => y.toDouble()).toList()..sort();
      double tickYFor(double dy) {
        for (var i = 0; i + 1 < railRules.length; i++) {
          if (dy >= railRules[i] && dy < railRules[i + 1]) {
            return (railRules[i] + railRules[i + 1]) / 2;
          }
        }
        return dy;
      }

      if (rawTicks.isEmpty) {
        final periodLabel = RegExp(
          r'^\s*(?:P\.?\s*|Period\s+)(\d{1,2})\s*$',
          caseSensitive: false,
        );
        final periodTimes = const PeriodTimes();
        for (final b in lines) {
          if (b.box.center.dx >= leftEdge) continue;
          final match = periodLabel.firstMatch(b.text);
          final period = match == null ? null : int.tryParse(match.group(1)!);
          final minute = period == null ? null : periodTimes.startOf(period);
          if (minute == null) continue;
          rawTicks.add([tickYFor(b.box.center.dy), minute.toDouble()]);
        }
        if (rawTicks.map((tick) => tick[1]).toSet().length >= 2) {
          syntheticRail = true;
        } else {
          // Aesthetic and app-style schedules print the start time INSIDE
          // each cell and have no left gutter at all. Those printed starts
          // are real times, so they can anchor the axis: each cell's clock
          // marks its own row, consecutive rows form a monotonic rail, and
          // the usual 30-minute snapping still applies.
          rawTicks.clear();
          for (final b in lines) {
            if (b.box.center.dx < leftEdge) continue;
            if (b.box.center.dy < gridTop || b.box.center.dy > gridBottom) {
              continue;
            }
            final minute = parseOcrClockMinute(b.text);
            if (minute == null) continue;
            rawTicks.add([tickYFor(b.box.center.dy), minute.toDouble()]);
          }
          if (rawTicks.map((tick) => tick[1]).toSet().length < 2) {
            rawTicks.clear();
          }
        }
      }
      rawTicks.sort((a, b) => a[0].compareTo(b[0]));
      // Collapse OCR duplicates at nearly the same vertical position.
      final ticks = <List<double>>[];
      for (final tick in rawTicks) {
        if (ticks.isNotEmpty && (tick[0] - ticks.last[0]).abs() < 5) continue;
        var minute = tick[1];
        if (ticks.isNotEmpty) {
          while (minute <= ticks.last[1] && minute + 720 <= 24 * 60) {
            minute += 720;
          }
          // A label like 1:00 after 12:30 is the next hour, not 1 AM.
          while (minute < ticks.last[1] && minute + 1440 <= 24 * 60) {
            minute += 1440;
          }
        }
        ticks.add([tick[0], minute]);
      }
      final rowSpacing = inferTimetableRowSpacing(
        gridRulePositions: pixelAnalysis.timeRules
            .map((y) => y.toDouble())
            .toList(),
        ocrTickPositions: ticks.map((tick) => tick[0]).toList(),
        // A tall grid (few rows filling most of the image) legitimately has
        // row spacing well above 12% of the image height; .12 rejected whole
        // schedules whose hourly rows were exactly 12% (e.g. 120px rows on a
        // 1000px photo). 20% still rejects missing-label double gaps while
        // accepting every real single-row spacing.
        maxGap: h * .2,
      );
      if (ticks.isEmpty || rowSpacing == null) return [];
      final firstVisibleMinute = ticks.first[1].round();
      final halfRow = rowSpacing / 2;
      double? minuteAt(double y) {
        // Missing OCR labels must not change the physical half-hour row size.
        final sampleY = y + halfRow;
        if (ticks.length == 1) {
          return ticks.single[1] +
              (sampleY - ticks.single[0]) / rowSpacing * 30;
        }
        for (var i = 0; i < ticks.length - 1; i++) {
          final a = ticks[i], b = ticks[i + 1];
          if (sampleY >= a[0] && sampleY <= b[0] && b[0] > a[0]) {
            return a[1] + (sampleY - a[0]) / (b[0] - a[0]) * (b[1] - a[1]);
          }
        }
        final a = sampleY < ticks.first[0] ? ticks[0] : ticks[ticks.length - 2];
        final b = sampleY < ticks.first[0] ? ticks[1] : ticks.last;
        if (b[0] <= a[0]) return null;
        return a[1] + (sampleY - a[0]) / (b[0] - a[0]) * (b[1] - a[1]);
      }

      final rules = pixelAnalysis.rules;
      final strongRules = pixelAnalysis.strongRules;
      final textByDay = <int, List<_SpatialText>>{};
      for (final day in sortedDays) {
        final dayLines = <_SpatialText>[];
        void addUniqueLine(_SpatialText candidate) {
          final normalized = candidate.text
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final duplicateRegion = dayLines.any((existing) {
            final existingText = existing.text
                .toLowerCase()
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
            final sameText =
                existingText == normalized &&
                (existing.box.center.dx - candidate.box.center.dx).abs() < 8 &&
                (existing.box.center.dy - candidate.box.center.dy).abs() < 8;
            return sameText || _sameOcrRegion(existing, candidate);
          });
          if (!duplicateRegion) {
            dayLines.add(candidate);
          }
        }

        for (final line in columnLinesByDay[day] ?? const <_SpatialText>[]) {
          addUniqueLine(line);
        }
        for (final line in lines) {
          final nearestDay = sortedDays.reduce((best, candidate) {
            final bestDistance = (line.box.center.dx - headers[best]!).abs();
            final candidateDistance = (line.box.center.dx - headers[candidate]!)
                .abs();
            return candidateDistance < bestDistance ? candidate : best;
          });
          final dayBounds = bounds[day]!;
          final centerX = line.box.center.dx;
          if (nearestDay == day &&
              centerX >= dayBounds[0] &&
              centerX < dayBounds[1]) {
            addUniqueLine(line);
          }
        }
        textByDay[day] = dayLines;
      }

      // Group lines within each weekday before consulting row rules. A class
      // title or its room/professor can cross a horizontal rule, so assigning
      // every OCR box to the nearest ruled row first can split one class into
      // several false entries.
      final cellTexts = <String, List<_SpatialText>>{};
      final cellMeta = <String, List<int>>{};

      // Group nearby OCR lines into text blocks first. If a weekday column
      // contains multiple course labels, row rules between those labels still
      // separate them below.
      for (final day in sortedDays) {
        final blocks = (textByDay[day] ?? const <_SpatialText>[]).toList()
          ..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
        if (blocks.isEmpty) continue;
        final clusters = <List<_SpatialText>>[];
        for (final block in blocks) {
          if (clusters.isEmpty) {
            clusters.add([block]);
            continue;
          }
          final previous = clusters.last.last;
          final lineGap = block.box.top - previous.box.bottom;
          final maxLineHeight = block.box.height > previous.box.height
              ? block.box.height
              : previous.box.height;
          if (lineGap <= maxLineHeight * .65) {
            clusters.last.add(block);
          } else {
            clusters.add([block]);
          }
        }

        String labelText(_SpatialText block) => block.text
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .replaceAll(clock, ' ')
            // Bare-hour ranges ("7-8"), dotted clocks ("7.00"), and compact
            // military ranges ("0800-0930") are printed times too; leaving
            // them in the label merges them into the class name.
            .replaceAll(RegExp(r'\b\d{1,2}\s*(?:-|–|—|to)\s*\d{1,2}\b'), ' ')
            .replaceAll(RegExp(r'\b\d{1,2}\.\d{2}\b'), ' ')
            .replaceAll(RegExp(r'\b\d{3,4}\s*(?:-|–|—|to)\s*\d{3,4}\b'), ' ')
            .replaceAll(RegExp(r'\b(?:AM|PM)\b', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\bprof\.?(?=\s|$)', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        bool isCourseCluster(List<_SpatialText> cluster) {
          final ordered = _mergeLineFragments(cluster);
          // Paddle can return a professor's initial and surname as separate
          // boxes on the same line. Parse their combined text so the surname
          // is not mistaken for a second course when a grid rule falls nearby.
          final raw = ordered
              .map(labelText)
              .where((text) => text.isNotEmpty)
              .join(' ');
          if (raw.length < 2 ||
              RegExp(r'^\d+(?:\.\d+)?$').hasMatch(raw) ||
              isClockArtifact(raw) ||
              dayOf(raw) != null) {
            return false;
          }
          final subject = ScheduleTextDetails.parse(raw).subject;
          final normalizedSubject = subject
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (const {
            'class schedule',
            'course',
            'day',
            'instructor',
            'professor',
            'room',
            'schedule',
            'subject',
            'time',
          }.contains(normalizedSubject)) {
            return false;
          }
          return isPlausibleCourseLabel(subject);
        }

        bool isTableMetadataCluster(List<_SpatialText> cluster) {
          final raw = _mergeLineFragments(
            cluster,
          ).map(labelText).where((text) => text.isNotEmpty).join(' ').trim();
          final normalized = raw
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
              .trim();
          return raw.isEmpty ||
              dayOf(raw) != null ||
              isClockArtifact(raw) ||
              const {
                'class schedule',
                'course',
                'day',
                'instructor',
                'professor',
                'schedule',
                'subject',
                'time',
              }.contains(normalized);
        }

        final courseClusterIndices = <int>[];
        for (var i = 0; i < clusters.length; i++) {
          if (isCourseCluster(clusters[i])) courseClusterIndices.add(i);
        }
        if (courseClusterIndices.isEmpty) continue;

        bool hasRuleBetween(int previousIndex, int nextIndex) {
          final previousBottom = clusters[previousIndex]
              .map((block) => block.box.bottom)
              .reduce((a, b) => a > b ? a : b);
          final nextTop = clusters[nextIndex]
              .map((block) => block.box.top)
              .reduce((a, b) => a < b ? a : b);
          final whitespace = nextTop - previousBottom;
          if (whitespace <= 0) return false;
          final margin = whitespace * .2;
          return rules[day]!.any(
            (y) => y > previousBottom + margin && y < nextTop - margin,
          );
        }

        final splitBefore = <int>{};
        for (var i = 1; i < courseClusterIndices.length; i++) {
          final previous = courseClusterIndices[i - 1];
          final next = courseClusterIndices[i];
          if (hasRuleBetween(previous, next)) splitBefore.add(next);
        }

        final outputGroups = <List<_SpatialText>>[];
        final groupForCourseCluster = <int, int>{};
        var groupIndex = -1;
        for (final clusterIndex in courseClusterIndices) {
          if (groupIndex < 0 || splitBefore.contains(clusterIndex)) {
            groupIndex++;
            outputGroups.add(<_SpatialText>[]);
          }
          groupForCourseCluster[clusterIndex] = groupIndex;
          outputGroups[groupIndex].addAll(clusters[clusterIndex]);
        }
        for (var i = 0; i < clusters.length; i++) {
          final assignedGroup = groupForCourseCluster[i];
          if (assignedGroup != null) continue;
          if (isTableMetadataCluster(clusters[i])) continue;
          var nearestCourse = courseClusterIndices.first;
          var nearestDistance = double.infinity;
          final center =
              clusters[i]
                  .map((block) => block.box.center.dy)
                  .reduce((a, b) => a + b) /
              clusters[i].length;
          for (final courseIndex in courseClusterIndices) {
            final courseCenter =
                clusters[courseIndex]
                    .map((block) => block.box.center.dy)
                    .reduce((a, b) => a + b) /
                clusters[courseIndex].length;
            final distance = (center - courseCenter).abs();
            if (distance < nearestDistance) {
              nearestCourse = courseIndex;
              nearestDistance = distance;
            }
          }
          outputGroups[groupForCourseCluster[nearestCourse]!].addAll(
            clusters[i],
          );
        }

        for (
          var groupIndex = 0;
          groupIndex < outputGroups.length;
          groupIndex++
        ) {
          final cluster = outputGroups[groupIndex];
          final clusterTop = cluster
              .map((block) => block.box.top)
              .reduce((a, b) => a < b ? a : b);
          final clusterBottom = cluster
              .map((block) => block.box.bottom)
              .reduce((a, b) => a > b ? a : b);
          var top = gridTop.toDouble();
          var bottom = gridBottom.toDouble();
          var smallestEnclosingSpan = double.infinity;
          for (final candidates in [strongRules[day]!, rules[day]!]) {
            int? upper, lower;
            for (final y in candidates) {
              if (y <= clusterTop - 2) upper = y;
              if (y >= clusterBottom + 2) {
                lower = y;
                break;
              }
            }
            if (upper == null || lower == null || lower <= upper) continue;
            final span = (lower - upper).toDouble();
            if (span < smallestEnclosingSpan) {
              top = upper.toDouble();
              bottom = lower.toDouble();
              smallestEnclosingSpan = span;
            }
          }
          if (bottom <= top) continue;
          final sm = minuteAt(top);
          final em = minuteAt(bottom);
          if (sm == null || em == null) continue;
          int snap(double value) =>
              ((value / 30).round() * 30).clamp(0, 24 * 60).toInt();
          final start = snap(sm);
          // OCR can mistake text in the weekday/header band for a class and
          // map it into a phantom half-hour before the schedule begins. The
          // first printed time marks the earliest valid slot in the grid.
          if (start < firstVisibleMinute) continue;
          var end = snap(em);
          if (end <= start && start < 24 * 60) end = start + 30;
          if (end <= start || end - start > 6 * 60) continue;
          final key = '$day|$start|$end';
          for (final block in _mergeLineFragments(cluster)) {
            final raw = labelText(block);
            if (raw.length < 2 ||
                RegExp(r'^\d+(?:\.\d+)?$').hasMatch(raw) ||
                isClockArtifact(raw) ||
                dayOf(raw) != null) {
              continue;
            }
            final classText = raw;
            if (classText.length < 2 ||
                RegExp(r'^\d+(?:\.\d+)?$').hasMatch(classText)) {
              continue;
            }
            final classWords = classText.toLowerCase().split(RegExp(r'\s+'));
            if (classWords.every(
              (word) =>
                  RegExp(r'^[a-z]\.?$').hasMatch(word) ||
                  const {
                    'and',
                    'or',
                    'the',
                    'of',
                    'to',
                    'in',
                    'at',
                    'on',
                  }.contains(word),
            )) {
              continue;
            }
            cellTexts
                .putIfAbsent(key, () => <_SpatialText>[])
                .add(_SpatialText(classText, block.box, block.confidence));
            cellMeta[key] = [day, start, end];
          }
        }
      }

      final output = <ParsedTimetableRow>[];
      final seen = <String>{};
      for (final entry in cellTexts.entries) {
        final blocks = entry.value
          ..sort(
            (a, b) => a.box.top == b.box.top
                ? a.box.left.compareTo(b.box.left)
                : a.box.top.compareTo(b.box.top),
          );
        // Suppress repeated OCR phrases even when word spacing differs, without
        // relying on course-specific names.
        final uniqueBlocks = <String>[];
        String normalizeOcrWord(String word) =>
            word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        bool containsPhrase(List<String> words, String phrase) {
          for (var start = 0; start < words.length; start++) {
            var candidate = '';
            for (var end = start; end < words.length; end++) {
              candidate += normalizeOcrWord(words[end]);
              if (candidate == phrase) return true;
              if (!phrase.startsWith(candidate)) break;
            }
          }
          return false;
        }

        for (final block in blocks) {
          final text = block.text.replaceAll('\n', ' ').trim();
          final words = text.split(RegExp(r'\s+'));
          final normalized = words.map(normalizeOcrWord).join();
          if (normalized.isEmpty) continue;

          final duplicatePhrase = uniqueBlocks.any((accepted) {
            final acceptedWords = accepted.split(RegExp(r'\s+'));
            final acceptedNormalized = acceptedWords
                .map(normalizeOcrWord)
                .join();
            return acceptedNormalized == normalized ||
                containsPhrase(acceptedWords, normalized) ||
                containsPhrase(words, acceptedNormalized);
          });
          if (duplicatePhrase) {
            continue;
          }
          uniqueBlocks.add(text);
        }
        final meta = cellMeta[entry.key]!;
        final day = meta[0], start = meta[1], end = meta[2];
        final details = ScheduleTextDetails.parse(uniqueBlocks.join(' '));
        final cleaned = details.subject;
        if (!isPlausibleCourseLabel(cleaned)) continue;
        final measuredConfidence =
            blocks
                .map((block) => block.confidence.clamp(0.0, 1.0))
                .reduce((a, b) => a + b) /
            blocks.length;
        // Rows built on a synthesized period rail carry assumed times, so
        // they are queued for review exactly like the PDF period rows.
        final ocrConfidence = syntheticRail ? .74 : measuredConfidence;
        final key =
            '$day|$start|$end|${cleaned.toLowerCase()}|${details.room.toLowerCase()}';
        final normalizedSubject = normalizeOcrWord(cleaned);
        final duplicateClass = output.any(
          (draft) =>
              draft.day == day &&
              draft.startMinutes == start &&
              draft.endMinutes == end &&
              normalizeOcrWord(draft.subject) == normalizedSubject,
        );
        if (!duplicateClass && seen.add(key)) {
          output.add(
            ParsedTimetableRow(
              subject: cleaned,
              room: details.room,
              professor: details.professor,
              day: day,
              startMinutes: start,
              endMinutes: end,
              ocrConfidence: ocrConfidence,
            ),
          );
        }
      }
      // PaddleOCR can read post-noon labels (1:00, 2:00, etc.) as
      // morning clock values even though the grid's time axis clearly runs
      // from morning through evening. Normalize only when the detected axis
      // itself proves this is a daytime/evening timetable; never change valid
      // morning classes.
      final axisStartsMorning =
          ticks.first[1] >= 6 * 60 && ticks.first[1] <= 9 * 60;
      final axisExtendsIntoEvening = ticks.any((tick) => tick[1] >= 17 * 60);
      if (axisStartsMorning && axisExtendsIntoEvening) {
        return output.map((row) {
          if (row.startMinutes <= 0 ||
              row.startMinutes >= 7 * 60 ||
              row.endMinutes <= row.startMinutes ||
              row.endMinutes >= 7 * 60) {
            return row;
          }
          return ParsedTimetableRow(
            subject: row.subject,
            room: row.room,
            professor: row.professor,
            day: row.day,
            startMinutes: row.startMinutes + 12 * 60,
            endMinutes: row.endMinutes + 12 * 60,
            ocrConfidence: row.ocrConfidence,
          );
        }).toList();
      }

      return output;
    } catch (e, st) {
      debugPrint('Grid-aware image scan fallback: $e\n$st');
      return [];
    } finally {
      try {
        await enhancedOcrImage?.file.delete();
      } catch (_) {
        // Temporary OCR data does not affect the saved schedule.
      }
      try {
        await adaptiveOcrImage?.file.delete();
      } catch (_) {
        // Temporary OCR data does not affect the saved schedule.
      }
      try {
        await invertedOcrImage?.file.delete();
      } catch (_) {
        // Temporary OCR data does not affect the saved schedule.
      }
      try {
        await enlargedOcrFile?.delete();
      } catch (_) {
        // Temporary OCR data does not affect the saved schedule.
      }
      try {
        await boundedOcrFile?.delete();
      } catch (_) {
        // Temporary OCR data does not affect the saved schedule.
      }
      for (final file in columnOcrFiles) {
        try {
          await file.delete();
        } catch (_) {
          // Temporary column images are cleaned up when possible.
        }
      }
      bitmap.dispose();
      codec.dispose();
    }
  }
}

class _SpatialText {
  final String text;
  final ui.Rect box;
  final double confidence;

  const _SpatialText(this.text, this.box, [this.confidence = 0]);
}

/// What a grid scan read, filled by [TimetableGridScanner.scan] when the
/// caller passes a [stats] box.
class GridScanStats {
  int lineCount = 0;
  int alnumChars = 0;
  double meanLineConfidence = 0;

  /// True when the upright scan already read substantial, clean text: the
  /// image is upright and readable, so the rotated rescans - which exist
  /// purely to recover orientation - cannot add anything. Sideways or faint
  /// photos read as little or low-confidence text and keep the retries.
  bool get readCleanText => alnumChars >= 40 && meanLineConfidence >= .6;
}
