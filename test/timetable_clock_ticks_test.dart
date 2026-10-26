import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/utils/timetable_clock_ticks.dart';

void main() {
  test('keeps AM and PM in grid clock labels', () {
    expect(parseOcrClockMinute('1:00 PM'), 13 * 60);
    expect(parseOcrClockMinute('12:00 AM'), 0);
    expect(parseOcrClockMinute('12:00 PM'), 12 * 60);
  });

  test('accepts 24-hour ticks and rejects invalid clocks', () {
    expect(parseOcrClockMinute('13:30'), 13 * 60 + 30);
    expect(parseOcrClockMinute('24:00'), isNull);
    expect(parseOcrClockMinute('13:00 PM'), isNull);
  });

  test('accepts dot-separated grid clock labels', () {
    expect(parseOcrClockMinute('8.00'), 8 * 60);
    expect(parseOcrClockMinute('13.30'), 13 * 60 + 30);
    expect(parseOcrClockMinute('1.30 PM'), 13 * 60 + 30);
  });

  test('still rejects bare hour labels and non-clock text', () {
    expect(parseOcrClockMinute('8'), isNull);
    expect(parseOcrClockMinute('Room 12'), isNull);
  });
}
