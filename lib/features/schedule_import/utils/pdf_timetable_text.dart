import 'schedule_text_parser.dart';

/// One resolved time marker on the margin rail of a PDF timetable page.
class PdfRailTick {
  const PdfRailTick({required this.centerY, required this.minute});

  final double centerY;
  final int minute;
}

/// Geometry of one visual text line on a PDF page.
typedef PdfTextLineGeometry = ({
  String text,
  double left,
  double right,
  double centerY,
});

/// Pure-logic helpers that read weekday headers and time rails out of a
/// born-digital PDF's text layer.
///
/// Rails are the time columns printed along the left (sometimes right) edge
/// of a timetable. Real-world rails are far more varied than the list format:
/// 24-hour times ("08:00"), military times ("0800"), bare hours ("8", "9",
/// "12", "1" across noon), ranges with the meridiem printed on one side
/// only ("8 - 9 PM"), and period rails ("P1", "Period 3", "P3-P4") all
/// occur. These helpers normalize every common shape into absolute minutes.
class PdfTimetableText {
  static final RegExp _rangePattern = RegExp(
    r'(\d{4}|\d{1,2}[:.]\d{2}|\d{1,2})\s*(?:([AP])\.?\s*M\.?)?'
    r'\s*(?:-|–|—|\bto\b)\s*'
    r'(\d{4}|\d{1,2}[:.]\d{2}|\d{1,2})\s*(?:([AP])\.?\s*M\.?)?',
    caseSensitive: false,
  );

  static final RegExp _singleTimePattern = RegExp(
    r'(\d{4}|\d{1,2}[:.]\d{2})\s*(?:([AP])\.?\s*M\.?)?',
    caseSensitive: false,
  );

  // A bare hour is only trusted when the whole line is the time, which is
  // how rails print it. This keeps "Room 8" or "Fall 8" out of the rail.
  static final RegExp _bareHourLinePattern = RegExp(
    r'^\s*(\d{1,2})\s*(?:([AP])\.?\s*M\.?)?\s*$',
    caseSensitive: false,
  );

  // Period rails are anchored as well: the whole line must be the marker
  // ("P1", "Period 3", "P3-P4"). Both pair tokens need the P/Period prefix
  // so clock-like ranges are never mistaken for periods.
  static final RegExp _periodRailLinePattern = RegExp(
    r'^\s*(?:P\.?\s*|Period\s+)(\d{1,2})\s*'
    r'(?:(?:-|–|—|to)\s*(?:P\.?\s*|Period\s+)(\d{1,2})\s*)?$',
    caseSensitive: false,
  );

  static const _fullDayNames = {
    'monday': 1,
    'tuesday': 2,
    'wednesday': 3,
    'thursday': 4,
    'friday': 5,
    'saturday': 6,
    'sunday': 7,
  };

  static const _dayPrefixes = {
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
  };

  static const _twoLetterDays = {'th': 4, 'sa': 6, 'su': 7};

  // Single-letter column headers, MTWRF convention (R = Thursday).
  static const _singleLetterDays = {
    'm': 1,
    't': 2,
    'w': 3,
    'r': 4,
    'f': 5,
    's': 6,
    'u': 7,
  };

  /// Maps a standalone header cell ("MONDAY", "Thu.", "M") to a weekday
  /// number (1 = Monday .. 7 = Sunday), or null when the cell is not a day
  /// header. Single-letter cells are accepted here on purpose; callers guard
  /// against stray letters elsewhere by requiring several of them.
  static int? dayOfHeaderCell(String cell) {
    final normalized = cell.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (normalized.isEmpty) return null;
    final key = normalized.toLowerCase();
    if (normalized.length >= 3) {
      return _fullDayNames[key] ?? _dayPrefixes[key.substring(0, 3)];
    }
    if (normalized.length == 2) return _twoLetterDays[key];
    return _singleLetterDays[key];
  }

  /// Parses the first time token on a rail line into absolute minutes.
  ///
  /// Returns the minute value plus whether a meridiem was printed, so the
  /// caller can resolve ambiguous 12-hour values against the rest of the
  /// rail. Returns null for lines without a plausible time. Period rails
  /// ("P1", "P3-P4") resolve to the nominal period grid and count as
  /// meridiem-explicit so the sequence resolver never shifts them across
  /// noon.
  static ({int minute, bool meridiemExplicit})? parseRailLine(String text) {
    final period = _periodRailLinePattern.firstMatch(text);
    if (period != null) {
      final times = const PeriodTimes();
      final first = int.tryParse(period.group(1)!);
      final last = period.group(2) == null
          ? first
          : int.tryParse(period.group(2)!);
      if (first != null && last != null && last >= first) {
        final start = times.startOf(first);
        final end = times.endOf(last);
        if (start != null && end != null && end > start && end - start >= 15) {
          return (minute: (start + end) ~/ 2, meridiemExplicit: true);
        }
      }
      return null;
    }
    final range = _rangePattern.firstMatch(text);
    if (range != null) {
      final start = _tokenMinute(range.group(1)!, range.group(2));
      final end = _tokenMinute(range.group(3)!, range.group(4));
      if (start != null && end != null) {
        // "11:00 - 1:00" wraps noon; a year pair like "2025 - 2026" has no
        // wrap that stays within a day and is rejected by the span floor
        // below.
        var resolvedEnd = end;
        if (resolvedEnd <= start) {
          if (resolvedEnd + 720 > 1439) return null;
          resolvedEnd += 720;
        }
        var resolvedStart = start;
        // "8 - 9 PM" pulls the bare start into the evening.
        if (range.group(4) != null &&
            range.group(2) == null &&
            resolvedStart + 720 <= resolvedEnd) {
          resolvedStart += 720;
        }
        // Sub-15-minute spans are table noise, not rail times: the year
        // pair "2025 - 2026" parses as a one-minute range.
        if (resolvedEnd - resolvedStart < 15) return null;
        return (
          minute: (resolvedStart + resolvedEnd) ~/ 2,
          meridiemExplicit: range.group(2) != null || range.group(4) != null,
        );
      }
      // A range-shaped match with implausible bounds ("2025 - 2026") must
      // not fall through to the single-time patterns below.
      return null;
    }
    final bare = _bareHourLinePattern.firstMatch(text);
    if (bare != null) {
      final minute = _tokenMinute(bare.group(1)!, bare.group(2));
      if (minute != null) {
        return (minute: minute, meridiemExplicit: bare.group(2) != null);
      }
    }
    final single = _singleTimePattern.firstMatch(text);
    if (single != null) {
      final minute = _tokenMinute(single.group(1)!, single.group(2));
      if (minute != null) {
        return (minute: minute, meridiemExplicit: single.group(2) != null);
      }
    }
    return null;
  }

  /// Collects time ticks from the margin lines of one page and resolves them
  /// into an ascending sequence of absolute minutes.
  ///
  /// Rails cross noon ("... 11:00, 12:00, 1:00 ...") and often print the
  /// meridiem on only some lines, so bare 12-hour values are carried forward
  /// by the running sequence. Both page-origin conventions (top-left and
  /// bottom-left) are tried and the one with fewer conflicts wins. The
  /// result is ordered by minute, not by position.
  static List<PdfRailTick> resolveRailTicks(
    List<PdfTextLineGeometry> lines, {
    required bool Function(PdfTextLineGeometry line) inMargin,
  }) {
    final candidates = <({double y, int minute, bool meridiemExplicit})>[];
    for (final line in lines) {
      if (!inMargin(line)) continue;
      final parsed = parseRailLine(line.text);
      if (parsed == null) continue;
      candidates.add((
        y: line.centerY,
        minute: parsed.minute,
        meridiemExplicit: parsed.meridiemExplicit,
      ));
    }
    if (candidates.length < 2) return const [];

    final forward = _resolveSequence(candidates);
    final backward = _resolveSequence(candidates.reversed.toList());
    var ticks = forward.dropped <= backward.dropped
        ? forward.ticks
        : backward.ticks.reversed.toList();
    ticks = [...ticks]..sort((a, b) => a.minute.compareTo(b.minute));
    if (ticks.length < 2) return const [];
    if (ticks.last.minute - ticks.first.minute < 60) return const [];
    return ticks;
  }

  static ({List<PdfRailTick> ticks, int dropped}) _resolveSequence(
    List<({double y, int minute, bool meridiemExplicit})> candidates,
  ) {
    final ticks = <PdfRailTick>[];
    var dropped = 0;
    int? last;
    for (final candidate in candidates) {
      var value = candidate.minute;
      if (last != null && !candidate.meridiemExplicit) {
        while (value <= last && value + 720 <= 1439) {
          value += 720;
        }
      }
      if (last != null && value <= last) {
        dropped++;
        continue;
      }
      last = value;
      ticks.add(PdfRailTick(centerY: candidate.y, minute: value));
    }
    return (ticks: ticks, dropped: dropped);
  }

  static int? _tokenMinute(String token, String? meridiem) {
    final value = token.trim();
    int? hour;
    int? minute;
    final military = RegExp(r'^(\d{2})(\d{2})$').firstMatch(value);
    if (military != null) {
      hour = int.parse(military.group(1)!);
      minute = int.parse(military.group(2)!);
    } else {
      final parts = value.split(RegExp(r'[:.]'));
      hour = int.tryParse(parts.first);
      minute = parts.length > 1 ? int.tryParse(parts.last) : 0;
    }
    if (hour == null || minute == null || minute > 59) return null;
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      final isPm = meridiem.toUpperCase() == 'P';
      return (hour % 12 + (isPm ? 12 : 0)) * 60 + minute;
    }
    if (hour > 23) return null;
    return hour * 60 + minute;
  }

  /// Upper-median of a non-empty list.
  static T medianOf<T extends num>(List<T> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }
}
