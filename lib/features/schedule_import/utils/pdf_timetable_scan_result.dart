import 'parse_chain.dart';
import 'timetable_parser.dart';

class PdfPageScanResult {
  const PdfPageScanResult({
    required this.pageNumber,
    required this.gridRows,
    required this.fallbackText,
    required this.hasWeekdayHeaders,
  });

  final int pageNumber;
  final List<ParsedTimetableRow> gridRows;
  final String fallbackText;
  final bool hasWeekdayHeaders;
}

class PdfTimetableScanResult {
  const PdfTimetableScanResult({
    required this.pages,
    required this.totalPages,
    required this.scannedPages,
  });

  final List<PdfPageScanResult> pages;
  final int totalPages;
  final int scannedPages;

  int get pagesSkipped => totalPages - scannedPages;

  String get text => pages.map((page) => page.fallbackText).join('\n');

  /// Whether any parser in the fallback chain can read this page's text.
  static bool _textParseable(String text) =>
      ParseChain.parse(text).sectioned.isNotEmpty ||
      ParseChain.parse(text).list.isNotEmpty;

  List<ParsedTimetableRow> get gridRows {
    final rows = <ParsedTimetableRow>[];
    for (final page in pages) {
      rows.addAll(page.gridRows);
      if (page.gridRows.isEmpty && !page.hasWeekdayHeaders) {
        // Same chain as the image import path: the shared ParseChain runs
        // prepareScheduleLines then the sectioned parser first (it reads
        // more layouts - day sections, slot bands, exam lists) and the line
        // parser stays as the conservative second attempt.
        final chain = ParseChain.parse(page.fallbackText);
        if (chain.sectioned.isNotEmpty) {
          rows.addAll([
            for (final row in chain.sectioned)
              ParsedTimetableRow(
                subject: row.subject,
                room: row.room,
                professor: row.professor,
                day: row.day,
                startMinutes: row.startMinutes,
                endMinutes: row.endMinutes,
                ocrConfidence: row.ocrConfidence,
              ),
          ]);
        } else {
          rows.addAll(chain.list);
        }
      }
    }

    final seen = <String>{};
    return rows.where((row) {
      final subject = row.subject
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return seen.add(
        '${row.day}|${row.startMinutes}|${row.endMinutes}|$subject',
      );
    }).toList();
  }

  List<int> get pagesNeedingReview => [
    for (final page in pages)
      if (page.gridRows.isEmpty &&
          (page.hasWeekdayHeaders || !_textParseable(page.fallbackText)))
        page.pageNumber,
  ];
}
