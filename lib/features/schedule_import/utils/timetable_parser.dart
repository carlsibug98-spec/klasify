import 'schedule_text_parser.dart';

/// Conservative OCR parser for line-oriented timetables.
/// Every parsed entry must still be reviewed by the user before saving.
class ParsedTimetableRow {
  final String subject;
  final String room;
  final String professor;
  final int day;
  final int startMinutes;
  final int endMinutes;
  final double? ocrConfidence;

  const ParsedTimetableRow({
    required this.subject,
    required this.room,
    required this.professor,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    this.ocrConfidence,
  });
}

class TimetableParser {
  static final RegExp _dayPattern = RegExp(
    r'\b(mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday|s)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?|th|sa|su|m(?!\.)|t(?!\.)|w(?!\.)|r(?!\.)|f(?!\.)|s(?!\.)|u(?!\.))\b',
    caseSensitive: false,
  );

  // Compact day groups used in many college timetables (MWF, MTWThF, TTh, TR).
  // These are recognized separately from full weekday names so a course
  // listed once with a repeated weekly pattern expands into one row per day.
  static final RegExp _compactDayPattern = RegExp(
    r'\b(MTWTHF|MTWRF|MTWR|MTW|MWF|MW|TTH|TR)\b',
    caseSensitive: false,
  );
  // The second time may omit AM/PM, as in "8:00 AM - 9:30". Official
  // documents also print compact military times such as "0800-0930" with no
  // hour/minute separator at all, so \d{4} is tried before the clock forms.
  static final RegExp _timePattern = RegExp(
    r'(\d{4}|\d{1,2}(?:[:.]\d{2})?\s*(?:(?:a\.?m\.?|p\.?m\.?))?)\s*(?:-|–|—|to)\s*(\d{4}|\d{1,2}(?:[:.]\d{2})?\s*(?:(?:a\.?m\.?|p\.?m\.?))?)',
    caseSensitive: false,
  );

  /// Flags names that commonly result from OCR merging nearby cells or text.
  static bool looksLikeOcrTextIssue(String subject) {
    final compact = subject.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.length > 36) return true;
    for (var length = 5; length <= compact.length ~/ 2; length++) {
      for (var start = 0; start + length * 2 <= compact.length; start++) {
        final phrase = compact.substring(start, start + length);
        if (phrase == compact.substring(start + length, start + length * 2)) {
          return true;
        }
      }
    }
    return false;
  }

  static List<ParsedTimetableRow> parse(String raw) {
    final rows = <ParsedTimetableRow>[];
    final seen = <String>{};
    var activeDay = 0;
    final lines = raw.replaceAll('\r', '\n').split('\n');

    for (final source in lines) {
      final line = source.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty) continue;

      // OCR often reads a column heading (e.g. "MONDAY") on its own line,
      // followed by subject/time/room rows that do not repeat the weekday.
      final dayMatches = _dayPattern.allMatches(line).toList();
      final compactDayMatches = _compactDayPattern.allMatches(line).toList();
      // Whiteboards and handwritten-style lists often pack several classes on
      // one line ("MON - Algebra 8AM-9AM / Science 10AM-11AM"); those lines
      // need one row per time range, so they take a dedicated path.
      final timeMatches = _timePattern.allMatches(line).toList();
      if (timeMatches.length > 1) {
        _parseMultiClassLine(
          line,
          timeMatches,
          dayMatches,
          compactDayMatches,
          activeDay,
          seen,
          rows,
        );
        continue;
      }
      final timeMatch = timeMatches.isEmpty ? null : timeMatches.first;
      if (timeMatch == null &&
          dayMatches.length == 1 &&
          compactDayMatches.isEmpty) {
        final before = line.substring(0, dayMatches.single.start).trim();
        final after = line.substring(dayMatches.single.end).trim();
        if (before.isEmpty && after.isEmpty) {
          activeDay = _dayNumber(dayMatches.single.group(1)!) ?? activeDay;
          continue;
        }
      }

      int? start;
      int? end;
      var periodBased = false;
      if (timeMatch != null) {
        start = _parseTime(timeMatch.group(1)!);
        end = _parseEndTime(timeMatch.group(2)!, timeMatch.group(1)!);
        start = _pmCarryStart(
          start,
          end,
          timeMatch.group(1)!,
          timeMatch.group(2)!,
        );
      } else {
        // Period-number ranges ("MATH 101 P3-P4") carry no clock times.
        // Nominal times are assumed and the row is flagged for review.
        final periodMatch = PeriodTimes.pairPattern.firstMatch(line);
        if (periodMatch != null) {
          final pair = const PeriodTimes().parseMatch(periodMatch);
          if (pair != null) {
            start = pair.start;
            end = pair.end;
            periodBased = true;
          }
        }
      }
      // A span below 15 minutes is OCR noise, not a class - the year range
      // "2025-2026" parses as the one-minute pair 20:25-20:26, for example.
      if (start == null || end == null || end <= start || end - start < 15) {
        continue;
      }
      final explicitDays = dayMatches
          .map((m) => _dayNumber(m.group(1)!))
          .whereType<int>()
          .toSet();
      for (final match in compactDayMatches) {
        explicitDays.addAll(_compactDays(match.group(1)!));
      }
      final days = explicitDays.isNotEmpty
          ? explicitDays.toList()
          : (activeDay == 0 ? <int>[] : <int>[activeDay]);
      if (days.isEmpty) continue;

      var subject = line
          .replaceAll(_dayPattern, ' ')
          .replaceAll(_compactDayPattern, ' ');
      subject =
          (timeMatch != null
                  ? subject.replaceFirst(_timePattern, ' ')
                  : subject.replaceFirst(PeriodTimes.pairPattern, ' '))
              .replaceAll(RegExp(r'[|•,:;]+'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      subject = subject.replaceAll(RegExp(r'^(?:/\s*)+|(?:\s*/)+$'), '').trim();
      subject = subject
          .replaceAll(RegExp(r'^(?:[-–—]\s*)+|(?:\s*[-–—])+$'), '')
          .trim();
      var details = ScheduleTextDetails.parse(subject);
      if (details.subject.isEmpty && subject.trim().length >= 2) {
        // The whole fragment was consumed as a venue ("Library", "Gym").
        // On list-style entries a class can legitimately be NAMED after its
        // venue, so keep it as the subject and drop the phantom room.
        details = ScheduleTextDetails(
          subject: ScheduleTextDetails.sanitizeSubject(subject),
          room: '',
          professor: '',
        );
      }
      subject = details.subject;
      // Ignore common table headings accidentally recognized as subjects.
      if (subject.length < 2 ||
          RegExp(
            r'^(subject|course|class|time|schedule|room)$',
            caseSensitive: false,
          ).hasMatch(subject)) {
        continue;
      }

      for (final day in days) {
        final key =
            '$day|$start|$end|${subject.toLowerCase()}|${details.room.toLowerCase()}';
        if (seen.add(key)) {
          rows.add(
            ParsedTimetableRow(
              subject: subject,
              room: details.room,
              professor: details.professor,
              day: day,
              startMinutes: start,
              endMinutes: end,
              ocrConfidence: periodBased ? .74 : null,
            ),
          );
        }
      }
    }
    return rows;
  }

  /// Splits a line carrying several time ranges ("MON - Algebra 8AM-9AM /
  /// Science 10AM-11AM") into one row per range. Text before each range is
  /// that class's label; text between two ranges may also hold the previous
  /// class's room or professor, so it is split at its last separator and the
  /// left half is attached to the previous class. Text after the final range
  /// belongs to the last class.
  static void _parseMultiClassLine(
    String line,
    List<RegExpMatch> matches,
    List<RegExpMatch> dayMatches,
    List<RegExpMatch> compactDayMatches,
    int activeDay,
    Set<String> seen,
    List<ParsedTimetableRow> rows,
  ) {
    final entries = <({int? start, int? end, String segment})>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final start = _pmCarryStart(
        _parseTime(match.group(1)!),
        _parseEndTime(match.group(2)!, match.group(1)!),
        match.group(1)!,
        match.group(2)!,
      );
      final end = _parseEndTime(match.group(2)!, match.group(1)!);
      // A span below 15 minutes is OCR noise (year ranges such as
      // "2025-2026" parse as a one-minute pair); its text still flows into
      // the neighbouring segments so nothing is silently dropped twice.
      final valid =
          start != null && end != null && end > start && end - start >= 15;
      final from = i == 0 ? 0 : matches[i - 1].end;
      entries.add((
        start: valid ? start : null,
        end: valid ? end : null,
        segment: line.substring(from, match.start),
      ));
    }
    final tail = line.substring(matches.last.end);
    for (var i = 1; i < entries.length; i++) {
      final segment = entries[i].segment.trim();
      final split = _lastSeparatorIndex(segment);
      if (split < 0) continue;
      entries[i - 1] = (
        start: entries[i - 1].start,
        end: entries[i - 1].end,
        segment: '${entries[i - 1].segment} ${segment.substring(0, split)}',
      );
      entries[i] = (
        start: entries[i].start,
        end: entries[i].end,
        segment: segment.substring(split + 1),
      );
    }
    var lastValid = -1;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].start != null) lastValid = i;
    }
    final lineDays = dayNumberSet(dayMatches, compactDayMatches);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final start = entry.start;
      final end = entry.end;
      if (start == null || end == null) continue;
      final segment = entry.segment;
      // Day tokens inside a segment belong to that class only; when a
      // segment names none, the line-level days (or the active day from a
      // preceding heading line) apply.
      final spanDays = dayNumberSet(
        _dayPattern.allMatches(segment).toList(),
        _compactDayPattern.allMatches(segment).toList(),
      );
      final days = spanDays.isNotEmpty
          ? spanDays
          : lineDays.isNotEmpty
          ? lineDays
          : activeDay == 0
          ? <int>[]
          : <int>[activeDay];
      if (days.isEmpty) continue;
      var text = i == lastValid ? '$segment $tail' : segment;
      text = text
          .replaceAll(_dayPattern, ' ')
          .replaceAll(_compactDayPattern, ' ')
          .replaceAll(RegExp(r'[|•,:;]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      text = text.replaceAll(RegExp(r'^(?:/\s*)+|(?:\s*/)+$'), '').trim();
      text = text
          .replaceAll(RegExp(r'^(?:[-–—]\s*)+|(?:\s*[-–—])+$'), '')
          .trim();
      final details = ScheduleTextDetails.parse(text);
      final subject = details.subject;
      // Ignore common table headings accidentally recognized as subjects,
      // and bare connectives left over when one class lists two time ranges
      // ("Math 8-9 and 10-11" must not become an "and" class).
      if (subject.length < 2 ||
          RegExp(
            r'^(subject|course|class|time|schedule|room)$',
            caseSensitive: false,
          ).hasMatch(subject) ||
          const {
            'and',
            'or',
            'then',
            'with',
            'also',
            'plus',
            'but',
            '&',
          }.contains(subject.toLowerCase())) {
        continue;
      }
      for (final day in days) {
        final key =
            '$day|$start|$end|${subject.toLowerCase()}|${details.room.toLowerCase()}';
        if (seen.add(key)) {
          rows.add(
            ParsedTimetableRow(
              subject: subject,
              room: details.room,
              professor: details.professor,
              day: day,
              startMinutes: start,
              endMinutes: end,
            ),
          );
        }
      }
    }
  }

  static int _lastSeparatorIndex(String text) {
    final slash = text.lastIndexOf('/');
    final semicolon = text.lastIndexOf(';');
    return slash >= semicolon ? slash : semicolon;
  }

  static Set<int> dayNumberSet(
    List<RegExpMatch> dayMatches,
    List<RegExpMatch> compactDayMatches,
  ) {
    final days = dayMatches
        .map((match) => _dayNumber(match.group(1)!))
        .whereType<int>()
        .toSet();
    for (final match in compactDayMatches) {
      days.addAll(_compactDays(match.group(1)!));
    }
    return days;
  }

  static int? _dayNumber(String value) {
    const days = {
      'mon': 1,
      'tue': 2,
      'wed': 3,
      'thu': 4,
      'fri': 5,
      'sat': 6,
      'sun': 7,
      'm': 1,
      't': 2,
      'w': 3,
      'th': 4,
      'r': 4,
      'f': 5,
      'sa': 6,
      's': 6,
      'su': 7,
      'u': 7,
    };
    final normalized = value.toLowerCase();
    return days[normalized] ??
        (normalized.length >= 3 ? days[normalized.substring(0, 3)] : null);
  }

  static List<int> _compactDays(String value) {
    switch (value.toUpperCase()) {
      case 'MWF':
        return [1, 3, 5];
      case 'MW':
        return [1, 3];
      case 'MTWTHF':
      case 'MTWRF':
        return [1, 2, 3, 4, 5];
      case 'MTWR':
        return [1, 2, 3, 4];
      case 'MTW':
        return [1, 2, 3];
      case 'TTH':
      case 'TR':
        return [2, 4];
      default:
        return const [];
    }
  }

  /// Casual lists print "1-3pm" / "1:00-2:30 PM": the meridiem sits only on
  /// the end, and the bare start is morning-ambiguous. When the end carries
  /// an explicit PM and shifting the start into the afternoon still leaves a
  /// valid forward span, the start belongs to the afternoon too.
  static int? _pmCarryStart(
    int? start,
    int? end,
    String startText,
    String endText,
  ) {
    if (start == null || end == null) return start;
    final startHasMeridiem = RegExp(
      r'(?:a\.?m\.?|p\.?m\.?)',
      caseSensitive: false,
    ).hasMatch(startText);
    final endIsPm = RegExp(r'p\.?m\.?', caseSensitive: false).hasMatch(endText);
    if (!startHasMeridiem && endIsPm && start + 720 < end) {
      return start + 720;
    }
    return start;
  }

  static int? _parseTime(String input) {
    final value = input.trim().toUpperCase().replaceAllMapped(
      RegExp(r'\b([AP])\.?\s*M\.?'),
      (match) => '${match.group(1)}M',
    );
    final match = RegExp(
      r'^(?:(\d{1,2})(?:[:.](\d{2}))?|(\d{2})(\d{2}))\s*(AM|PM)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final compactHour = match.group(3);
    var hour = int.parse(compactHour ?? match.group(1)!);
    final minute = int.parse(
      compactHour != null ? match.group(4)! : (match.group(2) ?? '0'),
    );
    final meridiem = match.group(5);
    if (minute > 59) return null;
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (meridiem == 'PM' ? 12 : 0);
    } else if (hour < 0 || hour > 23) {
      return null;
    }
    return hour * 60 + minute;
  }

  static int? _parseEndTime(String endText, String startText) {
    final explicit = _parseTime(endText);
    if (explicit != null &&
        RegExp(
          r'(?:a\.?m\.?|p\.?m\.?)',
          caseSensitive: false,
        ).hasMatch(endText)) {
      return explicit;
    }
    final start = _parseTime(startText);
    if (start == null) return null;
    final endMatch = RegExp(
      r'^(?:(\d{1,2})(?:[:.](\d{2}))?|(\d{2})(\d{2}))$',
    ).firstMatch(endText.trim());
    if (endMatch == null) return explicit;
    final compactHour = endMatch.group(3);
    final hour = int.parse(compactHour ?? endMatch.group(1)!);
    final minute = int.parse(
      compactHour != null ? endMatch.group(4)! : (endMatch.group(2) ?? '0'),
    );
    if (minute > 59) return null;

    // If start is in 12-hour format and end omits AM/PM, infer the nearest
    // later plausible time. For 24-hour ranges, retain 24-hour interpretation.
    final startHasMeridiem = RegExp(
      r'(?:a\.?m\.?|p\.?m\.?)',
      caseSensitive: false,
    ).hasMatch(startText);
    if (!startHasMeridiem) {
      if (hour > 23) return null;
      var result = hour * 60 + minute;
      if (result <= start && result + 720 <= 1440) result += 720;
      return result;
    }
    if (hour < 1 || hour > 12) return null;
    final startIsPm = RegExp(
      r'p\.?m\.?',
      caseSensitive: false,
    ).hasMatch(startText);
    var result = (hour % 12 + (startIsPm ? 12 : 0)) * 60 + minute;
    if (result <= start && result + 720 <= 1440) result += 720;
    return result;
  }
}
