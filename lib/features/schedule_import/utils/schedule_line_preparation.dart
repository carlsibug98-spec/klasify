/// Line preparation for non-timetable schedule text.
///
/// Photos (planners, chat screenshots, emails, notice boards) are written so
/// that one logical row often spans several printed lines, and one printed
/// line often carries two classes. The parsers below this layer assume "one
/// complete cell per line", so raw OCR text is reshaped first:
///
///  * WRAPPED CONTINUATIONS are rejoined:
///      - a line ending in " /" (an open multi-class marker),
///      - a line ending in an open time range ("Computer 10:00-"),
///      - a short tail (room / professor) after a trailing preposition
///        ("... 10:30-12:00 in" + "Lab 3.").
///  * MULTI-CLASS LINES are split into one line per class: a " / " separator
///    and an "and"/"&" connector between two time ranges become row
///    boundaries. Segments without a day inherit the parent line's day
///    prefix ("Fri - PE ... / Computer" -> "Fri - Computer ...").
///
/// The reshaping stays mechanical (split/join only), so no layout assumption
/// of a specific grid format is invented here; semantic cleanup belongs to
/// the parsers, which also run on text that never passes through this step.
library;

/// A time range anywhere in a line ("8:00-9:30", "1:00 PM-2:30 PM", "1-3pm").
final RegExp _timeRange = RegExp(
  r'\d{1,2}(?::\d{2})?\s*(?:[AP]\.?M\.?)?\s*(?:-|–|—|to)\s*'
  r'\d{1,2}(?::\d{2})?\s*(?:[AP]\.?M\.?)?',
  caseSensitive: false,
);

/// A dangling open range at the end of a line ("Computer 10:00-",
/// "1:00 PM-").
final RegExp _trailingOpenRange = RegExp(
  r'\d{1,2}(?::\d{2})?\s*(?:[AP]\.?M\.?)?\s*(?:-|–|—)\s*$',
  caseSensitive: false,
);

/// Trailing prepositions that invite a short-tail continuation.
const Set<String> _trailingPrepositions = {
  'in', 'at', 'for', 'of', 'on', 'to', 'and', 'with', 'the',
};

/// "Mon - ", "Monday: ", "Tue –" — a line-leading day prefix that a segment
/// of the same multi-class line can inherit.
final RegExp _dayPrefix = RegExp(
  r'^(?:mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday|s)?|thu(?:rsday)?|thur?s?|'
  r'fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b\s*(?:-|–|—|:)?\s*',
  caseSensitive: false,
);

bool _hasDayPrefix(String line) => _dayPrefix.firstMatch(line) != null;

bool _hasTimeRange(String line) => _timeRange.firstMatch(line) != null;

/// A bare subject fragment left by a room-and-subject split ("Art at", "and
/// Geometry") carries no time of its own and is the tail of the previous
/// class's sentence; it joins the next line, which carries its range. A
/// fragment is only a tail when it holds a preposition - a two-word
/// capitalized line ("Academic Writing", "Ms. Santos") or a title
/// ("GRADE 8 - SCHEDULE") starts its own row, and stacked layouts (calendar
/// grids, period rows, hour rails) print one token per line.
bool _isBareSubjectFragment(String line) {
  final words = line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || words.length > 4) return false;
  if (_hasTimeRange(line)) return false;
  if (_roomTail.hasMatch(line)) return false;
  if (_dayPrefix.hasMatch(line)) return false;
  final lower = words.map((w) => w.toLowerCase()).toSet();
  return lower.any(_trailingPrepositions.contains);
}

bool _endsWithRoomTail(String line) =>
    _roomTail.firstMatch(line)?.end == line.length;

bool _endsWithPreposition(String line) {
  final match = RegExp(r'[A-Za-z]+\s*$').firstMatch(line);
  if (match == null) return false;
  return _trailingPrepositions.contains(match.group(0)!.trim().toLowerCase());
}

/// True when [next] is the continuation of [prev], not a new row.
bool _shouldJoin(String prev, String next) {
  // A bare subject fragment ("Art at", "and Geometry") left by a
  // room-and-subject split carries no time of its own and is the tail of the
  // previous class's sentence; it joins the next line, which carries its
  // range. Runs before the multi-range split so the joined line can be split
  // again if it now holds two ranges.
  if (_isBareSubjectFragment(prev)) return true;

  // A day-anchored line always opens its own row.
  if (_hasDayPrefix(next)) return false;
  if (prev.endsWith('/')) return true;
  if (_trailingOpenRange.hasMatch(prev)) return true;
  // A room/professor tail riding on a trailing preposition ("... in" and a
  // short "Lab 3."). Longer lines start something of their own. A line that
  // merely STARTS with a range never joins here: stacked layouts (time
  // rails, calendar dates) print standalone range labels, and the parser
  // completes a subject-only pending cell from such a line itself.
  if (_endsWithPreposition(prev)) {
    if (next.split(' ').length <= 3) return true;
  }
  // A bare subject fragment after a room tail ("... in the IT Lab" + "Art at")
  // is the next class's sentence head, not a new row.
  final endsRoom = _endsWithRoomTail(prev);
  final bareNext = _isBareSubjectFragment(next);
  if (endsRoom && bareNext) return true;
  return false;
}

/// " and " / " & " parses as a connector only between two ranges, so the
/// "and" inside a subject ("Math and Science 8-9") never splits it.
final RegExp _rangeConnector = RegExp(r'\s+(?:and|&)\s+', caseSensitive: false);

/// One OCR line can carry the tail of a sentence and the head of the next
/// ("Lab 3. Tuesday has English at 9:00-10:30"). A period followed by a
/// piece that holds a digit marks such a boundary; the tail piece ("Lab 3")
/// then fuses with the line above, and the head opens its own row.
final RegExp _sentenceBoundaryRegExp = RegExp(r'\.\s+');

/// True when the period between [before] and [after] ends a sentence rather
/// than belonging to an abbreviation ("P.E.", "J. Sarmiento"). A digit before
/// the period ("Lab 3.") or a lowercase-ending word followed by a capitalized
/// start ("ends. Next") are sentence ends; a single capital letter ("E.") or
/// a capitalized word ("Prof. Santos") is a name/initial, not a boundary.
bool _isSentenceBoundary(String before, String after) {
  final beforeTrimmed = before.trim();
  if (beforeTrimmed.isEmpty || after.isEmpty) return false;
  final lastChar = beforeTrimmed[beforeTrimmed.length - 1];
  if (RegExp(r'\d').hasMatch(lastChar)) return true;
  final lastWord = RegExp(r'([A-Za-z]+)$').firstMatch(beforeTrimmed);
  if (lastWord != null &&
      RegExp(r'[a-z]').hasMatch(lastWord.group(1)!) &&
      RegExp(r'[A-Z]').hasMatch(after[0])) {
    return true;
  }
  return false;
}

List<String> _splitSentenceBoundary(String line) {
  final pieces = line.split(_sentenceBoundaryRegExp);
  if (pieces.length < 2) return [line];
  final lines = <String>[];
  var current = pieces[0];
  for (var i = 1; i < pieces.length; i++) {
    final piece = pieces[i];
    if (RegExp(r'\d').hasMatch(piece) && _isSentenceBoundary(current, piece)) {
      lines.add(current);
      current = piece;
    } else {
      // Restore the single boundary period this split consumed; pieces
      // without digits are mid-sentence fragments, not row starts, and a
      // period glued to an initial ("P.E.", "J. Smith") is not a boundary.
      current = '$current. $piece';
    }
  }
  lines.add(current);
  return lines;
}

/// Splits [line] at connectors that sit between two time ranges so every
/// range starts its own line.
List<String> _splitMultiRange(String line) {
  final ranges = _timeRange.allMatches(line).toList();
  if (ranges.length < 2) return [line];
  final first = ranges.first;
  for (final match in ranges.skip(1)) {
    final between = line.substring(first.end, match.start);
    final connectorBetween = _rangeConnector.allMatches(between).lastOrNull;
    if (connectorBetween == null) continue;
    final splitter = first.end + connectorBetween.start;
    return [
      line.substring(0, splitter).trim(),
      ..._splitMultiRange(line.substring(first.end + connectorBetween.end).trim()),
    ];
  }
  return [line];
}

/// Venue tokens that end a cell: the room of the class just listed.
final RegExp _roomTail = RegExp(
  r'\b(?:Room|Rm\.?|Lab|Laboratory|IT\s+Lab|Computer\s+Lab|Gym|Library|'
  r'Auditorium|Cafeteria|Main\s+Hall|Hall\b|Studio\s+\d{1,3}|NetLab|MacLab)'
  r'\s*$',
  caseSensitive: false,
);

/// The same venue tokens without the end-of-line anchor, used to find a room
/// that is followed by the next class's sentence head ("... in the IT Lab
/// Art at"). A room token at the very end of the line is the current cell's
/// room and is never a split point.
final RegExp _roomToken = RegExp(
  r'\b(?:Room|Rm\.?|Lab|Laboratory|IT\s+Lab|Computer\s+Lab|Gym|Library|'
  r'Auditorium|Cafeteria|Main\s+Hall|Hall\b|Studio\s+\d{1,3}|NetLab|MacLab)\b',
  caseSensitive: false,
);

/// A capitalized subject word, not a room token and not a weekday.
final RegExp _subjectStart = RegExp(
  r'^[A-Z][A-Za-z]{1,}',
);

/// A prose connector ("and Art at", "& Art at") that sits between a room and
/// the next class name. Unlike [_rangeConnector] this fires even when only one
/// range is on the line, because the second class's range is on the next line
/// ("Friday wraps up with Computer 10:00- 11:30 in the IT Lab and Art at").
final RegExp _roomAndSubjectConnector = RegExp(
  r'\s+(?:and|&)\s+',
  caseSensitive: false,
);

List<String> _splitRoomAndSubject(String line) {
  // 1. A connector ("and"/"&") sitting right after a room tail.
  for (final match in _roomAndSubjectConnector.allMatches(line)) {
    final before = line.substring(0, match.start).trim();
    final after = line.substring(match.end).trim();
    if (_roomTail.hasMatch(before) &&
        _subjectStart.hasMatch(after) &&
        !_roomTail.hasMatch(after)) {
      return [before, ..._splitRoomAndSubject(after)];
    }
  }
  // 2. A room token directly followed by a capitalized subject word with no
  //    connector ("... in the IT Lab Art at"). A room token at the very end of
  //    the line is the current cell's room and is never a split point.
  final room = _roomToken.firstMatch(line);
  if (room != null && room.end < line.length) {
    final afterRoom = line.substring(room.end).trim();
    if (afterRoom.isNotEmpty &&
        _subjectStart.hasMatch(afterRoom) &&
        !_roomTail.hasMatch(afterRoom)) {
      return [
        line.substring(0, room.end).trim(),
        ..._splitRoomAndSubject(afterRoom),
      ];
    }
  }
  return [line];
}

/// " / " multi-class separators ("Math 8-9 Room 5 / Science 10:30-12:00").
final RegExp _slashSeparator = RegExp(r'\s/\s');

/// Reshapes raw text into one complete-cell line per schedule row.
List<String> prepareScheduleLines(String raw) {
  final lines = raw
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();

  // 0. Boundaries of printed sentences that share one OCR line.
  final split = <String>[];
  for (final line in lines) {
    split.addAll(_splitSentenceBoundary(line));
  }

  // 0.5. A prose connector ("... in the IT Lab and Art at") between a room and
  //    the next class name marks a row boundary even when the second class's
  //    range is on the next line. Without this the trailing class fuses into
  //    the previous cell ("Computer" absorbs "Art at"). Runs before the join
  //    step so the bare fragment is a separate line that can join its range.
  final roomSplit = <String>[];
  for (final line in split) {
    roomSplit.addAll(_splitRoomAndSubject(line));
  }

  // 1. Join wrapped continuations; the loop re-evaluates the grown last line,
  //    so chains ("10:00-" + "11:30 ... and Art at" + "1:00 PM-...") fuse.
  //    A bare subject fragment ("Art at") left by a room split carries no
  //    time of its own and is the tail of the previous class's sentence; it
  //    joins the next line, which carries its range.
  final merged = <String>[];
  for (final line in roomSplit) {
    if (merged.isNotEmpty && _shouldJoin(merged.last, line)) {
      merged[merged.length - 1] = '${merged.last} $line';
    } else {
      merged.add(line);
    }
  }

  // 1.5. Re-run the room-and-subject split on the grown lines: joining a
  //    bare fragment can glue two classes back together ("... in the IT Lab
  //    Art at 1:00 PM-2:00 PM in Studio 2.") and the connector is now inside
  //    one line again.
  final roomSplit2 = <String>[];
  for (final line in merged) {
    roomSplit2.addAll(_splitRoomAndSubject(line));
  }

  // 2. One range per line.
  final ranged = <String>[];
  for (final line in roomSplit2) {
    ranged.addAll(_splitMultiRange(line));
  }

  // 3. Break " / " lines into single rows; day-less segments inherit the
  //    parent line's day prefix.
  final prepared = <String>[];
  for (final line in roomSplit2) {
    final parts = line.split(_slashSeparator);
    if (parts.length == 1) {
      prepared.add(line);
      continue;
    }
    final head = parts.first.trim();
    final match = _dayPrefix.firstMatch(head);
    final prefix = match == null ? '' : head.substring(0, match.end);
    prepared.add(head);
    for (final rawPart in parts.skip(1)) {
      final segment = rawPart.trim();
      if (segment.isEmpty) continue;
      prepared.add(
        _hasDayPrefix(segment) ? segment : '$prefix$segment',
      );
    }
  }
  return prepared;
}
