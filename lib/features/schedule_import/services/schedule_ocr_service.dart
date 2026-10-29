import '../../../models/class_item.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../utils/domain_rescoring.dart';
import '../utils/ocr_image_size.dart';
import '../utils/pdf_page_image.dart';
import '../utils/pdf_timetable_scan_result.dart';
import '../utils/pdf_timetable_text.dart';
import '../utils/parse_chain.dart';
import '../utils/schedule_text_parser.dart';
import '../utils/skew_profile_estimator.dart';
import '../utils/timetable_format.dart';
import '../utils/timetable_parser.dart';
import 'ocr_image_preprocessor.dart';
import 'timetable_grid_scanner.dart';

/// Coordinates on-device OCR passes for image, PDF, and weekly-grid imports.
class ScheduleOcrService {
  final PaddleOcr _ocr = PaddleOcr();
  final OcrImagePreprocessor _preprocessor = OcrImagePreprocessor();
  late final TimetableGridScanner _gridScanner = TimetableGridScanner(
    recognize: _ocr.recognize,
    preprocessor: _preprocessor,
  );

  /// Base number of PDF pages scanned before the idle-run heuristic kicks
  /// in. Most timetables fit on the first pages; the window keeps the common
  /// case fast while still allowing deep documents to be scanned.
  static const int _pdfBasePageWindow = 8;

  /// Hard ceiling on scanned PDF pages regardless of productivity.
  static const int _pdfMaxPageScanLimit = 24;

  Future<void>? _ocrInitialization;
  Future<void>? _pdfTextInitialization;

  Future<void> _initializeOcr() {
    return _ocrInitialization ??= _ocr
        .init(
      // Small printed course labels and room codes need finer detection.
      config: const PaddleOcrConfig(
        detThresh: 0.25,
        detBoxThresh: 0.35,
        detUnclipRatio: 1.0,
        detLimitSideLen: 2304,
        detLimitType: 'max',
        detMaxSideLimit: 4000,
        recScoreThresh: 0.0,
      ),
      engine: const EngineConfig(numThreads: 4),
    )
        .catchError((Object error) {
      // Forget a failed setup, so the next scan tries again.
      _ocrInitialization = null;
      throw error;
    });
  }

  Future<void> _initializePdfText() {
    return _pdfTextInitialization ??= pdfrx.pdfrxFlutterInitialize();
  }

  bool _isCancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Stops ongoing OCR processing after the current step.
  void cancel() {
    _isCancelled = true;
  }

  /// Clears cancellation state before starting a new scan.
  void resetCancel() {
    _isCancelled = false;
  }

  Future<void> dispose() {
    cancel();
    return _ocr.dispose();
  }

  Future<List<ParsedTimetableRow>> scanGridImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
    GridScanStats? stats,
  }) async {
    bool cancelled() => _isCancelled || (isCancelled?.call() ?? false);
    if (cancelled()) return [];
    await _initializeOcr();
    if (cancelled()) return [];
    // The caller can hand in a stats object to learn how clean the upright
    // read was (weak-grid rescue on the import screen); the rotations below
    // deliberately keep their own stats - only the first scan decides
    // whether the image was already upright and readable.
    final firstScanStats = stats ?? GridScanStats();
    final rows = await _gridScanner.scan(
      path,
      onProgress: onProgress,
      isCancelled: cancelled,
      stats: firstScanStats,
    );
    if (rows.isNotEmpty || cancelled()) return rows;

    // Grid geometry relies on upright weekday headers in the top band of
    // the image. When the first pass finds none, retry quarter-turn copies
    // the same way the list-based scan does before giving up — but only
    // when the upright scan did NOT read clean text. The rotated retries
    // exist to recover orientation; an image that was already read cleanly
    // upright cannot gain a header row from being scanned sideways. (This
    // is the same principle scanImage applies: it only rotates when
    // nothing parsed at all.)
    if (!firstScanStats.readCleanText) {
      final temporaryFiles = <File>[];
      try {
        for (final turns in const [1, 3, 2]) {
          if (cancelled()) return [];
          onProgress(.9, 'Trying a rotated grid scan');
          final rotated = await _preprocessor.prepare(
            path,
            quarterTurns: turns,
          );
          if (rotated == null) continue;
          temporaryFiles.add(rotated.file);
          final rotatedRows = await _gridScanner.scan(
            rotated.file.path,
            onProgress: (progress, detail) =>
                onProgress(.9 + .09 * progress.clamp(0.0, 1.0), detail),
            isCancelled: cancelled,
          );
          if (rotatedRows.isNotEmpty) return rotatedRows;
        }
      } finally {
        for (final file in temporaryFiles) {
          try {
            if (await file.exists()) await file.delete();
          } catch (error) {
            debugPrint('Could not remove temporary rotated grid image: $error');
          }
        }
      }
    }
    return rows;
  }

  /// Runs independent OCR candidates and selects the most useful one instead
  /// of concatenating them. Concatenating alternate passes often duplicates
  /// subjects and can make the timetable parser associate the wrong fields.
  Future<String> scanImage(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => _isCancelled || (isCancelled?.call() ?? false);
    if (cancelled()) return '';
    onProgress(.44, 'Starting on-device text recognition');
    await _initializeOcr();
    if (cancelled()) return '';
    final candidates = <_OcrTextCandidate>[];
    var failedPasses = 0;
    final temporaryFiles = <File>[];

    var candidateProgress = .46;
    Future<_OcrTextCandidate?> addCandidate(
      String imagePath,
      String label,
    ) async {
      if (cancelled()) return null;
      onProgress(candidateProgress, '$label text recognition');
      try {
        final result = await _ocr.recognize(imagePath);
        if (cancelled()) return null;
        final text = _joinOcrRegions(result.results);
        if (text.trim().isEmpty) return null;
        final confidence = result.results.isEmpty
            ? 0.0
            : result.results
                    .map(
                      (region) => region.confidence.clamp(0.0, 1.0).toDouble(),
                    )
                    .fold<double>(0.0, (sum, value) => sum + value) /
                result.results.length;
        final candidate = _OcrTextCandidate(text, confidence, label);
        candidates.add(candidate);
        return candidate;
      } catch (error) {
        failedPasses++;
        debugPrint('$label OCR pass failed: $error');
        return null;
      } finally {
        candidateProgress =
            (candidateProgress + .09).clamp(.46, .82).toDouble();
        onProgress(candidateProgress, '$label scan complete');
      }
    }

    try {
      var candidate = await addCandidate(path, 'Original');
      if (cancelled()) return '';

      // The cascade stops as soon as a pass parses strongly: a clear,
      // upright photo is fully read by its first pass, and the variant
      // passes below exist to rescue faint, low-contrast, or inverted
      // photos that the first pass could not read. Running all of them for
      // every photo multiplied the scan time by the pass count for no gain.
      // The bar is deliberately high (>= 2 rows through the shared parser
      // chain AND mean confidence >= 0.85): anything weaker keeps the full
      // cascade, so hard photos keep exactly today's recall.
      bool strongEnough() => _strongScan(candidate);

      // Laplacian variance of the last prepared grayscale. Below the
      // threshold the photo is out of focus or interpolation-soft (a COR
      // photographed at arm's length), and an unsharp-masked variant reads
      // the table the soft original cannot. Calibrated on the COR benchmark
      // fixtures: crisp pages measure 1300+, soft ones under 700.
      const softnessThreshold = 800.0;
      var preparedSoftness = double.infinity;
      PreparedOcrImage? enhancedImage;

      if (!strongEnough()) {
        onProgress(candidateProgress, 'Preparing an enhanced image');
        final enhanced = await _preprocessor.prepare(path);
        enhancedImage = enhanced;
        if (enhanced != null) {
          temporaryFiles.add(enhanced.file);
          preparedSoftness = enhanced.softness;
        }
        if (cancelled()) return '';
        if (enhanced != null) {
          candidate = await addCandidate(
            enhanced.file.path,
            'Contrast enhanced',
          );
        }
        if (cancelled()) return '';
      }

      if (!strongEnough() && preparedSoftness < softnessThreshold) {
        // Sharpening before the threshold passes: on a soft page the
        // adaptive-threshold pass only has smeared strokes to threshold, so
        // recovering glyph edges first helps every later candidate too.
        onProgress(candidateProgress, 'Preparing a sharpened image');
        final sharpened = await _preprocessor.prepare(path, sharpen: true);
        if (sharpened != null) temporaryFiles.add(sharpened.file);
        if (cancelled()) return '';
        if (sharpened != null) {
          candidate = await addCandidate(
            sharpened.file.path,
            'Sharpen rescue',
          );
        }
        if (cancelled()) return '';
      }

      if (!strongEnough()) {
        // Adaptive thresholding can help faint text, but can also erase thin
        // strokes and timetable grid details. Treat it as a candidate, not truth.
        onProgress(candidateProgress, 'Preparing a high-contrast image');
        final adaptive = await _preprocessor.prepare(
          path,
          adaptiveThreshold: true,
        );
        if (adaptive != null) temporaryFiles.add(adaptive.file);
        if (cancelled()) return '';
        if (adaptive != null) {
          candidate = await addCandidate(
            adaptive.file.path,
            'Adaptive threshold',
          );
        }
        if (cancelled()) return '';
      }

      if (!strongEnough()) {
        final inverted = await _preprocessor.prepare(
          path,
          invertDarkBackground: true,
        );
        if (inverted != null) temporaryFiles.add(inverted.file);
        if (cancelled()) return '';
        if (inverted != null) {
          candidate = await addCandidate(
            inverted.file.path,
            'Dark-background inversion',
          );
        }
        if (cancelled()) return '';
      }

      // High-res rescue: cheap cameras hand back 1000-2000 px captures whose
      // thin glyphs dissolve at the standard upscale target. One more decode
      // at a higher pixel budget reads rows the standard passes cannot - the
      // COR benchmark's 1500 px sample goes 7/10 -> 9/10 at the 2160 target.
      if (!strongEnough() &&
          enhancedImage != null &&
          enhancedImage.sourceLongestSide < 2160) {
        onProgress(candidateProgress, 'Preparing a high-resolution image');
        final hires = await _preprocessor.prepare(
          path,
          upscaleTarget: 2160,
        );
        if (hires != null) temporaryFiles.add(hires.file);
        if (cancelled()) return '';
        if (hires != null) {
          candidate = await addCandidate(hires.file.path, 'High-res rescue');
        }
        if (cancelled()) return '';
      }

      // Deskew rescue: a photographed page tilted more than ~2 degrees keeps
      // its schedule cells from banding into rows (the quarter-turn gate
      // below only covers 90-degree mistakes). The gradient projection
      // profile estimate from the enhanced pass costs no extra decode; when
      // it is confident, try the correction plus a +-0.75 degree bracket -
      // the profile peak and the recognizer's preferred angle can differ by
      // a hair, and ParseChain picks whichever candidate actually parses.
      final skewDegrees = enhancedImage?.skewDegrees ?? 0;
      final skewProminence = enhancedImage?.skewProminence ?? 0;
      if (!strongEnough() &&
          ProfileSkewEstimate(
            degrees: skewDegrees,
            prominence: skewProminence,
          ).shouldRescue) {
        for (final degrees in const [-1.0, 0.0, 1.0]) {
          if (cancelled()) return '';
          final angle = skewDegrees + 0.75 * degrees;
          onProgress(candidateProgress, 'Trying a deskewed scan');
          final deskewed = await _preprocessor.prepare(
            path,
            upscaleTarget: 2160,
            rotateDegrees: angle,
          );
          if (deskewed != null) temporaryFiles.add(deskewed.file);
          if (cancelled()) return '';
          if (deskewed == null) continue;
          candidate = await addCandidate(
            deskewed.file.path,
            'Deskew ${angle.toStringAsFixed(2)}',
          );
          if (strongEnough()) break;
        }
        if (cancelled()) return '';
      }

      // Rotation is expensive and normally unnecessary. Try it only when the
      // initial independent candidates fail to yield a usable parsed row.
      final initialBestRows = candidates.isEmpty
          ? 0
          : candidates
              .map(
                (candidate) => TimetableParser.parse(candidate.text).length,
              )
              .reduce((a, b) => a > b ? a : b);
      if (initialBestRows == 0) {
        for (final turns in const [1, 3, 2]) {
          if (cancelled()) return '';
          onProgress(candidateProgress, 'Trying a rotated scan');
          final rotated = await _preprocessor.prepare(
            path,
            quarterTurns: turns,
          );
          if (rotated != null) temporaryFiles.add(rotated.file);
          if (cancelled()) return '';
          if (rotated == null) continue;
          await addCandidate(rotated.file.path, 'Rotated $turns');
          if (cancelled()) return '';
        }
      }

      if (cancelled()) return '';
      if (candidates.isEmpty) {
        // Every pass threw. That is an engine failure, not an image with no text.
        if (failedPasses > 0) throw const OcrEngineFailure();
        return '';
      }
      candidates.sort(
        (a, b) => _scoreOcrCandidate(b).compareTo(_scoreOcrCandidate(a)),
      );
      final best = candidates.first;

      // Format routing + domain correction: OCR letter/digit slips inside
      // times and codes are normalized first. The full normalized text is
      // then returned: the review screen runs the parser chain itself
      // (sectioned parser first, then list, then free text), so every field
      // the scan produced survives. Never emit subject-only lines here -
      // the downstream re-parse would lose day/time/room and yield nothing.
      final normalizedText = normalizeOcrTokens(best.text);
      final estimate = TimetableFormatClassifier.classify(normalizedText);
      final selectedRows = TimetableParser.parse(normalizedText).length;
      final sectionedPreview = ParseChain.sectionedRows(normalizedText);
      debugPrint(
        'Selected ${best.label} OCR candidate: '
        '$selectedRows free-text rows, ${sectionedPreview.length} sectioned rows, '
        'confidence ${best.meanConfidence.toStringAsFixed(3)}, '
        'format ${estimate.format.name}.',
      );
      onProgress(.84, 'Text recognition complete');
      return normalizedText;
    } finally {
      for (final file in temporaryFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (error) {
          debugPrint('Could not remove temporary OCR image: $error');
        }
      }
    }
  }

  /// Accuracy is judged by useful, valid timetable rows first. Model confidence
  /// is only a tie-breaker because a confident OCR result can still be wrong.
  /// The sectioned parser counts too: it recovers formats the free-text path
  /// cannot see (section headers, slot grids, exam records), so a candidate
  /// that feeds it more rows is the better scan. Delegates to the shared
  /// ParseChain scorer so the bench harness and the live selection cannot
  /// drift.
  double _scoreOcrCandidate(_OcrTextCandidate candidate) =>
      ParseChain.score(candidate.text, candidate.meanConfidence);

  /// True when a single OCR pass already parsed into a usable timetable
  /// through the same chain the review screen runs: at least two rows and a
  /// high mean confidence. Used by the scanImage cascade to stop before the
  /// rescue passes; the bar is intentionally conservative because the pass
  /// that fails it keeps the full multi-candidate fallback.
  bool _strongScan(_OcrTextCandidate? candidate) {
    if (candidate == null || candidate.meanConfidence < .85) return false;
    final chain = ParseChain.parse(candidate.text);
    final rows =
        chain.sectioned.isNotEmpty ? chain.sectioned.length : chain.list.length;
    return rows >= 2;
  }

  Future<PdfTimetableScanResult> scanPdf(
    String path, {
    required void Function(double progress, String detail) onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => _isCancelled || (isCancelled?.call() ?? false);
    if (cancelled()) {
      return const PdfTimetableScanResult(
        pages: [],
        totalPages: 0,
        scannedPages: 0,
      );
    }
    onProgress(.1, 'Opening the PDF');
    try {
      await _initializePdfText();
    } catch (error) {
      debugPrint('Selectable PDF text is unavailable; using OCR: $error');
    }
    final doc = await pdfrx.PdfDocument.openFile(path);
    final temp = await getTemporaryDirectory();
    final totalPages = doc.pages.length;
    final pageResults = <PdfPageScanResult>[];
    try {
      await _initializeOcr();
      if (cancelled()) {
        return PdfTimetableScanResult(
          pages: const [],
          totalPages: totalPages,
          scannedPages: 0,
        );
      }
      // Pages are scanned in order. The first base window is always read;
      // past it, the run continues only while pages keep paying off (three
      // consecutive unproductive pages end it) and never past the hard cap.
      var plannedPages = math.min(totalPages, _pdfBasePageWindow);
      var idleRun = 0;
      for (var i = 1; i <= totalPages; i++) {
        if (cancelled()) break;
        if (i > _pdfBasePageWindow &&
            (idleRun >= 3 || pageResults.length >= _pdfMaxPageScanLimit)) {
          break;
        }
        if (i > plannedPages) plannedPages = i;
        onProgress(
          .1 + .72 * (i - 1) / plannedPages,
          i > _pdfBasePageWindow
              ? 'Reading PDF page $i (checking whether it holds classes)'
              : plannedPages < totalPages
                  ? 'Reading PDF page $i of $plannedPages (first $plannedPages of $totalPages)'
                  : 'Reading PDF page $i of $plannedPages',
        );
        final page = doc.pages[i - 1];
        if (cancelled()) break;
        final pdfTextFragments = await _readPdfTextFragments(doc, i);
        final renderScale = math
            .min(3.0, maxOcrRasterSide / math.max(page.width, page.height))
            .toDouble();
        final rendered = await page.render(
          fullWidth: page.width * renderScale,
          fullHeight: page.height * renderScale,
          backgroundColor: 0xffffffff,
        );
        if (rendered == null) {
          pageResults.add(
            PdfPageScanResult(
              pageNumber: i,
              gridRows: const [],
              fallbackText: '',
              hasWeekdayHeaders: false,
            ),
          );
          if (i > _pdfBasePageWindow) idleRun++;
          onProgress(
            .1 + .72 * i / plannedPages,
            'Skipped unreadable PDF page $i of $plannedPages',
          );
          continue;
        }
        final imageFile = File(
          p.join(
            temp.path,
            'schedule_import_page_${i}_${DateTime.now().microsecondsSinceEpoch}.png',
          ),
        );
        await imageFile.writeAsBytes(
          await encodePdfImagePng(rendered),
          flush: true,
        );
        try {
          void gridScanProgress(double progress, String detail) {
            final pageFraction =
                (progress / .43).clamp(0.0, 1.0).toDouble() * .45;
            onProgress(
              .1 + .72 * ((i - 1 + pageFraction) / plannedPages),
              'PDF page $i of $plannedPages - $detail',
            );
          }

          final scannedPageRows = await _gridScanner.scan(
            imageFile.path,
            isCancelled: cancelled,
            onProgress: gridScanProgress,
          );
          if (cancelled()) break;
          var pageRows = scannedPageRows.isNotEmpty
              ? _applyPdfTextLayer(scannedPageRows, pdfTextFragments)
              : const <ParsedTimetableRow>[];
          final fallbackText = pageRows.isEmpty
              ? await scanImage(
                  imageFile.path,
                  isCancelled: cancelled,
                  onProgress: (progress, detail) {
                    final pageFraction =
                        ((progress - .44) / .4).clamp(0.0, 1.0).toDouble();
                    onProgress(
                      .1 +
                          .72 *
                              ((i - 1 + .45 + .55 * pageFraction) /
                                  plannedPages),
                      'PDF page $i of $plannedPages · $detail',
                    );
                  },
                )
              : '';
          if (cancelled()) break;
          final hasWeekdayHeaders = RegExp(
                r'\b(?:MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|FRI(?:DAY)?)\b',
                caseSensitive: false,
              ).allMatches(fallbackText).length >=
              2;
          // Last-resort text-layer rescue: when neither the raster grid
          // scan nor the text parser chain produced anything, a
          // born-digital page still contains its timetable as selectable
          // text. Rows built here carry a conservative confidence so the
          // review screen asks the user to verify the rail-snapped times.
          if (pageRows.isEmpty &&
              !hasWeekdayHeaders &&
              TimetableParser.parse(fallbackText).isEmpty &&
              ParseChain.sectionedRows(fallbackText).isEmpty) {
            pageRows = _parseTextLayerTimetable(pdfTextFragments);
          }
          pageResults.add(
            PdfPageScanResult(
              pageNumber: i,
              gridRows: pageRows,
              fallbackText: fallbackText,
              hasWeekdayHeaders: hasWeekdayHeaders,
            ),
          );
          if (i > _pdfBasePageWindow) {
            final productive = pageRows.isNotEmpty ||
                hasWeekdayHeaders ||
                TimetableParser.parse(fallbackText).isNotEmpty ||
                ParseChain.sectionedRows(fallbackText).isNotEmpty;
            idleRun = productive ? 0 : idleRun + 1;
          }
          onProgress(
            .1 + .72 * i / plannedPages,
            'Finished PDF page $i of $plannedPages',
          );
        } finally {
          if (await imageFile.exists()) await imageFile.delete();
        }
      }
      return cancelled()
          ? PdfTimetableScanResult(
              pages: const [],
              totalPages: totalPages,
              scannedPages: 0,
            )
          : PdfTimetableScanResult(
              pages: pageResults,
              totalPages: totalPages,
              scannedPages: pageResults.length,
            );
    } finally {
      await doc.dispose();
    }
  }

  Future<List<_PdfTextFragment>> _readPdfTextFragments(
    pdfrx.PdfDocument? document,
    int pageNumber,
  ) async {
    if (document == null ||
        pageNumber < 1 ||
        pageNumber > document.pages.length) {
      return const [];
    }
    try {
      final text = await document.pages[pageNumber - 1].loadStructuredText();
      final fragments = [
        for (final fragment in text.fragments)
          if (fragment.text.trim().isNotEmpty && fragment.bounds.isNotEmpty)
            _PdfTextFragment(
              text: fragment.text.trim(),
              left: fragment.bounds.left,
              right: fragment.bounds.right,
              top: fragment.bounds.top,
              bottom: fragment.bounds.bottom,
            ),
      ];
      // Some PDFs embed damaged CID-keyed fonts whose "text" is private-use
      // gibberish. Treating that layer as real text corrupts both the label
      // correction and the rescue path, so it is discarded outright.
      if (_isGarbledTextLayer(
        fragments.map((fragment) => fragment.text).join(' '),
      )) {
        return const [];
      }
      return fragments;
    } catch (error) {
      debugPrint('Could not read PDF text on page $pageNumber: $error');
      return const [];
    }
  }

  /// True when a PDF text layer is damaged beyond use: mostly private-use,
  /// replacement, or C1 control characters (broken CID fonts), or almost no
  /// letters and digits at all on a page that claims to have text.
  bool _isGarbledTextLayer(String text) {
    if (text.isEmpty) return false;
    final suspicious = RegExp(
      '[\uE000-\uF8FF\uFFFD\u0080-\u009F\uFEFF]',
    ).allMatches(text).length;
    if (suspicious * 100 > text.length * 2) return true;
    final meaningful = text.replaceAll(RegExp(r'\s'), '');
    if (meaningful.length >= 40) {
      final lettersAndDigits = RegExp(
        r'[A-Za-z0-9]',
      ).allMatches(meaningful).length;
      if (lettersAndDigits * 100 < meaningful.length * 45) return true;
    }
    return false;
  }

  List<ParsedTimetableRow> _applyPdfTextLayer(
    List<ParsedTimetableRow> gridRows,
    List<_PdfTextFragment> fragments,
  ) {
    if (gridRows.isEmpty || fragments.isEmpty) return gridRows;
    final lines = _pdfTextLines(fragments);
    final headers = _pdfDayHeaderCenters(fragments);
    final dayCenters = headers.centers;
    if (dayCenters.length < 2) return gridRows;

    final sortedDays = dayCenters.keys.toList()
      ..sort((a, b) => dayCenters[a]!.compareTo(dayCenters[b]!));
    final dayBounds = _pdfDayBounds(dayCenters);

    // Rail ticks may sit in either margin and come in every common shape:
    // single times, 24-hour and military values, bare hours, ranges with
    // the meridiem printed on one side only, and period rails.
    final ticks = PdfTimetableText.resolveRailTicks(
      [
        for (final line in lines)
          (
            text: line.text,
            left: line.left,
            right: line.right,
            centerY: line.centerY,
          ),
      ],
      inMargin: (line) =>
          line.right <= dayBounds[sortedDays.first]![0] ||
          line.left >= dayBounds[sortedDays.last]![1],
    );
    if (ticks.length < 2) return gridRows;

    final fit = _fitMinuteAxis(ticks);
    if (fit == null) return gridRows;
    final yPerMinute = fit.slope;
    double yAt(double minute) => fit.intercept + fit.slope * minute;
    // Inverse of the fit: minutes from a page Y position.
    double minuteAt(double y) => (y - fit.intercept) / fit.slope;
    final halfSlotHeight = yPerMinute.abs() * 15;

    // Slot geometry shared by the time correction below.
    final byMinute = [...ticks]..sort((a, b) => a.minute.compareTo(b.minute));
    final medianSlot = byMinute.length >= 2
        ? PdfTimetableText.medianOf(<int>[
            for (var i = 1; i < byMinute.length; i++)
              byMinute[i].minute - byMinute[i - 1].minute,
          ])
        : 0;
    final slotsUsable = medianSlot >= 10 && medianSlot <= 240;

    var correctedCount = 0;
    final correctedRows = gridRows.map((row) {
      final bounds = dayBounds[row.day];
      if (bounds == null) return row;
      // pdfrx may expose page coordinates with either a top-left or
      // bottom-left origin. Normalize the interval instead of assuming that
      // later times always have a smaller Y value.
      final firstY = yAt((row.startMinutes + 15).toDouble());
      final lastY = yAt((row.endMinutes - 15).toDouble());
      final lowerY = math.min(firstY, lastY) - halfSlotHeight;
      final upperY = math.max(firstY, lastY) + halfSlotHeight;

      final cellFragments = fragments.where((fragment) {
        final centerX = (fragment.left + fragment.right) / 2;
        final centerY = (fragment.top + fragment.bottom) / 2;
        return centerX >= bounds[0] &&
            centerX < bounds[1] &&
            centerY >= lowerY - 2 &&
            centerY <= upperY + 2;
      }).toList();
      final cellLines = _pdfTextLines(
        cellFragments,
      ).map((line) => line.text).where((text) => text.isNotEmpty).toList();
      if (cellLines.isEmpty) return row;

      final details = ScheduleTextDetails.parseLines(cellLines);
      final subject = details.subject.trim();
      if (subject.length < 2 ||
          TimetableParser.looksLikeOcrTextIssue(subject)) {
        return row;
      }
      correctedCount++;

      // Re-derive the slot boundaries from the cell's own text extent: the
      // raster grid scan snaps to detected lines, but the text layer knows
      // where the printed content actually sits. Override the OCR times
      // when the two disagree by more than five minutes, and flag the row
      // so the review screen asks the user to confirm.
      var startMinutes = row.startMinutes;
      var endMinutes = row.endMinutes;
      var timeCorrected = false;
      if (slotsUsable && cellFragments.isNotEmpty) {
        final ys = <double>[
          for (final fragment in cellFragments) ...[
            fragment.top,
            fragment.bottom,
          ],
        ];
        final snappedStart = _snapSlotStart(
          minuteAt(ys.reduce(math.min)),
          byMinute,
          medianSlot,
        );
        final snappedEnd = _snapSlotEnd(
          minuteAt(ys.reduce(math.max)),
          byMinute,
          medianSlot,
        );
        if (snappedStart != null &&
            snappedEnd != null &&
            snappedEnd > snappedStart &&
            ((snappedStart - row.startMinutes).abs() > 5 ||
                (snappedEnd - row.endMinutes).abs() > 5)) {
          startMinutes = snappedStart;
          endMinutes = snappedEnd;
          timeCorrected = true;
        }
      }

      return ParsedTimetableRow(
        subject: subject,
        room: details.room == 'Room to confirm' ? row.room : details.room,
        professor: details.professor == unspecifiedProfessor
            ? row.professor
            : details.professor,
        day: row.day,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        ocrConfidence: timeCorrected ? .74 : null,
      );
    }).toList();

    // A sparse or flattened PDF text layer may expose only a few labels. In
    // that case keep the complete OCR result instead of mixing partial data.
    return correctedCount >= (gridRows.length / 2).ceil()
        ? correctedRows
        : gridRows;
  }

  List<_PdfTextLine> _pdfTextLines(List<_PdfTextFragment> fragments) {
    final ordered = fragments.toList()
      ..sort((a, b) {
        final vertical = b.centerY.compareTo(a.centerY);
        return vertical == 0 ? a.left.compareTo(b.left) : vertical;
      });
    final lines = <List<_PdfTextFragment>>[];
    for (final fragment in ordered) {
      final lineIndex = lines.indexWhere((line) {
        final center =
            line.map((item) => item.centerY).reduce((a, b) => a + b) /
                line.length;
        final height =
            line.map((item) => item.height).reduce((a, b) => a < b ? a : b);
        return (fragment.centerY - center).abs() <=
            math.max(1.5, math.min(height, fragment.height) * .45);
      });
      if (lineIndex < 0) {
        lines.add([fragment]);
      } else {
        lines[lineIndex].add(fragment);
      }
    }

    return lines.map((line) {
      line.sort((a, b) => a.left.compareTo(b.left));
      return _PdfTextLine(
        text: line.map((fragment) => fragment.text).join(' ').trim(),
        left: line.map((fragment) => fragment.left).reduce(math.min),
        right: line.map((fragment) => fragment.right).reduce(math.max),
        centerY:
            line.map((fragment) => fragment.centerY).reduce((a, b) => a + b) /
                line.length,
      );
    }).toList();
  }

  /// Averages the x-centers of fragments that read as standalone weekday
  /// header cells. Fragment-level matching survives header rows whose cells
  /// merge into one visual line, and also covers Saturday/Sunday columns.
  /// Single-letter MTWRF headers are trusted only when at least three of
  /// them appear together, so a stray "M" elsewhere cannot become a column.
  ({Map<int, double> centers, Set<_PdfTextFragment> matched})
      _pdfDayHeaderCenters(List<_PdfTextFragment> fragments) {
    final matches = <({int day, _PdfTextFragment fragment})>[];
    for (final fragment in fragments) {
      final day = PdfTimetableText.dayOfHeaderCell(fragment.text);
      if (day == null) continue;
      matches.add((day: day, fragment: fragment));
    }
    final letterMatches =
        matches.where((match) => match.fragment.text.trim().length <= 2).length;
    final usable = letterMatches > 0 && letterMatches < 3
        ? matches
            .where((match) => match.fragment.text.trim().length > 2)
            .toList()
        : matches;
    final sums = <int, double>{};
    final counts = <int, int>{};
    final matched = <_PdfTextFragment>{};
    for (final match in usable) {
      final fragment = match.fragment;
      sums[match.day] = (sums[match.day] ?? 0) + fragment.centerX;
      counts[match.day] = (counts[match.day] ?? 0) + 1;
      matched.add(fragment);
    }
    final centers = <int, double>{
      for (final day in sums.keys) day: sums[day]! / counts[day]!,
    };
    return (centers: centers, matched: matched);
  }

  /// Midpoint boundaries between neighboring day header columns. The first
  /// and last columns extend outward by half of their neighboring gap.
  Map<int, List<double>> _pdfDayBounds(Map<int, double> dayCenters) {
    final sortedDays = dayCenters.keys.toList()
      ..sort((a, b) => dayCenters[a]!.compareTo(dayCenters[b]!));
    final firstGap = dayCenters[sortedDays[1]]! - dayCenters[sortedDays.first]!;
    final lastGap = dayCenters[sortedDays.last]! -
        dayCenters[sortedDays[sortedDays.length - 2]]!;
    final dayBounds = <int, List<double>>{};
    for (var i = 0; i < sortedDays.length; i++) {
      final day = sortedDays[i];
      final center = dayCenters[day]!;
      final left = i == 0
          ? center - firstGap / 2
          : (dayCenters[sortedDays[i - 1]]! + center) / 2;
      final right = i == sortedDays.length - 1
          ? center + lastGap / 2
          : (center + dayCenters[sortedDays[i + 1]]!) / 2;
      dayBounds[day] = [left, right];
    }
    return dayBounds;
  }

  /// Robust fit mapping page Y coordinates to rail minutes.
  ///
  /// The fit is y = intercept + slope * minute, with the slope taken as the
  /// median of pairwise slopes (Theil-Sen), so a stray margin tick cannot
  /// skew the line the way it would a least-squares fit. The slope sign
  /// stays open because pdfrx may expose either page-origin convention, but
  /// a zero slope means there is no usable time axis at all. Outlier ticks
  /// are dropped one at a time - ranked by the robust fit, so the stray
  /// itself is always the worst - before the fit is rejected.
  ({double slope, double intercept})? _fitMinuteAxis(List<PdfRailTick> ticks) {
    ({double slope, double intercept})? fitOf(List<PdfRailTick> sample) {
      if (sample.length < 2) return null;
      final slopes = <double>[];
      for (var i = 0; i < sample.length; i++) {
        for (var j = i + 1; j < sample.length; j++) {
          final minuteDelta = sample[j].minute - sample[i].minute;
          if (minuteDelta == 0) continue;
          slopes.add((sample[j].centerY - sample[i].centerY) / minuteDelta);
        }
      }
      if (slopes.isEmpty) return null;
      final slope = PdfTimetableText.medianOf(slopes);
      // Every tick at the same page height is not a time axis.
      if (slope.abs() < 1e-9) return null;
      final intercept = PdfTimetableText.medianOf(<double>[
        for (final tick in sample) tick.centerY - slope * tick.minute,
      ]);
      return (slope: slope, intercept: intercept);
    }

    var sample = ticks;
    while (sample.length >= 2) {
      final fit = fitOf(sample);
      if (fit == null) return null;
      // The fit predicts Y from minutes, so residuals are compared in Y
      // units: a 20-minute deviation is 20 * |slope| points.
      final yTolerance = 20 * fit.slope.abs();
      var worstResidual = 0.0;
      PdfRailTick? worst;
      for (final tick in sample) {
        final residual =
            (fit.intercept + fit.slope * tick.minute - tick.centerY).abs();
        if (residual > worstResidual) {
          worstResidual = residual;
          worst = tick;
        }
      }
      if (worstResidual <= yTolerance) return fit;
      if (sample.length <= 3) return null;
      sample = [...sample]..remove(worst!);
    }
    return null;
  }

  /// Builds rows directly from the text layer of a born-digital PDF page.
  ///
  /// This is a last-resort path: it only runs when the raster grid scan and
  /// the text parser chain both came up empty. Cell text is exact (no OCR),
  /// but class boundaries follow the rail's slot grid instead of the drawn
  /// cell borders, so times can be off by up to one slot. Rows carry a
  /// conservative confidence so the review screen flags them.
  List<ParsedTimetableRow> _parseTextLayerTimetable(
    List<_PdfTextFragment> fragments,
  ) {
    if (fragments.length < 4) return const [];
    final headers = _pdfDayHeaderCenters(fragments);
    final dayCenters = headers.centers;
    if (dayCenters.length < 2) return const [];
    final sortedDays = dayCenters.keys.toList()
      ..sort((a, b) => dayCenters[a]!.compareTo(dayCenters[b]!));
    final dayBounds = _pdfDayBounds(dayCenters);
    final firstLeft = dayBounds[sortedDays.first]![0];
    final lastRight = dayBounds[sortedDays.last]![1];

    final lines = _pdfTextLines(fragments);
    final ticks = PdfTimetableText.resolveRailTicks([
      for (final line in lines)
        (
          text: line.text,
          left: line.left,
          right: line.right,
          centerY: line.centerY,
        ),
    ], inMargin: (line) => line.right <= firstLeft || line.left >= lastRight);
    if (ticks.length < 3) return const [];
    final fit = _fitMinuteAxis(ticks);
    if (fit == null) return const [];
    // Inverse of the fit: minutes from a page Y position. The fit maps
    // minutes to Y (yAt), so this divides, never multiplies.
    double minuteAt(double y) => (y - fit.intercept) / fit.slope;

    final byMinute = [...ticks]..sort((a, b) => a.minute.compareTo(b.minute));
    final medianSlot = PdfTimetableText.medianOf(<int>[
      for (var i = 1; i < byMinute.length; i++)
        byMinute[i].minute - byMinute[i - 1].minute,
    ]);
    if (medianSlot < 10 || medianSlot > 240) return const [];
    final medianTickGapY = PdfTimetableText.medianOf(<double>[
      for (var i = 1; i < byMinute.length; i++)
        (byMinute[i].centerY - byMinute[i - 1].centerY).abs(),
    ]);
    // Within one cell, consecutive text lines nearly touch; different cells
    // are separated by a large fraction of the slot height. Classify each
    // fragment into a cell block by its edge-to-edge distance.
    final clusterGapThreshold = math.max(2.0, .35 * medianTickGapY);
    final firstMinute = byMinute.first.minute;
    final lastMinute = byMinute.last.minute;

    final rows = <ParsedTimetableRow>[];
    final seen = <String>{};
    for (final day in sortedDays) {
      final bounds = dayBounds[day]!;
      final cellFragments = <_PdfTextFragment>[];
      for (final fragment in fragments) {
        if (headers.matched.contains(fragment)) continue;
        final centerX = fragment.centerX;
        if (centerX < bounds[0] || centerX >= bounds[1]) continue;
        final cellMinute = minuteAt(fragment.centerY);
        if (cellMinute < firstMinute - medianSlot * .25 ||
            cellMinute > lastMinute + medianSlot) {
          continue;
        }
        cellFragments.add(fragment);
      }
      if (cellFragments.isEmpty) continue;
      cellFragments.sort((a, b) => a.centerY.compareTo(b.centerY));
      final clusters = <List<_PdfTextFragment>>[
        [cellFragments.first],
      ];
      for (var i = 1; i < cellFragments.length; i++) {
        final fragment = cellFragments[i];
        final previous = cellFragments[i - 1];
        final gap = (fragment.centerY - previous.centerY).abs() -
            (fragment.height + previous.height) / 2;
        if (gap <= clusterGapThreshold) {
          clusters.last.add(fragment);
        } else {
          clusters.add([fragment]);
        }
      }
      for (final cluster in clusters) {
        final cellLines = _pdfTextLines(
          cluster,
        ).map((line) => line.text).where((text) => text.isNotEmpty).toList();
        if (cellLines.isEmpty) continue;
        final details = ScheduleTextDetails.parseLines(cellLines);
        final subject = details.subject.trim();
        if (subject.length < 2 ||
            TimetableParser.looksLikeOcrTextIssue(subject) ||
            PdfTimetableText.dayOfHeaderCell(subject) != null ||
            RegExp(r'^[\d:.\s-]+$').hasMatch(subject)) {
          continue;
        }
        final ys = <double>[
          for (final fragment in cluster) ...[fragment.top, fragment.bottom],
        ];
        final start = _snapSlotStart(
          minuteAt(ys.reduce(math.min)),
          byMinute,
          medianSlot,
        );
        final end = _snapSlotEnd(
          minuteAt(ys.reduce(math.max)),
          byMinute,
          medianSlot,
        );
        if (start == null || end == null || end - start < 15) continue;
        final key = '$day|$start|$end|${subject.toLowerCase()}';
        if (!seen.add(key)) continue;
        rows.add(
          ParsedTimetableRow(
            subject: subject,
            room: details.room,
            professor: details.professor,
            day: day,
            startMinutes: start,
            endMinutes: end,
            ocrConfidence: .74,
          ),
        );
      }
    }
    return rows;
  }

  /// Snaps a cell's top edge to its slot start. Text sitting on a tick
  /// belongs to the slot that starts there; otherwise the slot is the last
  /// one that starts at or before the text edge.
  int? _snapSlotStart(
    double minute,
    List<PdfRailTick> byMinute,
    int medianSlot,
  ) {
    final tolerance = medianSlot * .2;
    for (final tick in byMinute) {
      if ((tick.minute - minute).abs() <= tolerance) return tick.minute;
    }
    int? candidate;
    for (final tick in byMinute) {
      if (tick.minute <= minute) {
        candidate = tick.minute;
      } else {
        break;
      }
    }
    return candidate ?? byMinute.first.minute;
  }

  /// Snaps a cell's bottom edge to the end of the slot that contains it:
  /// the next tick after the text edge, unless the text ends on a boundary.
  int? _snapSlotEnd(double minute, List<PdfRailTick> byMinute, int medianSlot) {
    final tolerance = medianSlot * .2;
    for (final tick in byMinute) {
      if ((tick.minute - minute).abs() <= tolerance) return tick.minute;
    }
    for (final tick in byMinute) {
      if (tick.minute > minute) return tick.minute;
    }
    final afterLast = byMinute.last.minute + medianSlot;
    return afterLast > 1440 ? null : afterLast;
  }

  String _joinOcrRegions(List<OcrResult> regions) {
    final sorted = regions.toList()
      ..sort((a, b) {
        final vertical = a.boundingBox.center.dy.compareTo(
          b.boundingBox.center.dy,
        );
        return vertical == 0
            ? a.boundingBox.left.compareTo(b.boundingBox.left)
            : vertical;
      });
    final lines = <String>[];
    var bandCenter = 0.0;
    var bandHeight = 0.0;
    var band = <OcrResult>[];
    void flushBand() {
      if (band.isEmpty) return;
      band.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      lines.add(band.map((region) => region.text.trim()).join(' | '));
      band = <OcrResult>[];
      bandCenter = 0;
      bandHeight = 0;
    }

    for (final region in sorted) {
      final center = region.boundingBox.center.dy;
      if (band.isNotEmpty &&
          center - bandCenter >
              math.max(
                5.0,
                math.min(region.boundingBox.height, bandHeight) * .6,
              )) {
        flushBand();
      }
      if (band.isEmpty) {
        bandCenter = center;
        bandHeight = region.boundingBox.height;
      } else {
        bandCenter = (bandCenter * band.length + center) / (band.length + 1);
        bandHeight = (bandHeight * band.length + region.boundingBox.height) /
            (band.length + 1);
      }
      band.add(region);
    }
    flushBand();
    return lines.join('\n');
  }
}

class _OcrTextCandidate {
  const _OcrTextCandidate(this.text, this.meanConfidence, this.label);

  final String text;
  final double meanConfidence;
  final String label;
}

class _PdfTextFragment {
  const _PdfTextFragment({
    required this.text,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => (top - bottom).abs();
}

class _PdfTextLine {
  const _PdfTextLine({
    required this.text,
    required this.left,
    required this.right,
    required this.centerY,
  });

  final String text;
  final double left;
  final double right;
  final double centerY;

  double get centerX => (left + right) / 2;
}

/// Text recognition itself failed (every pass threw). This is different from
/// an image that contains no readable text.
class OcrEngineFailure implements Exception {
  const OcrEngineFailure();

  String get message =>
      'Text recognition failed on this device. Try again, or add classes manually.';

  @override
  String toString() => message;
}
