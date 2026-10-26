int? parseOcrClockMinute(String text) {
  // OCR misreads colons as dots on small timetable rails, so both "8:00"
  // and "8.00" are accepted. A bare hour ("8") stays rejected: it is
  // indistinguishable from a period number.
  final match = RegExp(
    r'(\d{1,2})[.:](\d{2})(?:\s*([AP])\.?M\.?)?',
    caseSensitive: false,
  ).firstMatch(text);
  final hour = int.tryParse(match?.group(1) ?? '');
  final minute = int.tryParse(match?.group(2) ?? '');
  if (hour == null || minute == null || minute > 59) return null;

  final meridiem = match?.group(3)?.toUpperCase();
  if (meridiem != null) {
    if (hour < 1 || hour > 12) return null;
    return (hour % 12 + (meridiem == 'P' ? 12 : 0)) * 60 + minute;
  }

  if (hour > 23) return null;
  return hour * 60 + minute;
}
