import 'package:klasify/features/schedule_import/utils/pdf_timetable_text.dart';
import 'package:flutter_test/flutter_test.dart';

PdfTextLineGeometry line(String text, double left, double right, double y) =>
    (text: text, left: left, right: right, centerY: y);

void main() {
  group('PdfTimetableText.parseRailLine', () {
    test('reads every common rail shape', () {
      expect(PdfTimetableText.parseRailLine('8:00 AM - 9:30 AM'), (
        minute: 525,
        meridiemExplicit: true,
      ));
      expect(PdfTimetableText.parseRailLine('0800-0930'), (
        minute: 525,
        meridiemExplicit: false,
      ));
      expect(PdfTimetableText.parseRailLine('8 - 9 PM'), (
        minute: 1230,
        meridiemExplicit: true,
      ));
      expect(PdfTimetableText.parseRailLine('11:00 AM - 1:00 PM'), (
        minute: 720,
        meridiemExplicit: true,
      ));
      expect(PdfTimetableText.parseRailLine('10:00 to 11:30'), (
        minute: 645,
        meridiemExplicit: false,
      ));
      expect(PdfTimetableText.parseRailLine('8.00 - 8.50'), (
        minute: 505,
        meridiemExplicit: false,
      ));
      expect(PdfTimetableText.parseRailLine('9:00'), (
        minute: 540,
        meridiemExplicit: false,
      ));
      expect(PdfTimetableText.parseRailLine('0900'), (
        minute: 540,
        meridiemExplicit: false,
      ));
      expect(PdfTimetableText.parseRailLine('8'), (
        minute: 480,
        meridiemExplicit: false,
      ));
      expect(PdfTimetableText.parseRailLine('Room 8'), isNull);
      expect(PdfTimetableText.parseRailLine('Fall Semester Schedule'), isNull);
    });

    test('rejects year pairs as rail times', () {
      expect(PdfTimetableText.parseRailLine('2025 - 2026'), isNull);
      expect(PdfTimetableText.parseRailLine('2025-2026'), isNull);
    });

    test('reads period rails as nominal ticks', () {
      // P1 = 08:00-09:00, so the tick sits at its midpoint 08:30.
      expect(PdfTimetableText.parseRailLine('P1'), (
        minute: 510,
        meridiemExplicit: true,
      ));
      expect(PdfTimetableText.parseRailLine('Period 3'), (
        minute: 630,
        meridiemExplicit: true,
      ));
      // P3-P4 = 10:00-12:00 inclusive, midpoint 11:00.
      expect(PdfTimetableText.parseRailLine('P3-P4'), (
        minute: 660,
        meridiemExplicit: true,
      ));
      expect(PdfTimetableText.parseRailLine('Period 1 - Period 2'), (
        minute: 540,
        meridiemExplicit: true,
      ));
      // Period markers must own the whole line.
      expect(PdfTimetableText.parseRailLine('Math P1'), isNull);
      expect(PdfTimetableText.parseRailLine('P13'), isNull);
      expect(PdfTimetableText.parseRailLine('P1-P'), isNull);
    });
  });

  group('PdfTimetableText.resolveRailTicks', () {
    test('carries bare 12-hour values across noon', () {
      final ticks = PdfTimetableText.resolveRailTicks([
        line('8:00 AM', 10, 60, 100),
        line('9:00', 10, 60, 140),
        line('10:00', 10, 60, 180),
        line('11:00', 10, 60, 220),
        line('12:00', 10, 60, 260),
        line('1:00', 10, 60, 300),
        line('2:00 PM', 10, 60, 340),
      ], inMargin: (l) => true);
      expect(ticks.map((tick) => tick.minute).toList(), [
        480,
        540,
        600,
        660,
        720,
        780,
        840,
      ]);
    });

    test('reads a descending rail under a bottom-left page origin', () {
      final ticks = PdfTimetableText.resolveRailTicks([
        line('8:00 AM', 10, 60, 340),
        line('9:00', 10, 60, 300),
        line('10:00', 10, 60, 260),
        line('11:00', 10, 60, 220),
        line('12:00', 10, 60, 180),
        line('1:00', 10, 60, 140),
        line('2:00 PM', 10, 60, 100),
      ], inMargin: (l) => true);
      expect(ticks.map((tick) => tick.minute).toList(), [
        480,
        540,
        600,
        660,
        720,
        780,
        840,
      ]);
    });

    test('collects period rails into an ascending axis', () {
      final ticks = PdfTimetableText.resolveRailTicks([
        line('P1', 10, 60, 100),
        line('P2', 10, 60, 160),
        line('P3', 10, 60, 220),
        line('P4', 10, 60, 280),
      ], inMargin: (l) => true);
      expect(ticks.map((tick) => tick.minute).toList(), [510, 570, 630, 690]);
    });

    test('refuses rails that are too short or sparse', () {
      expect(
        PdfTimetableText.resolveRailTicks([
          line('8:00', 0, 40, 0),
          line('8:30', 0, 40, 40),
        ], inMargin: (l) => true),
        isEmpty,
      );
      expect(
        PdfTimetableText.resolveRailTicks([
          line('8:00', 0, 40, 0),
        ], inMargin: (l) => true),
        isEmpty,
      );
    });
  });

  group('PdfTimetableText.dayOfHeaderCell', () {
    test('maps full, abbreviated, two-letter, and single-letter headers', () {
      expect(PdfTimetableText.dayOfHeaderCell('MONDAY'), 1);
      expect(PdfTimetableText.dayOfHeaderCell('Mon.'), 1);
      expect(PdfTimetableText.dayOfHeaderCell('TUES'), 2);
      expect(PdfTimetableText.dayOfHeaderCell('SATURDAY'), 6);
      expect(PdfTimetableText.dayOfHeaderCell('TH'), 4);
      expect(PdfTimetableText.dayOfHeaderCell('SU'), 7);
      // MTWRF convention: R is Thursday.
      expect(PdfTimetableText.dayOfHeaderCell('R'), 4);
      expect(PdfTimetableText.dayOfHeaderCell('M'), 1);
      expect(PdfTimetableText.dayOfHeaderCell('Math'), isNull);
      expect(PdfTimetableText.dayOfHeaderCell('CS 101'), isNull);
      expect(PdfTimetableText.dayOfHeaderCell(''), isNull);
    });
  });
}
