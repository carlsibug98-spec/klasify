import 'timetable_parser.dart';

/// The layout family a timetable source appears to use. Detecting this first
/// lets the import pipeline route each schedule type to the parser that fits
/// it instead of forcing every image through the weekly-grid scanner.
enum TimetableFormat {
  /// Days as columns, time slots as rows, classes inside cells.
  weeklyGrid,

  /// One line per class: "CS201 Mon 9:30-11:00 Room B12".
  list,

  /// Exam-style tables: "Subject Date Time Room" with calendar dates.
  examCalendar,

  /// Not enough signal either way; treat as free text.
  unknown,
}

class TimetableFormatEstimate {
  const TimetableFormatEstimate({
    required this.format,
    required this.confidence,
    required this.evidence,
  });

  final TimetableFormat format;
  final double confidence;
  final String evidence;

  @override
  String toString() =>
      'TimetableFormatEstimate(${format.name}, ${confidence.toStringAsFixed(2)}, $evidence)';
}

/// Classifies raw OCR text into a layout family using cheap structural
/// signals (weekday density, time ranges, date tokens, column headers).
class TimetableFormatClassifier {
  static final RegExp _weekdayWord = RegExp(
    r'\b(mon(?:day)?|tues?day|tue|wednesday|wed|thurs?day|thu|thur|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b',
    caseSensitive: false,
  );

  static final RegExp _compactDayGroup = RegExp(
    r'\b(MTWTHF|MTWRF|MTWR|MTW|MWF|MW|TTH|TR)\b',
  );

  // Case-insensitive variant for structural signals: printed grids often use
  // lowercase or mixed-case day abbreviations that the strict pattern misses.
  static final RegExp _compactDayGroupLoose = RegExp(
    r'\b(mtwthf|mtwrf|mtwr|mtw|mw|tth|tr|mwf|mf|tt|thfr)\b',
    caseSensitive: false,
  );

  static final RegExp _timeRange = RegExp(
    r'\d{1,2}[:.]\d{2}\s*(?:[AP]\.?M\.?)?\s*(?:-|–|—|to)\s*\d{1,2}[:.]\d{2}',
    caseSensitive: false,
  );

  static final RegExp _clockTime = RegExp(
    r'\b\d{1,2}[:.]\d{2}\s*(?:[AP]\.?M\.?)?\b',
    caseSensitive: false,
  );

  static final RegExp _calendarDate = RegExp(
    r'\b\d{1,2}[/\-.]\d{1,2}(?:[/\-.]\d{2,4})?\b'
    r'|\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\b'
    r'|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2}\b',
    caseSensitive: false,
  );

  static final List<String> _examHeaderWords = const [
    'exam',
    'final',
    'midterm',
    'date',
    'venue',
    'schedule',
  ];

  /// Estimates the layout from recognized text. [hasPixelGridEvidence] should
  /// be true when pixel analysis already found long straight rules, which is
  /// the strongest possible grid signal.
  static TimetableFormatEstimate classify(
    String raw, {
    bool hasPixelGridEvidence = false,
  }) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return const TimetableFormatEstimate(
        format: TimetableFormat.unknown,
        confidence: 0,
        evidence: 'no text',
      );
    }

    final nonEmpty = raw.replaceAll(RegExp(r'\s'), '').length;
    final fillRatio = nonEmpty / (raw.isEmpty ? 1 : raw.length);

    var weekdayLines = 0;
    var timeRangeLines = 0;
    var dateLines = 0;
    var headerWordHits = 0;
    for (final line in lines) {
      if (_weekdayWord.hasMatch(line) ||
          _compactDayGroup.hasMatch(line) ||
          _compactDayGroupLoose.hasMatch(line)) {
        weekdayLines++;
      }
      if (_timeRange.hasMatch(line)) timeRangeLines++;
      if (_calendarDate.hasMatch(line)) dateLines++;
      final lower = line.toLowerCase();
      headerWordHits += _examHeaderWords.where(lower.contains).length;
    }

    // Fragmented OCR output of a printed grid: weekday names scattered across
    // many short lines with almost no inline day+time structure. OCR dumps of
    // grids are usually one word per line, so whitespace dominates the text.
    final fragmented = lines.length >= 8 && fillRatio < .70;
    // Fragmented pages put one weekday name on its own line (column headers
    // of a grid survive OCR as standalone words), unlike list schedules
    // where the day sits inline with a time.
    final standaloneWeekdayPattern = RegExp(
      r'^(mon|tue|tues|wed|thu|thur|fri|sat|sun)(day)?'
      r'|(mtwthf|mtwrf|mtwr|mtw|mwf|mw|tth|tr)$',
      caseSensitive: false,
    );
    final standaloneWeekdayLines = lines
        .where((line) => standaloneWeekdayPattern.hasMatch(line))
        .length;
    final gridByStructure =
        weekdayLines >= 4 && timeRangeLines <= (weekdayLines * .25).round();
    // A fragmented weekday dump only counts as grid evidence when it lacks
    // the inline day+time structure that defines list schedules.
    final fewClockTimes = _clockTime.allMatches(raw).length <= 1;
    final gridSignals =
        (hasPixelGridEvidence ? 2 : 0) +
        (gridByStructure ? 1 : 0) +
        (fragmented && weekdayLines >= 5 && fewClockTimes ? 1 : 0) +
        (standaloneWeekdayLines >= 4 && fewClockTimes ? 1 : 0);

    final listLines = lines
        .where(
          (line) =>
              _weekdayWord.hasMatch(line) &&
              (_timeRange.hasMatch(line) || _clockTime.hasMatch(line)),
        )
        .length;
    final listSignals =
        (listLines >= 3 ? 1 : 0) +
        (listLines > weekdayLines * .6 && timeRangeLines >= 3 ? 1 : 0);

    final examSignals =
        (dateLines >= 3 && headerWordHits >= 2 ? 2 : 0) +
        (dateLines >= 5 && timeRangeLines >= 3 ? 1 : 0);

    TimetableFormat format;
    double confidence;
    String evidence;
    if (gridSignals >= 2 &&
        gridSignals >= listSignals &&
        gridSignals >= examSignals) {
      format = TimetableFormat.weeklyGrid;
      confidence = (0.5 + gridSignals * 0.15).clamp(0.0, 0.95);
      evidence =
          'grid signals=$gridSignals (pixel=$hasPixelGridEvidence, '
          'weekdayLines=$weekdayLines, fragmented=$fragmented)';
    } else if (examSignals >= 2 && examSignals >= listSignals) {
      format = TimetableFormat.examCalendar;
      confidence = (0.45 + examSignals * 0.15).clamp(0.0, 0.9);
      evidence = 'dateLines=$dateLines, headerWords=$headerWordHits';
    } else if (listSignals >= 1 && listLines >= 2) {
      format = TimetableFormat.list;
      confidence = (0.4 + listSignals * 0.2).clamp(0.0, 0.9);
      evidence = 'structured lines=$listLines/${lines.length}';
    } else {
      format = TimetableFormat.unknown;
      confidence = 0.25;
      evidence =
          'weekdayLines=$weekdayLines, listLines=$listLines, '
          'dateLines=$dateLines';
    }
    return TimetableFormatEstimate(
      format: format,
      confidence: confidence,
      evidence: evidence,
    );
  }
}

/// Parses list-style timetables where every class occupies one line, e.g.
/// "CS201 - Data Structures, Mon 9:30-11:00, Room B12, Prof. A. Garcia".
/// Reuses [TimetableParser.parse] per line so day groups (MWF, TTh) expand
/// into one row per weekday exactly like the free-text path does.
class TimetableListParser {
  static List<ParsedTimetableRow> parse(String raw) {
    final rows = <ParsedTimetableRow>[];
    final seen = <String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // A usable class line needs both a weekday token and a time on it.
      // Compact day groups ("MWF", "TTh") count as weekday tokens too.
      if (!TimetableFormatClassifier._weekdayWord.hasMatch(trimmed) &&
          !TimetableFormatClassifier._compactDayGroup.hasMatch(trimmed)) {
        continue;
      }
      if (!TimetableFormatClassifier._clockTime.hasMatch(trimmed) &&
          !TimetableFormatClassifier._timeRange.hasMatch(trimmed)) {
        continue;
      }
      for (final row in TimetableParser.parse(trimmed)) {
        final key =
            '${row.subject}|${row.day}|${row.startMinutes}|${row.endMinutes}|${row.room}';
        if (seen.add(key)) rows.add(row);
      }
    }
    return rows;
  }
}
