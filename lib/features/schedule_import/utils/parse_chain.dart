import 'sectioned_schedule_parser.dart';
import 'schedule_line_preparation.dart';
import 'timetable_parser.dart';

/// Shared parser-chain entry point and quality chooser.
///
/// The review screen and the OCR service both need to turn raw text into rows,
/// and both need to decide which of several OCR candidates is best. This module
/// owns that decision so the two paths cannot drift.
///
/// The chain is layout-aware first: `SectionedScheduleParser` reads weekday
/// header bands, day sections, exam records, calendar dates, day-less blocks
/// and single-time lines. `prepareScheduleLines` is applied to the text before
/// the sectioned parser runs so wrapped prose lines, multi-class lines and
/// room-and-subject connectors are reshaped into one complete-cell line per
/// row. `TimetableParser` stays as the conservative second attempt and is
/// deliberately NOT given the reshaping step: its chat single-message list
/// parser yields fewer rows than the sectioned parser for the same input, and
/// giving it the reshaping too would change its behaviour mid-bench.
class ParseChain {
  ParseChain._();

  /// Runs the review-screen chain on [text]. Returns the parser that produced
  /// rows, or null when neither parser found anything.
  static ({List<SectionedRow> sectioned, List<ParsedTimetableRow> list, String used})
  parse(String text) {
    final prepared = prepareScheduleLines(text).join('\n');
    final sectioned = SectionedScheduleParser.parse(prepared);
    if (sectioned.isNotEmpty) {
      return (
        sectioned: sectioned,
        list: const <ParsedTimetableRow>[],
        used: 'sectioned',
      );
    }
    return (
      sectioned: const <SectionedRow>[],
      list: TimetableParser.parse(text),
      used: 'list',
    );
  }

  /// Sectioned rows only, with the shared line preparation applied. Used by
  /// callers that want the layout-aware parser without the list fallback.
  static List<SectionedRow> parseSectioned(String text) =>
      SectionedScheduleParser.parse(prepareScheduleLines(text).join('\n'));

  /// Scores a candidate OCR text for selection. The score rewards useful,
  /// distinct rows and penalises duplicated lines, so a confident but
  /// duplicated scan loses to a noisier one that parses more classes.
  static double score(String text, double meanConfidence) {
    final sectioned = SectionedScheduleParser.parse(
      prepareScheduleLines(text).join('\n'),
    );
    final list = TimetableParser.parse(text);
    final bestRowCount =
        sectioned.length > list.length ? sectioned.length : list.length;
    if (bestRowCount == 0) return meanConfidence * 5;

    final subjects = <String>{
      for (final row in sectioned)
        row.subject.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
      for (final row in list)
        row.subject.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
    }..removeWhere((subject) => subject.isEmpty);
    final slots = <String>{
      for (final row in sectioned)
        '${row.day}:${row.startMinutes}:${row.endMinutes}',
      for (final row in list)
        '${row.day}:${row.startMinutes}:${row.endMinutes}',
    };
    final repeatedLines = text
        .split('\n')
        .map(
          (line) => line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim(),
        )
        .where((line) => line.length > 3)
        .toList();
    final duplicatePenalty =
        repeatedLines.length - repeatedLines.toSet().length;
    final validTimePairs = RegExp(
      r'(?:\d{1,2}(?:[:.]\d{2})?|\d{4})\s*(?:am|pm)?\s*(?:-|–|—|to)\s*(?:\d{1,2}(?:[:.]\d{2})?|\d{4})',
      caseSensitive: false,
    ).allMatches(text).length;

    return (bestRowCount * 100.0 +
            subjects.length * 8.0 +
            slots.length * 4.0 +
            (validTimePairs < 20 ? validTimePairs : 20) * 1.5 +
            meanConfidence * 12.0 -
            duplicatePenalty * 12.0)
        .toDouble();
  }
}