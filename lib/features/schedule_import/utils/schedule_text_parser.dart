import '../../../models/class_item.dart';

class ScheduleTextDetails {
  const ScheduleTextDetails({
    required this.subject,
    required this.room,
    required this.professor,
  });

  final String subject;
  final String room;
  final String professor;

  static final RegExp _roomPattern = RegExp(
    r'\b(?:Room|Rm\.?)\s*[-:#]?\s*[A-Za-z0-9-]+'
    r'|\b(?:Lab|Laboratory)\s*[-:#]?\s*(?:[A-Z]{1,3}\s*[-]?\s*)?\d+[A-Z]?\b'
    r'|\b(?:NetLab|MacLab)\b'
    // Venue names that carry no Room/Lab keyword: "Main Hall", "Hall A",
    // "Studio 1". Without these, the venue leaks into the class name.
    r'|\bMain\s+Hall\b'
    r'|\bHall\s+[A-Z0-9]{1,3}\b'
    r'|\bStudio\s+\d{1,3}\b'
    // Computer labs are usually printed without a room number ("IT Lab",
    // "Computer Lab"); without these tokens the lab leaks into the class
    // name ("Computer IT Lab", "Computer Science, IT Lab"). A negative
    // lookahead keeps a capitalized subject word that follows the token
    // ("Computer Lab Programming") part of the class name.
    r'|\bIT\s+Lab\b(?!\s*[A-Z])'
    r'|\bComputer\s+Lab\b(?!\s*[A-Z])'
    r'|\b(?:Gym|Library|Auditorium|Cafeteria|Home\s+Economics\s+Room|HE\s+Room)\b'
    r'|(?<!\d)[RL]\s*[-]?\s*\d{1,2}[A-Z]?',
    caseSensitive: false,
  );

  // A bare title word standing alone ("RPH Prof.", "- - Prof.") is OCR
  // debris from a professor cell whose name was read elsewhere.
  static final RegExp _titleWordToken = RegExp(
    r'\b(?:prof|professor|instructor|instr)\.?(?=\s|$|[|,;:\-–—])',
    caseSensitive: false,
  );

  // Initial + surname at the end of a line. Particle surnames (de Guzman,
  // Dela Cruz, Van Dyke, San Jose) and compound/all-caps surnames are common
  // in Philippine and Indonesian timetables, so they are accepted too.
  static final RegExp _professorLinePattern = RegExp(
    r"(?:^|\s)"
    r"([A-Z](?:\.|\s+)\s*"
    r"(?:(?:de|del|dela|delas|delos|di|da|das|dos|la|le|las|los|van|von|der|den|ter|san|santa|sto)\.?\s+)*"
    r"(?:[A-Z][a-z]+(?:[A-Z][a-z]+)?|[A-Z]{3,}(?:[-'][A-Z]{2,})?)"
    r"(?:\s+(?:[A-Z][a-z]+|[A-Z]{2,}))*"
    r")\s*[.,]?\s*$",
  );

  // With an explicit title ("Prof. ...") a plain capitalized name at the end
  // of the line is safe to treat as a person, because the title disambiguates
  // it from course words. Accepts initials, particles ("dela Cruz") and up to
  // four name tokens.
  static final RegExp _titledProfessorPattern = RegExp(
    r'\b(?:prof(?:essor)?|instr(?:uctor)?|dr|mr|ms|mrs)\.?:?\s+'
    r'((?:[A-Z]\.?|[A-Z][a-z]+|[A-Z]{2,}|[a-z]{1,5})'
    r'(?:\s+(?:[A-Z]\.?|[A-Z][a-z]+|[A-Z]{2,}|[a-z]{1,5})){0,3})'
    r'\s*[.,]*$',
  );

  static final RegExp _singleLetterRoomPattern = RegExp(
    r'^(?:Room|Rm\.?)\s*[-:#]?\s*([A-Z])$',
    caseSensitive: false,
  );
  static final RegExp _orphanedProfessorSurnamePattern = RegExp(
    r"^[.,;:]?\s*([A-Z][a-z]+(?:[A-Z][a-z]+)?(?:\s+[A-Z][a-z]+)?|[A-Z]{3,}(?:[-'][A-Z]{2,})?)\s*$",
  );

  // --- Subject debris patterns -------------------------------------------
  // Grid cells often carry the printed period ("7:00-8:00", "7-8", "0800-
  // 0930"), the teaching-week date ("June 16", "10 June", "6/16") or a
  // professor title next to the class name. None of that belongs in the
  // subject, and leaving it there merges several fields into one label.

  static final RegExp _militaryTimeRangeToken = RegExp(
    r'\b\d{3,4}\s*(?:-|–|—|to)\s*\d{3,4}\b',
    caseSensitive: false,
  );
  static final RegExp _timeRangeToken = RegExp(
    r'\b\d{1,2}(?:[:.]\d{2})?\s*(?:[AP]\.?M\.?)?\s*(?:-|–|—|to)\s*\d{1,2}(?:[:.]\d{2})?\s*(?:[AP]\.?M\.?)?\b',
    caseSensitive: false,
  );
  static final RegExp _clockToken = RegExp(
    r'\b\d{1,2}:\d{2}\s*(?:[AP]\.?M\.?)?\b',
    caseSensitive: false,
  );
  static final RegExp _dottedClockToken = RegExp(
    r'\b\d{1,2}\.\d{2}\s*(?:[AP]\.?M\.?)?\b',
    caseSensitive: false,
  );
  static final RegExp _meridiemToken = RegExp(
    r'\b[AP]\.?M\.?\b',
    caseSensitive: false,
  );
  static final RegExp _monthDateToken = RegExp(
    r'\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?(?:\s*\d{1,2})?(?:\s*,?\s*\d{4})?\b',
    caseSensitive: false,
  );
  static final RegExp _dayMonthDateToken = RegExp(
    r'\b\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?(?:\s*,?\s*\d{4})?\b',
    caseSensitive: false,
  );
  static final RegExp _numericDateToken = RegExp(
    r'\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b',
  );
  static final RegExp _weekdayToken = RegExp(
    r'\b(?:mon|tues?|wed(?:nes)?|thur?s?|fri|sat|sun)(?:day)?\b',
    caseSensitive: false,
  );
  static final RegExp _standaloneDashRun = RegExp(r'(?:^|\s)[-–—=|]+(?=\s|$)');
  static const List<String> _placeholderSubjects = [
    'na',
    'n a',
    'tba',
    'tbd',
    'none',
    'n/a',
  ];

  /// "(both days)" & friends: a row tag saying the entry repeats for every
  /// day of the line's derived context, never part of the class name.
  static final RegExp bothDaysTag = RegExp(
    r'\(\s*both\s+days?\s*\)?|\(\s*(?:two|2)\s+days\s*\)|both\s+days',
    caseSensitive: false,
  );

  /// Removed ranges leave comma runs ("Computer Science, , IT Lab").
  static final RegExp _commaRun = RegExp(r'(?:\s*,\s*){2,}');

  /// Stray period tokens left by wrapped ranges ("English .", "History .").
  /// Initial dots ("P.E.", "J. Sarmiento") keep the dot because it is glued
  /// to the letter, never preceded by a space.
  static final RegExp _looseDotToken = RegExp(r'\s\.(?=\s|$)');

  /// Dangling tail words after the real subject was extracted.
  static const Set<String> _trailingNoise = {
    'in', 'at', 'on', 'for', 'of', 'to', 'and', 'with', 'then', 'by',
    'the', 'a', 'after', 'followed', 'up', 'lunch', 'recess', 'break',
  };

  /// Removes time, date, weekday, title-word and dash debris from a subject
  /// fragment without touching any real course label content.
  static String sanitizeSubject(String text) {
    var cleaned = text;
    cleaned = cleaned.replaceAll(_militaryTimeRangeToken, ' ');
    cleaned = cleaned.replaceAll(_timeRangeToken, ' ');
    cleaned = cleaned.replaceAll(_dottedClockToken, ' ');
    cleaned = cleaned.replaceAll(_clockToken, ' ');
    cleaned = cleaned.replaceAll(_meridiemToken, ' ');
    cleaned = cleaned.replaceAll(_dayMonthDateToken, ' ');
    cleaned = cleaned.replaceAll(_numericDateToken, ' ');
    cleaned = cleaned.replaceAll(_monthDateToken, ' ');
    cleaned = cleaned.replaceAll(_weekdayToken, ' ');
    cleaned = cleaned.replaceAll(_titleWordToken, ' ');
    cleaned = cleaned.replaceAll(_standaloneDashRun, ' ');
    cleaned = cleaned.replaceAll(bothDaysTag, ' ');
    cleaned = _collapseCommaRuns(cleaned);
    cleaned = cleaned.replaceAll(_looseDotToken, ' ');
    cleaned = _stripTrailingTokens(cleaned);
    cleaned = _dropProseLeadIn(cleaned);
    cleaned = _dropLeadingLowercase(cleaned);
    // Edge debris: separators, unmatched brackets left behind after date and
    // weekday tokens were stripped ("Nov 07 (Thu)" -> "( )"), and dashes.
    cleaned = cleaned
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[|,;:()\[\]\s-]+|[|,;:()\[\]\s-]+$'), '')
        .trim();
    return cleaned;
  }

  static String _collapseCommaRuns(String text) =>
      text.replaceAll(_commaRun, ', ');

  /// Trailing words that never close a subject: connectors, meal/section
  /// markers, and single-letter OCR debris ("Science e").
  static String _stripTrailingTokens(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    while (words.length >= 2) {
      final last = words.last.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (last.length == 1 && RegExp(r'^[a-z]$').hasMatch(last)) {
        words.removeLast();
        continue;
      }
      if (_trailingNoise.contains(last)) {
        words.removeLast();
        continue;
      }
      break;
    }
    return words.join(' ');
  }

/// Prose flow around the subject ("wraps up with Computer", "Please bring
    /// calculators for Geometry"): a lowercase word directly before a
    /// capitalized one marks where the real subject starts. "English Lit"
    /// keeps both words because their capitalized neighbour is not lowercase.
    /// The lead-in is only dropped when at least two lowercase words precede
    /// the capitalized one: a one-word preposition ("for Geometry", "in
    /// Tech") is part of the course label, while a prose clause ("Friday
    /// wraps up with Computer") is not.
    static String _dropProseLeadIn(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length < 3) return text;
    for (var i = 1; i < words.length; i++) {
      final lowerBefore = RegExp(r'^[a-z]').hasMatch(words[i - 1]);
      final capitalizedAfter = RegExp('^[A-Z.]').hasMatch(words[i]);
      if (lowerBefore && capitalizedAfter) {
        var lowerRun = 0;
        for (var j = i - 1; j >= 0 && RegExp(r'^[a-z]').hasMatch(words[j]); j--) {
          lowerRun++;
        }
        if (lowerRun >= 2) return words.sublist(i).join(' ');
      }
    }
    return text;
  }

  /// A last pass after weekday/date tokens were stripped: a subject that now
  /// starts with a lowercase word ("Tuesday has English" -> "has English")
  /// is a prose verb riding on a section header, not a course label. Course
  /// labels start with a capitalized word ("Ethics in Tech"), so this never
  /// touches them.
  static String _dropLeadingLowercase(String text) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length < 2) return text;
    var i = 0;
    while (i < words.length - 1 &&
        RegExp(r'^[a-z]').hasMatch(words[i])) {
      i++;
    }
    return i == 0 ? text : words.sublist(i).join(' ');
  }

  /// True when the remaining subject is only an OCR placeholder such as
  /// "N/A" or "TBA" rather than a class name.
  static bool isPlaceholderSubject(String subject) => _placeholderSubjects
      .contains(subject.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim());

  factory ScheduleTextDetails.parse(String text) =>
      ScheduleTextDetails.parseLines([text]);

  static String _collapseRepeatedPhrases(String text) {
    final words = text.split(RegExp(r'\s+'));
    var changed = true;
    while (changed) {
      changed = false;
      // Full adjacent copies: "…Issues in IT Social…Issues in IT". The
      // longest possible pair is tried first so a whole-name copy wins
      // over any shorter fragment overlap.
      for (
        var phraseLength = words.length ~/ 2;
        phraseLength >= 2 && !changed;
        phraseLength--
      ) {
        for (var start = 0; start + phraseLength * 2 <= words.length; start++) {
          if (_phrasesMatch(words, start, start + phraseLength, phraseLength)) {
            words.removeRange(start + phraseLength, start + phraseLength * 2);
            changed = true;
            break;
          }
        }
      }
      // Trailing partial copy: the row often ends mid-name ("…Issues in IT
      // Social and Professional Issues"). A tail that runs to the end of
      // the text and reads as the start of the phrase before it is a cut-
      // off OCR copy, so the tail is dropped. The tail aligns with the
      // head from its first word, which is what keeps this from eating
      // real course labels.
      for (var start = 0; start + 5 <= words.length && !changed; start++) {
        for (
          var phraseLength = words.length - start - 2;
          phraseLength >= 3 && !changed;
          phraseLength--
        ) {
          final tailLength = words.length - start - phraseLength;
          if (_phrasesMatch(words, start, start + phraseLength, tailLength)) {
            words.removeRange(start + phraseLength, words.length);
            changed = true;
            break;
          }
        }
      }
    }
    return words.join(' ');
  }

  /// Average per-word OCR-tolerant similarity of [words][first..first+len)
  /// against [words][second..second+len), matching whole phrases only when
  /// at least two words line up.
  static bool _phrasesMatch(
    List<String> words,
    int first,
    int second,
    int length,
  ) {
    if (length < 2 || second + length > words.length) return false;
    var similarity = 0.0;
    for (var offset = 0; offset < length; offset++) {
      final a = words[first + offset]
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final b = words[second + offset]
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (a.isEmpty || b.isEmpty) continue;
      similarity +=
          1 -
          _editDistance(a, b) /
              (a.length > b.length ? a.length : b.length);
    }
    return similarity / length >= .8;
  }

  static int _editDistance(String first, String second) {
    var previous = List<int>.generate(second.length + 1, (i) => i);
    for (var i = 0; i < first.length; i++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < second.length; j++) {
        final substitutionCost = first[i] == second[j] ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + substitutionCost,
        ].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous.last;
  }

  static String _removeProfessorSuffix(
    String subject,
    Iterable<String> professors,
  ) {
    var cleaned = subject;
    for (final professor in professors) {
      final nameParts = professor
          .split(RegExp(r'[\s.]+'))
          .where((part) => part.isNotEmpty)
          .map(RegExp.escape)
          .toList();
      if (nameParts.isEmpty) continue;
      final namePattern = nameParts.join(r'[\s.]*');
      // The printed title may still sit in front of the extracted name
      // ("RPH Prof. R. Santos" -> professor "R. Santos").
      cleaned = cleaned.replaceFirst(
        RegExp(
          r'(?:^|\s)(?:(?:prof(?:essor)?|instr(?:uctor)?|dr|mr|ms|mrs)\.?:?\s+)?'
          '$namePattern\\.?\\s*\$',
          caseSensitive: false,
        ),
        '',
      );
    }
    return cleaned
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[|,;:()\[\]\s-]+|[|,;:()\[\]\s-]+$'), '')
        .trim();
  }

  factory ScheduleTextDetails.parseLines(Iterable<String> lines) {
    final subjects = <String>[];
    final rooms = <String>[];
    final professors = <String>[];
    final normalizedLines = lines
        .map(
          (line) =>
              line.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();
    for (var i = 0; i < normalizedLines.length; i++) {
      var normalized = normalizedLines[i];
      if (RegExp(
            r'^(?:Room|Rm\.?|Lab|Laboratory)$',
            caseSensitive: false,
          ).hasMatch(normalized) &&
          i + 1 < normalizedLines.length &&
          RegExp(
            r'^(?:[A-Z]{1,3}\s*[-]?\s*)?\d+[A-Z]?$',
            caseSensitive: false,
          ).hasMatch(normalizedLines[i + 1])) {
        normalized = '$normalized ${normalizedLines[++i]}';
      }

      final roomMatch = _roomPattern.firstMatch(normalized);
      var remainder = normalized;
      if (roomMatch != null) {
        final roomText = roomMatch
            .group(0)!
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final singleLetterRoom = _singleLetterRoomPattern.firstMatch(roomText);
        final trailingText = normalized.substring(roomMatch.end).trim();
        final orphanedSurname = singleLetterRoom == null
            ? null
            : _orphanedProfessorSurnamePattern.firstMatch(trailingText);

        // OCR can mistake the professor's initial for the room code, leaving
        // only the surname after the room token (for example, "Room R .Tiongco").
        // Recover the instructor and flag the room for review instead of saving
        // the initial as a confidently parsed room.
        if (singleLetterRoom != null && orphanedSurname != null) {
          professors.add(
            '${singleLetterRoom.group(1)!.toUpperCase()}. ${orphanedSurname.group(1)!.trim()}',
          );
          rooms.add('Room to confirm');
          remainder = normalized.substring(0, roomMatch.start);
        } else {
          rooms.add(roomText);
          remainder = normalized.replaceRange(
            roomMatch.start,
            roomMatch.end,
            ' ',
          );
        }
      }

      // A titled professor ("Prof. R. Santos", "Instructor: De Vera") is
      // matched first so the title itself never leaks into the subject; the
      // bare initial+surname form stays as the conservative fallback.
      final titledMatch = _titledProfessorPattern.firstMatch(remainder);
      if (titledMatch != null) {
        professors.add(titledMatch.group(1)!.trim());
        remainder = remainder.substring(0, titledMatch.start);
      } else {
        final professorMatch = _professorLinePattern.firstMatch(remainder);
        if (professorMatch != null) {
          professors.add(professorMatch.group(1)!.trim());
          remainder = remainder.substring(0, professorMatch.start);
        }
      }

      final subject = sanitizeSubject(
        remainder
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'^[|,;:()\[\]\s-]+|[|,;:()\[\]\s-]+$'), '')
            .replaceAll(RegExp(r'\biT\b'), 'IT')
            .trim(),
      );
      if (subject.isNotEmpty && !isPlaceholderSubject(subject)) {
        subjects.add(subject);
      }
    }
    final subject = sanitizeSubject(
      _removeProfessorSuffix(
        subjects.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
        professors,
      ),
    );
    return ScheduleTextDetails(
      subject: _collapseRepeatedPhrases(subject),
      room: rooms.isEmpty ? 'Room to confirm' : rooms.first,
      professor: professors.isEmpty ? unspecifiedProfessor : professors.first,
    );
  }
}

/// Nominal period-grid times for schools that print period numbers ("P1",
/// "Period 2", "P3-P4") instead of clock times. The printed legend mapping
/// periods to actual times is rarely captured by a scan, so a default grid is
/// assumed: P1 starts at 08:00 and every period lasts 60 minutes. Rows built
/// from period numbers are flagged for review because of that assumption.
class PeriodTimes {
  const PeriodTimes({this.firstPeriodStart = 8 * 60, this.periodMinutes = 60});

  final int firstPeriodStart;
  final int periodMinutes;

  static const int minPeriod = 1;
  static const int maxPeriod = 12;

  /// "P3-P4", "Period 1 - Period 2", "P2 to P3". Both tokens must carry the
  /// P/Period prefix: a bare second number ("P3-4") is ambiguous with
  /// clock-like ranges and is rejected.
  static final RegExp pairPattern = RegExp(
    r'\b(?:P\.?\s*|Period\s+)(\d{1,2})\s*(?:-|–|—|to)\s*'
    r'(?:P\.?\s*|Period\s+)(\d{1,2})\b',
    caseSensitive: false,
  );

  int? startOf(int period) => period >= minPeriod && period <= maxPeriod
      ? firstPeriodStart + (period - 1) * periodMinutes
      : null;

  /// End of a period is exclusive: the end of P4 is the start of P5, so
  /// "P3-P4" spans both periods entirely.
  int? endOf(int period) {
    final start = startOf(period);
    return start == null ? null : start + periodMinutes;
  }

  /// Parses the first period pair in [text] into an inclusive minute range,
  /// or null when no valid pair is present.
  ({int start, int end})? parsePair(String text) {
    final match = pairPattern.firstMatch(text);
    return match == null ? null : parseMatch(match);
  }

  /// Parses an already-matched pair pattern (kept separate so callers that
  /// matched the pattern against a different string offset can reuse it).
  ({int start, int end})? parseMatch(RegExpMatch match) {
    final first = int.tryParse(match.group(1)!);
    final last = int.tryParse(match.group(2)!);
    if (first == null || last == null || last < first) return null;
    final start = startOf(first);
    final end = endOf(last);
    if (start == null || end == null || end <= start) return null;
    return (start: start, end: end);
  }
}
