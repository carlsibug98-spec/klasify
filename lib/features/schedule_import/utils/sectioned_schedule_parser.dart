import '../../../models/class_item.dart';
import 'schedule_line_preparation.dart';
import 'schedule_text_parser.dart';

/// A parsed schedule row plus the assumptions that produced it. Rows that
/// relied on positional inference (slot cycling, row professors, single
/// times, calendar dates) carry [assumptions] and an [ocrConfidence] of
/// 0.74 (matching the PDF rescue path) so the review screen flags them.
class SectionedRow {
  const SectionedRow({
    required this.subject,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    required this.room,
    required this.professor,
    required this.ocrConfidence,
    required this.assumptions,
  });

  final String subject;
  final int day;
  final int startMinutes;
  final int endMinutes;
  final String room;
  final String professor;
  final double? ocrConfidence;
  final List<String> assumptions;
}

/// Parses schedule text that does not put one complete class on each line.
///
/// The classic list parser needs "day + time + subject" inline. Real school
/// schedules rarely cooperate, so this state machine additionally handles:
///
///  * weekday header bands ("MON TUE WED THU FRI" on consecutive lines) ->
///    slot mode: cells get days by their printed column order (faculty
///    grids, period rows, hour grids whose rail did not OCR);
///  * section headers ("Monday" alone) -> day carryover below the header;
///  * row markers: a standalone "Prof. R. DeJesus" (faculty row) or "P1" /
///    "Period 2" (period row) resets the slot counter, so one missed cell
///    can only misalign its own row;
///  * "No class" cells advance the slot without emitting a row;
///  * day-less blocks (subject / time / room / professor stacked lines):
///    the day comes from context; when no day exists anywhere (tables with
///    no day column) rows are emitted flagged with a Monday default;
///  * exam records ("Nov 07 (Thu)" + time + subject + room + professor):
///    the weekday comes from the date line;
///  * month calendars: a 7-column weekday band turns bare date numbers
///    ("2", "15") into weekdays by column position (Sunday-first grids);
///  * single printed times ("Mon 09:00 Art History Room 12 Prof. L. Santos"
///    and card layouts like "11:00  Room 5") become start + 60 minutes,
///    flagged for review.
///
/// Hour-rail ticks (a lone "7:00" line) never become class times.
class SectionedScheduleParser {
  SectionedScheduleParser._();

  // -- vocabulary ---------------------------------------------------------
  static final RegExp _weekdayWord = RegExp(
    r'^(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday|s)?|thu(?:rsday)?|thur?s?|'
    r'fri(?:day)?|sat(?:urday)?|sun(?:day)?)$',
    caseSensitive: false,
  );
  static const Map<String, int> _dayNumbers = {
    'mon': 1,
    'monday': 1,
    'tue': 2,
    'tues': 2,
    'tuesday': 2,
    'wed': 3,
    'weds': 3,
    'wednesday': 3,
    'thu': 4,
    'thur': 4,
    'thurs': 4,
    'thursday': 4,
    'fri': 5,
    'friday': 5,
    'sat': 6,
    'saturday': 6,
    'sun': 7,
    'sunday': 7,
  };
  static int? _dayOf(String word) =>
      _dayNumbers[word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')];

  /// "TUES + WEDS", "MON/WED", "MON and TUE" — two weekday tokens joined by a
  /// separator name one multi-day block. Header bands (3+ weekday tokens)
  /// keep their slot-mode behaviour; a pair header only carries the days
  /// themselves. A "(both days)" row under a pair header must expand to
  /// every day listed, so the parse keeps the pair in [parse].
  static List<int>? _multiDayHeader(String line) {
    if (RegExp(r'\d').hasMatch(line)) return null;
    if (!RegExp(r'^[A-Za-z+/\s,\u2013\u2014-]+$').hasMatch(line)) return null;
    final tokens = line
        .toLowerCase()
        .replaceAll(RegExp(r'\band\b'), ' ')
        .split(RegExp(r'[^a-z]+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.length != 2) return null;
    final first = _dayOf(tokens[0]);
    final second = _dayOf(tokens[1]);
    if (first == null || second == null) return null;
    return [first, second];
  }

  /// "(both days)": the row applies to every day of the open context.
  /// Defined once in [ScheduleTextDetails] since subject cleanup needs it too.
  static final RegExp _bothDaysTag = ScheduleTextDetails.bothDaysTag;

  /// Chat-app metadata stamps ("Today 9:12 AM", "Yesterday 10:11 PM") are UI
  /// chrome, never class rows.
  static final RegExp _uiTimestampLine = RegExp(
    r'^(?:today|yesterday)\b.*\d{1,2}:\d{2}\b',
    caseSensitive: false,
  );

  /// Notice-board items with a day and a time that are not classes.
  static final RegExp _noticeNoise = RegExp(
    r'\b(?:fire\s*drills?|pta|ptm|parents?\s*[-]?\s*teachers?\b|announcement'
    r'|assembly\s+hall)\b',
    caseSensitive: false,
  );

  /// A lost-and-found / notice body entry: a time, a dash, and a single
  /// capitalized name ("Thursday 4:00 PM - Anne", "Friday 10:00 AM e
  /// Thursday 4:00 PM - Anney -"). The name is the person who found the item,
  /// not a class; emitting it as one would invent a class from a notice body.
  /// A class label is at least two words or carries a room/professor token.
  /// Anchored at the end of the line so an OCR-merged notice line
  /// ("Friday 10:00 AM e Thursday 4:00 PM - Anne") is caught too, and a
  /// trailing dash/dot ("Anney -") from OCR noise is tolerated.
  static final RegExp _noticeBodyName = RegExp(
    r'(?:^|\s)(?:Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|'
    r'Fri(?:day)?|Sat(?:urday)?|Sun(?:day)?)?\s*'
    r'\d{1,2}(?::\d{2})?\s*(?:AM|PM|am|pm)?\s*[-–—]\s*[A-Z][A-Za-z]+\.?'
    r'(?:\s*[-–—]|\s*\.|\s*)$',
    caseSensitive: false,
  );

  static bool _isNoticeBodyName(String line) =>
      _noticeBodyName.hasMatch(line) &&
      !RegExp(r'\b(?:Room|Rm|Lab|Gym|Library|Studio|Hall|Auditorium|'
          r'Cafeteria|IT\s+Lab|Computer\s+Lab)\b', caseSensitive: false)
          .hasMatch(line);

  /// Lines whose last word is table metadata are titles
  /// ("ROOM 12 - WEEK SCHEDULE"), so a room token inside them must not
  /// pre-charge the first cell below the title. Printed titles are usually
  /// all-caps; that keeps "History 1pm-2:30pm" (ends in "pm") away.
  static final RegExp _lastWord = RegExp(r'([A-Za-z]+)\s*$');

  static bool _isTitleLine(String line) {
    if (RegExp(r'[a-z]').hasMatch(line)) return false;
    final word = _lastWord.firstMatch(line)?.group(1);
    return word != null && _tableMetadata.contains(word.toLowerCase());
  }

  /// A lone clock at the end of a wordy line ("Math starts the day at
  /// 8:00," — with or without a meridiem) reads a start time, but prose
  /// rows print no published end; a row must not be invented from that
  /// hint. Meridiem-less clocks ("at 8:00,") must be caught too.
  static final RegExp _proseClockTail = RegExp(
    r'\d{1,2}:\d{2}\s*(?:[AP]\.?M\.?)?[\s.,;:)*]*$',
    caseSensitive: false,
  );

  static bool _isProseSingleClock(String line) {
    final match = _proseClockTail.firstMatch(line);
    if (match == null) return false;
    final before = line.substring(0, match.start).trim();
    if (before.isEmpty) return false;
    // One word before the clock ("Math 8:00") is a time-less label that
    // legitimately parses as a start-only class; two or more words ("Math
    // starts the day at 8:00") is a prose sentence.
    return before.split(RegExp(r'\s+')).length >= 2;
  }

  /// Any weekday token inside a longer line ("Nov 07 (Thu)", "Mon 09:00").
  static final RegExp _inlineWeekday = RegExp(
    r'\b(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday|s)?|thu(?:rsday)?|thur?s?|'
    r'fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b',
    caseSensitive: false,
  );

  static final RegExp _standaloneBareNumber = RegExp(r'^\d{1,2}$');
  static final RegExp _monthDate = RegExp(
    r'\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|'
    r'Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|'
    r'Dec(?:ember)?)\.?(?:\s*\d{1,2})?(?:\s*,?\s*\d{4})?\b',
    caseSensitive: false,
  );
  static final RegExp _periodMarker = RegExp(
    r'^(?:P\s*\d{1,2}|Period\s*\d{1,2}|PERIOD\s*\d{1,2})$',
    caseSensitive: false,
  );
  static final RegExp _noClass = RegExp(
    r'^(?:no\s*class|n/a|___+)$',
    caseSensitive: false,
  );
  static const Set<String> _tableMetadata = {
    'time',
    'subject',
    'room',
    'professor',
    'instructor',
    'date',
    'day',
    'days',
    'venue',
    'schedule',
    'course',
    'class',
    'lunch',
    'break',
    'recess',
    'times',
    'rooms',
    'teachers',
    'no',
    'am',
    'pm',
    'hr',
    'hrs',
    'class schedule',
    'class timetable',
    'name',
    'section',
    'units',
  };

  // -- entry point ----------------------------------------------------------
  static List<SectionedRow> parse(String raw) {
    final rows = <SectionedRow>[];
    final seen = <String>{};
    final lines = prepareScheduleLines(raw);

    var activeDay = 0;
    // Days of an open multi-day header ("TUES + WEDS"). Cleared by any
    // single-day section header.
    var activeDays = const <int>[];
    var slotDays = <int>[];
    var slotIndex = 0;
    var rowProfessor = '';
    var calendarMode = false;
    var streakDays = <int>[];
    var inWeekdayStreak = false;
    // Time-rail layouts print each row's range once, above its cells
    // ("08:00-10:00" then the row's classes). Time-inside-cell layouts put
    // the range between the subject and the room. The last processed line's
    // kind distinguishes them.
    _TimeInfo? rowTime;
    var lastLineKind = '';
    final pending = _PendingCell();

    // Emits the open cell. An emitted cell consumes exactly one slot; a
    // "No class" placeholder consumes one via [consumeSlot] on top of any
    // slot the emitted cell already took.
    void flush({bool consumeSlot = false}) {
      if (pending.isComplete) {
        final emitted = _emit(
          pending,
          activeDay,
          slotDays,
          slotIndex,
          rowProfessor,
          calendarMode,
          activeDays,
        );
        for (final row in emitted) {
          final key = '${row.day}|${row.startMinutes}'
              '|${row.endMinutes}|${row.subject.toLowerCase()}'
              '|${row.room.toLowerCase()}';
          if (seen.add(key)) rows.add(row);
        }
        if (slotDays.isNotEmpty) slotIndex++;
      }
      if (consumeSlot && slotDays.isNotEmpty) slotIndex++;
      pending.clear();
    }

    for (final line in lines) {
      // 0. Chat-app UI chrome and notice-board items ("Today 9:12 AM",
      //    "FIRE DRILL 10:00") carry day-and-time shapes but are not class
      //    rows; they must not open a cell either.
      if (_uiTimestampLine.hasMatch(line) ||
          _noticeNoise.hasMatch(line) ||
          _isNoticeBodyName(line)) {
        flush();
        lastLineKind = 'other';
        continue;
      }
      // 0. A joined OCR band can put a whole weekday header row on one line
      //    ("Sun | Mon | Tue | Wed | Thu | Fri | Sat", joined with pipes by
      //    the region joiner, or printed with spaces). Split it into the
      //    equivalent standalone weekday lines so the header-band streak
      //    still engages.
      final bandParts = line
          .split(RegExp(r'[|\s]+'))
          .where((part) => part.isNotEmpty)
          .toList();
      if (bandParts.length >= 3 &&
          bandParts.length <= 8 &&
          bandParts.every((part) => _weekdayWord.hasMatch(part))) {
        for (final part in bandParts) {
          final d = _dayOf(part);
          if (d != null) streakDays.add(d);
        }
        inWeekdayStreak = true;
        continue;
      }
      // 0.5. Multi-day pair header: "TUES + WEDS", "MON/WED", "MON and TUE".
      // The open cell above the header is closed FIRST, so the row printed
      // before the header keeps its own day: the header belongs to the rows
      // below it, not to the previous one.
      final pairDays = _multiDayHeader(line);
      if (pairDays != null) {
        flush();
        activeDay = pairDays.last;
        activeDays = pairDays;
        streakDays = <int>[];
        inWeekdayStreak = false;
        slotDays = <int>[];
        rowTime = null;
        lastLineKind = 'other';
        continue;
      }
      // 1. Standalone weekday: a section header or part of a header band.
      if (_weekdayWord.hasMatch(line)) {
        final d = _dayOf(line);
        if (d != null) streakDays.add(d);
        inWeekdayStreak = true;
        continue;
      }
      if (inWeekdayStreak) {
        // Close anything left open above the header (titles, stale cells).
        flush();
        activeDays = const <int>[];
        if (streakDays.length >= 3) {
          // A printed column-header band: cells below follow column order.
          slotDays = streakDays.toList();
          slotIndex = 0;
          rowProfessor = '';
          calendarMode = streakDays.length == 7;
        } else if (streakDays.isNotEmpty) {
          activeDay = streakDays.last;
          slotDays = const [];
        }
        streakDays = <int>[];
        inWeekdayStreak = false;
        lastLineKind = 'other';
      }

      // 2. Row markers reset the slot counter so one missed cell can only
      //    misalign its own row. A mid-cell professor line ("... Prof. X"
      //    completing a cell) never reaches here: the guard requires the
      //    pending cell NOT to be already complete.
      final professorLine = _standaloneTitledProfessor(line);
      // A titled professor line is a ROW LABEL (faculty grids) when the
      // pending cell is still open, or when it is a compact slot-mode cell
      // (subject + room-time: such cells never print their own professor).
      // Cells that print a room line before the professor (four-line cells)
      // keep the professor for themselves.
      if (professorLine != null &&
          (!pending.isComplete ||
              (slotDays.isNotEmpty && pending.lineCount <= 2))) {
        flush();
        rowProfessor = professorLine;
        slotIndex = 0;
        lastLineKind = 'other';
        continue;
      }
      if (_periodMarker.hasMatch(line)) {
        flush();
        slotIndex = 0;
        lastLineKind = 'other';
        continue;
      }
      if (_noClass.hasMatch(line)) {
        flush(consumeSlot: true);
        lastLineKind = 'other';
        continue;
      }
      if (_tableMetadata.contains(line.toLowerCase())) {
        flush(); // a printed table header; stale titles above it are dropped
        lastLineKind = 'other';
        continue;
      }

      // 3. Bare calendar date inside a 7-column weekday band ("2", "15").
      if (calendarMode && _standaloneBareNumber.hasMatch(line)) {
        final date = int.parse(line);
        if (date >= 1 && date <= 31) {
          flush();
          pending.day = slotDays[(date - 1) % slotDays.length];
          pending.calendarDate = true;
          lastLineKind = 'other';
          continue;
        }
      }

      // 4. Exam-style date line: "Nov 07 (Thu)". The date never reaches the
      //    subject; the weekday inside the line becomes the day.
      final examDay = _examDateWeekday(line);
      if (examDay != null) {
        flush();
        pending.day = examDay;
        pending.examRecord = true;
        lastLineKind = 'other';
        continue;
      }

      // 4.5. A title line ("ROOM 12 - WEEK SCHEDULE") is layout chrome; it
      // must not pre-charge the first cell below it with its room token.
      // Title check happens after extraction because hours ending in
      // "am"/"pm" touch the same metadata vocabulary.
      final isTitle = _isTitleLine(line);

      // 5. Time information on the line, if any.
      var time = _TimeInfo.extract(line);
      // A single clock ending a prose sentence ("Math starts the day at
      // 8:00,") is a start hint, not a published time: prose rows print no
      // end, so the line is dropped entirely instead of feeding its words
      // into the pending cell. The weekday the sentence names ("On
      // Monday, ...") still carries over for the classes it introduces.
      if (time != null && time.single && _isProseSingleClock(line)) {
        flush();
        final weekday = _inlineWeekday.firstMatch(line);
        if (weekday != null && slotDays.isEmpty) {
          final day = _dayOf(weekday.group(0)!);
          if (day != null) activeDay = day;
        }
        lastLineKind = 'other';
        continue;
      }
      final remainder = time == null ? line : time.remainderOf(line);

      if (time == null && isTitle) {
        flush();
        lastLineKind = 'other';
        continue;
      }

      if (time != null && time.single && remainder.isEmpty) {
        // A lone clock label ("7:00") is a rail/axis tick, never a class
        // time; it simply closes whatever cell was open above it.
        flush();
        lastLineKind = 'other';
        continue;
      }

      if (time != null && remainder.isEmpty) {
        // A whole-line time range. Three layouts print these:
        //  (a) a row label above its cells (time-rail tables): the range
        //      closes the previous row and timestamps the next;
        //  (b) the time inside a cell, printed right after its subject line;
        //  (c) a sibling cell of the same row, printed right after the
        //      previous cell's room/professor line: it needs the row label.
        if (pending.isComplete) {
          flush();
          slotIndex = 0;
          rowTime = time;
        } else if (pending.hasSubject && lastLineKind == 'subject') {
          pending.time = time; // (b) the subject line just above owns it
          pending.lineCount++;
        } else if (pending.hasSubject && rowTime != null) {
          pending.time = rowTime; // (c) sibling cell in the previous row
          flush();
          slotIndex = 0;
          rowTime = time;
        } else {
          rowTime = time; // (a) a label above the row's first cell
        }
        lastLineKind = 'time';
        continue;
      }

      if (time != null) {
        if (pending.isComplete) {
          // A range that arrives while a complete cell is open: the previous
          // row is done and this is the next row's label in a time-rail
          // layout, so restart the column cycle.
          flush();
          slotIndex = 0;
        }
        pending.time = time;
        pending.lineCount++;
        final inlineDay = _absorbInlineDay(pending, remainder);
        // An inline weekday ("Mon -", "Monday:") also names the day of the
        // rows that follow it, so it stays on as the day context.
        if (inlineDay != null && slotDays.isEmpty) activeDay = inlineDay;
        if (remainder.isNotEmpty) {
          _absorbFields(pending, remainder);
          if (_bothDaysTag.hasMatch(remainder)) pending.bothDays = true;
        }
        lastLineKind = 'fields';
        continue;
      }

      // 6. Content without a time: a room, a professor, or a subject line.
      // A subject line printed right after a row label (time-rail layout)
      // inherits the label's range as the cell time.
      if (lastLineKind == 'time' &&
          rowTime != null &&
          !pending.hasSubject &&
          pending.time == null) {
        pending.time = rowTime;
        pending.lineCount++;
      }
      final inlineDay = _absorbInlineDay(pending, line);
      if (inlineDay != null && slotDays.isEmpty) activeDay = inlineDay;
      if (_bothDaysTag.hasMatch(line)) pending.bothDays = true;
      final details = ScheduleTextDetails.parse(line);
      final isNewSubject = details.subject.isNotEmpty;
      if (isNewSubject && pending.hasSubject) {
        flush(); // record boundary inside a section
      }
      _absorbDetails(pending, details);
      pending.lineCount++;
      lastLineKind = isNewSubject ? 'subject' : 'fields';
    }
    // EOF: a cell with subject and fields but no time of its own belongs to
    // the last printed row label (time-rail layouts).
    if (!pending.isComplete && pending.hasSubject && rowTime != null) {
      pending.time = rowTime;
    }
    flush();
    return rows;
  }

  // -- emission -------------------------------------------------------------
  static List<SectionedRow> _emit(
    _PendingCell cell,
    int activeDay,
    List<int> slotDays,
    int slotIndex,
    String rowProfessor,
    bool calendarMode,
    List<int> activeDays,
  ) {
    final assumptions = <String>[];
    List<int> rowDays;
    if (cell.day != 0) {
      rowDays = [cell.day];
    } else if (slotDays.isNotEmpty) {
      rowDays = [slotDays[slotIndex % slotDays.length]];
      assumptions.add('Day taken from the column order in the layout');
    } else if (cell.bothDays && activeDays.length > 1) {
      rowDays = activeDays;
      assumptions.add('Expanded for every day of the multi-day header');
    } else if (activeDay != 0) {
      rowDays = [activeDay];
    } else if (activeDays.isNotEmpty) {
      rowDays = [activeDays.last];
      assumptions.add('Day taken from a multi-day header');
    } else {
      rowDays = [1];
      assumptions.add('No day column was found; defaulted to Monday');
    }
    if (cell.examRecord) {
      assumptions.add('Imported from an examination-style timetable');
    }
    if (calendarMode && cell.calendarDate) {
      assumptions.add('Calendar date mapped to a weekday by grid position');
    }
    var end = cell.time!.end;
    if (cell.time!.single) {
      end = cell.time!.start + 60;
      assumptions.add('Only a start time was printed; end assumed 1 hour');
    }
    var professor = cell.professor;
    if (professor.isEmpty && rowProfessor.isNotEmpty) {
      professor = rowProfessor;
      assumptions.add('Professor taken from the row label');
    }
    return [
      for (final day in rowDays)
        SectionedRow(
          subject: cell.subject,
          day: day,
          startMinutes: cell.time!.start,
          endMinutes: end,
          room: cell.room.isEmpty ? 'Room to confirm' : cell.room,
          professor: professor.isEmpty ? unspecifiedProfessor : professor,
          ocrConfidence: assumptions.isEmpty ? null : 0.74,
          assumptions: List.of(assumptions),
        ),
    ];
  }

  /// A fragment whose only surviving subject word is a bare preposition is a
  /// room-only continuation ("in the IT Lab", "in Studio 2."), not a class
  /// name. Used when the cell already has its subject from a previous line.
  static const Set<String> _trailingPrepositionOnly = {
    'in', 'at', 'on', 'for', 'of', 'to', 'and', 'with', 'the', 'by',
  };

  // -- helpers ----------------------------------------------------------------
  /// "Prof. R. DeJesus" alone on a line (faculty row label).
  static String? _standaloneTitledProfessor(String line) {
    final m = RegExp(
      r'^(?:prof(?:essor)?|instr(?:uctor)?|dr|mr|ms|mrs)\.?:?\s+'
      r'((?:[A-Z]\.?|[A-Z][a-z]+|[A-Z]{2,})'
      r'(?:\s+(?:[A-Z]\.?|[A-Z][a-z]+|[A-Z]{2,})){0,3})\s*[.,]*$',
      caseSensitive: false,
    ).firstMatch(line);
    return m?.group(1)?.trim();
  }

  /// Weekday inside an exam date line; null when the line is not a date.
  /// A date without any weekday yields Monday (flagged by the caller).
  static int? _examDateWeekday(String line) {
    if (!_monthDate.hasMatch(line)) return null;
    if (_TimeInfo.containsRange(line)) return null;
    final weekday = _inlineWeekday.firstMatch(line);
    if (weekday == null) return 1;
    return _dayOf(weekday.group(0)!) ?? 1;
  }

  /// Pulls an inline weekday ("Mon 09:00 ...") into the pending cell before
  /// the fragment is split into fields, so self-contained list lines keep
  /// their day. Returns the weekday (1-7) when the fragment names one.
  static int? _absorbInlineDay(_PendingCell pending, String fragment) {
    final weekday = _inlineWeekday.firstMatch(fragment);
    if (weekday == null) return null;
    final day = _dayOf(weekday.group(0)!) ?? 0;
    if (day != 0 && pending.day == 0) pending.day = day;
    return day == 0 ? null : day;
  }

  static void _absorbDetails(
    _PendingCell pending,
    ScheduleTextDetails details,
  ) {
    if (details.subject.isNotEmpty) pending.subject = details.subject;
    if (details.room != 'Room to confirm') pending.room = details.room;
    if (details.professor != unspecifiedProfessor) {
      pending.professor = details.professor;
    }
  }

  static void _absorbFields(_PendingCell pending, String fragment) {
    var details = ScheduleTextDetails.parse(fragment);
    if (!pending.hasSubject &&
        details.subject.isEmpty &&
        fragment.trim().length >= 2) {
      // "_absorbFields" only ever sees the text left after a time range was
      // removed ("Library" from "Library 11-12"). When that remainder is
      // nothing but a venue token, the venue names the class - without this
      // rescue the entry silently disappears.
      //
      // The rescue must not run when the cell already carries its subject:
      // there the remainder is the cell's room ("11:00 Room 5" under a
      // "Calculus II" line), and re-labelling it would rename the class and
      // throw the room away.
      final fallback = ScheduleTextDetails.sanitizeSubject(fragment);
      if (fallback.isNotEmpty) {
        details = ScheduleTextDetails(
          subject: fallback,
          room: '',
          professor: '',
        );
      }
    } else if (pending.hasSubject &&
        details.subject.isNotEmpty &&
        _trailingPrepositionOnly.contains(details.subject)) {
      // A room-only continuation ("in the IT Lab", "in Studio 2.") reached
      // here after a time range was removed; the cell already has its subject
      // from the previous line, so the bare preposition is not a class name -
      // taking it as one would rename the class ("in") and lose the room.
      details = ScheduleTextDetails(
        subject: '',
        room: details.room,
        professor: details.professor,
      );
    }
    _absorbDetails(pending, details);
  }
}

class _PendingCell {
  String subject = '';
  _TimeInfo? time;
  String room = '';
  String professor = '';
  int day = 0;
  bool calendarDate = false;
  bool examRecord = false;
  bool bothDays = false;
  int lineCount = 0;

  bool get hasSubject => subject.isNotEmpty;
  bool get isComplete => subject.isNotEmpty && time != null;

  void clear() {
    subject = '';
    time = null;
    room = '';
    professor = '';
    day = 0;
    calendarDate = false;
    examRecord = false;
    bothDays = false;
    lineCount = 0;
  }
}

class _TimeInfo {
  _TimeInfo._(this.start, this.end, this.single);

  final int start;
  final int end;
  final bool single;

  static final RegExp _rangeInLine = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*([AP]\.?M\.?)?\s*(?:-|–|—|to)\s*'
    r'(\d{1,2})(?::(\d{2}))?\s*([AP]\.?M\.?)?'
    r'|(?:(?<!\d)(\d{3,4})\s*(?:-|–|—|to)\s*(\d{3,4})(?!\d))',
    caseSensitive: false,
  );
  static final RegExp _singleMidline = RegExp(
    r'(?<!\d)(\d{1,2}):(\d{2})\s*([AP]\.?M\.?)?(?!\d)',
    caseSensitive: false,
  );

  static bool containsRange(String line) => _rangeInLine.hasMatch(line);

  /// Extracts the first time expression in [line]. A lone clock on the
  /// whole line ("7:00") becomes a single (rail tick) time; a single clock
  /// with other content ("Mon 09:00 Art History...") is a real start time.
  static _TimeInfo? extract(String line) {
    final m = _rangeInLine.firstMatch(line);
    if (m != null) {
      int? s, e;
      if (m.group(1) != null) {
        s = _minutes(m.group(1)!, m.group(2), m.group(3));
        // An end without its own meridiem inherits the start's ("9:30 PM - 11:00").
        e = _minutes(m.group(4)!, m.group(5), m.group(6) ?? m.group(3) ?? '');
        // "1-3pm" / "1:00-2:30 PM": the bare start belongs to the afternoon
        // too when the end is explicitly PM and the shift stays forward.
        final endMeridiem = (m.group(6) ?? '').toUpperCase();
        if (s != null &&
            e != null &&
            m.group(3) == null &&
            endMeridiem.contains('PM') &&
            s + 720 < e) {
          s += 720;
        }
      } else if (m.group(7) != null && m.group(8) != null) {
        s = _military(m.group(7)!);
        e = _military(m.group(8)!);
      }
      // A span below 15 minutes is noise, not a class - the year range
      // "2025-2026" parses as the one-minute pair 20:25-20:26, for example.
      // Spans beyond 8 hours are unlikely classes; a school day with an
      // "Art workshop 4-11" page-long block still fits inside 8.
      if (s != null && e != null && e > s && e - s >= 15 && e - s <= 8 * 60) {
        return _TimeInfo._(s, e, false);
      }
    }
    final single = _singleMidline.firstMatch(line);
    if (single != null) {
      final s = _minutes(
        single.group(1)!,
        single.group(2),
        single.group(3) ?? '',
      );
      if (s != null) return _TimeInfo._(s, s + 60, true);
    }
    return null;
  }

  String remainderOf(String line) {
    var rest = line;
    final range = _rangeInLine.firstMatch(rest);
    if (range != null) {
      rest = rest.replaceRange(range.start, range.end, ' ');
    } else {
      final s = _singleMidline.firstMatch(rest);
      if (s != null) rest = rest.replaceRange(s.start, s.end, ' ');
    }
    return rest.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static int? _minutes(String hourText, String? minuteText, String? meridiem) {
    final hour = int.tryParse(hourText);
    if (hour == null) return null;
    final minute = minuteText == null ? 0 : int.tryParse(minuteText) ?? 0;
    if (minute > 59) return null;
    var h = hour;
    final m = meridiem?.toUpperCase() ?? '';
    if (m.contains('PM')) {
      if (hour < 1 || hour > 12) return null;
      h = hour % 12 + 12;
    } else if (m.contains('AM')) {
      if (hour < 1 || hour > 12) return null;
      h = hour % 12;
    } else if (hour > 23) {
      return null;
    }
    return h * 60 + minute;
  }

  static int? _military(String text) {
    final digits = text.padLeft(4, '0');
    final hour = int.tryParse(digits.substring(0, 2));
    final minute = int.tryParse(digits.substring(2));
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }
}
