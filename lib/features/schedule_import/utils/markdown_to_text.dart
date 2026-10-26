/// Converts a PaddleOCR-VL markdown document parse (HTML tables + headings +
/// paragraphs) into the plain reading-order line dump the timetable parsers
/// expect - the same shape a raw OCR pass produces:
///
///  * table cells keep their internal line breaks (`<br>`), so a cell
///    "Calculus II<br>Room 5<br>Prof. R. DeJesus" arrives as three lines;
///  * cells are emitted in row-major order, exactly the order a printed
///    timetable is read in;
///  * markdown decoration (emphasis, rule lines, heading hashes) is dropped
///    without touching the text content.
///
/// The sectioned parser then assigns days and times from that reading order,
/// the same way it does for on-device OCR output.
library;

/// Returns the converted text; empty lines removed, whitespace collapsed.
String markdownToText(String markdown) {
  var text = markdown;

  // 1. Table cells -> one line per cell (row-major order falls out of the
  //    document order). <br> inside cells becomes a line break first.
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAllMapped(
    RegExp(r'<t[dh][^>]*>([\s\S]*?)</t[dh]>', caseSensitive: false),
    (m) => '\n${m.group(1)!.trim()}\n',
  );

  // 2. Strip every remaining tag (tables, images, links keep their text).
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');

  // 3. Unescape the HTML entities VL output uses.
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  // 4. Drop markdown decoration that would end up as label debris.
  text = text.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
  final cleaned = <String>[];
  for (final rawLine in text.split('\n')) {
    var line = rawLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Horizontal rules and separator rows are decoration, not content.
    if (RegExp(r'^[-=_*]{3,}$').hasMatch(line)) continue;
    // Heading hashes carry no timetable meaning; keep the words.
    line = line.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    // Pipe-table borders keep their inner text but lose the edge pipes.
    line = line.replaceFirst(RegExp(r'^\|'), '').trim();
    line = line.replaceFirst(RegExp(r'\|$'), '').trim();
    if (line.isEmpty) continue;
    cleaned.add(line);
  }
  return cleaned.join('\n');
}
