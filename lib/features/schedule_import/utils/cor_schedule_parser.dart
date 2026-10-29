import 'sectioned_schedule_parser.dart';

/// Reads a Certificate of Registration (COR): one enrolled subject per row,
/// with its printed schedule in a "hh:mm AM - hh:mm PM / Day" cell, followed
/// by room and faculty cells.
///
/// Expected row shape, after OCR (columns may be separated by spaces):
///
///   IT 104 Data Structures and Algorithm 3 BSIT-2A 08:00 AM - 09:30 AM / Mon Rm 301 Prof. Ana Reyes
///
/// Rules:
///  * the code is the first token group (IT 104, IT 104L, GE C03, PE 03,
///    IT Elec2, IT FE1); the description runs until the units digit;
///  * a row with a time cell but no code is a continuation of the subject
///    above it (a second meeting of the same subject). It is emitted with the
///    carried subject and flagged for review;
///  * rows without a time cell are enrolled subjects with no printed
///    schedule (a blank-schedule COR). They emit no class, because a class
///    needs a day and a time;
///  * "tba" and "Online" cells are ignored, and the Faculty and Room cells
///    are split at the first faculty title (Prof., Coach, Dr., Engr.).
class CorScheduleParser {
  CorScheduleParser._();

  static const double _continuationConfidence = 0.74;

  /// The schedule cell. Tolerant of the slips OCR makes on photographed
  /// forms: a space after the colon (`09: 30`), a dropped colon (`05 00 PM`),
  /// a dot for the colon, and missing spaces around the slash (`PM/Fri`).
  static final RegExp _slot = RegExp(
    r'(\d{1,2})\s?[:.]?\s?(\d{2})\s*(AM|PM)\s*[-–—]\s*(\d{1,2})\s?[:.]?\s?(\d{2})\s*(AM|PM)\s*/\s*([A-Za-z]{3,9})',
    caseSensitive: false,
  );

  static final RegExp _formTitle = RegExp(
    r'certificate\s+of\s+registration',
    caseSensitive: false,
  );

  static final RegExp _columnHeaders = RegExp(
    r'\bunits?\b[\s\S]*\bfaculty\b|\bfaculty\b[\s\S]*\bunits?\b',
    caseSensitive: false,
  );

  static final RegExp _facultyStart = RegExp(
    r'\b(Prof\.?|Professor|Coach|Dr\.?|Engr\.?|Mr\.?|Ms\.?|Mrs\.?|Sir)\s',
    caseSensitive: false,
  );

  static final RegExp _codeAndDescription = RegExp(
    r'^((?:[A-Za-z]{1,4}\s)?[A-Za-z]{1,4}\s?\d{1,3}[A-Za-z]{0,2}\d?)\s+(\S.*)$',
  );

  static final RegExp _trailingUnits = RegExp(r'\s(\d)\s*$');
  static final RegExp _trailingSection = RegExp(
    r'\s+(?:BS[A-Za-z]*-?\s?\d[A-Za-z]?|[A-Za-z]{2,5}-\d[A-Za-z]?)\s*$',
    caseSensitive: false,
  );
  static final RegExp _roomCell = RegExp(
    r'\b(?:(?:Rm|Room)\.?\s*[\w-]+|Mac\s?Lab|Lab(?:oratory)?\s?\d*|Gym)\b',
    caseSensitive: false,
  );

  /// Column vocabulary shared by every COR layout: room, faculty, units,
  /// section and programme tokens. Skewed or soft photos garble the printed
  /// form title, so this vocabulary is the fallback COR signature.
  static final RegExp _corVocabulary = RegExp(
    r'\b(?:Rm|Room|Prof\.?|Professor|Faculty|Units?|Section|Registrar)\b',
    caseSensitive: false,
  );

  /// Table separators and underline filler the OCR text joiner and the
  /// scanner leave inside a row: `IT 201 | Data Structures | 3 | BSIT-2A _`.
  static final RegExp _cellNoise = RegExp(r'[|\[_\]]');
  static final RegExp _tbaCell = RegExp(
    r'\b(tba|online)\b',
    caseSensitive: false,
  );

  /// Whether [text] looks like a COR: the printed form title appears, or a
  /// schedule cell appears together with the Units and Faculty column
  /// headers. Photographed forms often garble both title and headers, so two
  /// or more COR-shaped schedule cells (`hh:mm AM - hh:mm PM / Day`) beside
  /// the COR column vocabulary also identify the form. Ordinary timetables
  /// with a "Time / Day" or "Room" header do not match (their times never
  /// carry the `/ Day` cell), so they keep their existing parser.
  static bool looksLikeCor(String text) {
    if (_formTitle.hasMatch(text)) return true;
    if (_slot.hasMatch(text) && _columnHeaders.hasMatch(text)) return true;
    return _slot.allMatches(text).length >= 2 &&
        _corVocabulary.allMatches(text).length >= 2;
  }

  /// Parses COR rows from OCR or extracted text, one row per line.
  static List<SectionedRow> parse(String raw) {
    final lines = raw
        .replaceAll('\r', '\n')
        .split('\n')
        .map(_cleanLine)
        .where((line) => line.isNotEmpty);

    final rows = <SectionedRow>[];
    String? carriedSubject;
    String? carriedCode;

    // A photographed COR read at a slight angle often loses its narrow Code
    // column while the wide Subject column survives, and a row's subject and
    // time cells can land on separate banded lines. When at least one
    // schedule cell has been seen the parser is inside the table, so a
    // subject-shaped line is stashed and attached to the next schedule cell.
    var insideTable = false;

    for (final line in lines) {
      final slot = _slot.firstMatch(line);

      if (slot == null) {
        if (!insideTable) continue;
        // A no-slot line inside the table is either a subject waiting for
        // its time cell (banded rows split it) or a room/faculty fragment
        // of the row being assembled. Only a subject-shaped residue after
        // the room and faculty spans are removed is stashed.
        final body = _subjectResidue(line);
        if (body != null) {
          carriedSubject = body;
          carriedCode = null;
        }
        continue;
      }
      insideTable = true;

      final day = _dayNumber(slot.group(7)!);
      if (day == null) continue;
      final start = _minutes(slot.group(1)!, slot.group(2)!, slot.group(3)!);
      final end = _minutes(slot.group(4)!, slot.group(5)!, slot.group(6)!);
      if (end <= start) continue;

      final before = line.substring(0, slot.start).trim();
      final after = line.substring(slot.end).trim();

      final parsedHead = _parseHead(before);
      final ownSubject = parsedHead == null ? _subjectBody(before) : null;
      final String subject;
      final List<String> assumptions;
      final double? confidence;
      if (parsedHead != null) {
        subject = parsedHead.description;
        carriedSubject = subject;
        carriedCode = parsedHead.code;
        assumptions = const [];
        confidence = null;
      } else if (ownSubject != null) {
        // A subject with no readable code: skewed or soft photos lose the
        // narrow code column while the description survives. The row's own
        // description always wins over the carried one - only a line with
        // no subject text of its own continues the row above it.
        subject = ownSubject;
        carriedSubject = subject;
        carriedCode = null;
        assumptions = [
          'No subject code was recognized; the subject was read from the row.',
        ];
        confidence = _continuationConfidence;
      } else if (carriedSubject != null) {
        subject = carriedSubject;
        assumptions = [
          carriedCode == null
              ? 'Read as the subject above; the Code column was not recognized.'
              : 'Second meeting of $carriedCode, read from the row above.',
        ];
        confidence = _continuationConfidence;
      } else {
        continue;
      }

      final cells = _splitRoomAndFaculty(after);
      rows.add(
        SectionedRow(
          subject: subject,
          day: day,
          startMinutes: start,
          endMinutes: end,
          room: cells.room,
          professor: cells.professor,
          ocrConfidence: confidence,
          assumptions: assumptions,
        ),
      );
    }
    return rows;
  }

  /// The subject phrase in a head or body line that carries no code: the
  /// whole text, when it reads like a description (at least two alphabetic
  /// tokens) and does not end on a column-header word. Column-header
  /// fragments (`ect Description`), room and faculty cells, and numeric
  /// junk all fail this test, so they are never mistaken for a subject.
  static String? _subjectBody(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final tokens = trimmed.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.length < 2) return null;
    final last = tokens.last.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (_headerWords.contains(last)) return null;
    final alphaTokens = tokens
        .where((token) => RegExp(r'^[A-Za-z]').hasMatch(token))
        .length;
    if (alphaTokens < 2) return null;
    return trimmed;
  }

  /// [_subjectBody] over a no-slot line with its room and faculty cells
  /// removed, so a banded line like `PATHAit 3 - Dance Prof. Ana Reyes
  /// Rm 301` stashes only the subject. The faculty cell runs from its title
  /// to the end of the line; a pure room or faculty fragment leaves no
  /// subject-shaped residue and stashes nothing.
  static String? _subjectResidue(String line) {
    final faculty = _facultyStart.firstMatch(line);
    if (faculty != null) {
      return _subjectBody(line.substring(0, faculty.start));
    }
    final room = _roomCell.firstMatch(line);
    if (room != null) {
      return _subjectBody(line.replaceRange(room.start, room.end, ' '));
    }
    return _subjectBody(line);
  }

  static const Set<String> _headerWords = {
    'code',
    'description',
    'subject',
    'units',
    'unit',
    'section',
    'time',
    'day',
    'room',
    'faculty',
    'online',
    'enrolled',
  };

  /// One OCR text line with the table filler removed: cell separators
  /// (` | `), underline runs (`BSIT-2A _`) and stray bracket borders. A COR
  /// code, subject, room or faculty name never contains these characters, so
  /// collapsing them to spaces only ever removes noise.
  static String _cleanLine(String line) => line
      .replaceAll(_cellNoise, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Splits the text before the schedule cell into code, description and
  /// units. Returns null when no code is present (a continuation line).
  static ({String code, String description})? _parseHead(String before) {
    var head = before.replaceFirst(_trailingSection, '').trim();
    head = head.replaceFirst(_trailingUnits, '').trim();
    var match = _codeAndDescription.firstMatch(head);
    if (match == null) {
      // Letter/digit slips inside the code token: a trailing O read for 0
      // (`PEO?` for `PE 03`) or a trailing L read for 1 (`IT FEL` for
      // `IT FE1`). Retry once with the fixups applied; the description side
      // of the row never reaches this branch because it carries no code.
      final fixed = _fixCodeSlips(head);
      if (fixed != head) match = _codeAndDescription.firstMatch(fixed);
      if (match == null) return null;
    }
    final code = match.group(1)!.trim();
    final description = match.group(2)!.trim();
    if (description.isEmpty) return null;
    return (code: code, description: description);
  }

  /// Conservative code-token fixups, applied only when the head otherwise
  /// has no code at all: strip trailing `? ! .` noise from the first token,
  /// map a trailing O to 0 inside that token, and a trailing L to 1 inside a
  /// second token that is otherwise all caps. Real words (`Intro`, `Lab`)
  /// never sit in the code position of a COR head, and the fixups only fire
  /// when the plain parse already failed.
  static String _fixCodeSlips(String head) {
    final tokens = head.split(' ');
    if (tokens.isEmpty) return head;
    var first = tokens.first.replaceAll(RegExp(r'[?!._]+$'), '');
    if (first.length >= 2 && first.endsWith('O')) {
      first = '${first.substring(0, first.length - 1)}0';
    }
    tokens[0] = first;
    if (tokens.length >= 2) {
      final second = tokens[1];
      if (second.length >= 2 &&
          second.endsWith('L') &&
          RegExp(r'^[A-Z]{2,}$').hasMatch(second)) {
        tokens[1] = '${second.substring(0, second.length - 1)}1';
      }
    }
    return tokens.join(' ');
  }

  /// The room and faculty cells can come in either order, so the room token
  /// is found first and the rest of the text is the faculty name.
  static ({String room, String professor}) _splitRoomAndFaculty(String after) {
    final cleaned = after
        .replaceAll(_tbaCell, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final roomMatch = _roomCell.firstMatch(cleaned);
    final room = roomMatch == null ? '' : _formatRoom(roomMatch.group(0)!);
    final rest = roomMatch == null
        ? cleaned
        : cleaned.replaceRange(roomMatch.start, roomMatch.end, '').trim();
    final faculty = _facultyStart.firstMatch(rest);
    final professor = faculty == null ? rest : rest.substring(faculty.start);
    return (room: room, professor: professor.trim());
  }

  /// Canonical room labels: OCR merges the space in `Lab 2` (`lab2`) and
  /// lowercases `MacLab`; both display and review read better normalized.
  static String _formatRoom(String raw) {
    final trimmed = raw.trim();
    final merged = RegExp(r'^lab(\d+)$', caseSensitive: false).firstMatch(
      trimmed,
    );
    if (merged != null) return 'Lab ${merged.group(1)}';
    if (trimmed.toLowerCase() == 'maclab') return 'MacLab';
    return trimmed;
  }

  static int _minutes(String hour, String minute, String meridiem) {
    var h = int.parse(hour) % 12;
    if (meridiem.toUpperCase() == 'PM') h += 12;
    return h * 60 + int.parse(minute);
  }

  /// Weekday 1..7 (Monday = 1), matching the app's day convention. An exact
  /// three-letter prefix wins; photographed cells read days with one
  /// character off (`Tuo` for Tue, `Wen` for Wed, `Fir` for Fri), so a
  /// unique single-edit match is accepted too. Ambiguous or longer slips
  /// stay unparsed rather than guessed.
  static int? _dayNumber(String word) {
    final key = word.toLowerCase().trim();
    if (key.length < 3) return null;
    final prefix = key.substring(0, 3);
    const days = {
      'mon': 1,
      'tue': 2,
      'wed': 3,
      'thu': 4,
      'fri': 5,
      'sat': 6,
      'sun': 7,
    };
    final exact = days[prefix];
    if (exact != null) return exact;
    int? best;
    var bestDistance = 2;
    var tied = false;
    for (final entry in days.entries) {
      final distance = _editDistance(prefix, entry.key);
      if (distance > 1) continue;
      if (distance == bestDistance) {
        tied = true;
      } else if (distance < bestDistance) {
        bestDistance = distance;
        best = entry.value;
        tied = false;
      }
    }
    return tied ? null : best;
  }

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    var distance = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) distance++;
    }
    return distance + (a.length - b.length).abs();
  }
}
