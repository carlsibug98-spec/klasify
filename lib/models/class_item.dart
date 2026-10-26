/// Sentinel professor value stored when the field is left empty.
/// Always compare against this constant — never a raw string — so the
/// sentinel can never drift between screens and parsers.
const String unspecifiedProfessor = 'Not specified';

const List<String> dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Minutes since midnight -> "1:30 PM"
String formatMinutes(int m) {
  final h24 = m ~/ 60;
  final min = m % 60;
  // 1440 (end of day) renders as 12:00 AM, the midnight it actually is —
  // not "12:00 PM", which reads as noon in the middle of the day.
  final period = h24 >= 12 && h24 < 24 ? 'PM' : 'AM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${min.toString().padLeft(2, '0')} $period';
}

/// "304" -> "Room 304", but "Lab 2" stays "Lab 2" (it already names the place).
String formatRoom(String room) {
  final r = room.trim();
  return RegExp(r'[A-Za-z]{3,}').hasMatch(r) ? r : 'Room $r';
}

class ClassItem {
  final int? id;
  final String subject;
  final String room;
  final String professor;
  final int day; // 1 = Monday ... 7 = Sunday (same as DateTime.weekday)
  final int startMinutes;
  final int endMinutes;

  const ClassItem({
    this.id,
    required this.subject,
    required this.room,
    required this.professor,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
  });

  String get dayName => dayNames[day - 1];
  String get timeRange =>
      '${formatMinutes(startMinutes)} - ${formatMinutes(endMinutes)}';

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'subject': subject,
    'room': room,
    'professor': professor,
    'day': day,
    'start_minutes': startMinutes,
    'end_minutes': endMinutes,
  };

  factory ClassItem.fromMap(Map<String, Object?> m) => ClassItem(
    id: m['id'] as int?,
    subject: m['subject'] as String,
    room: m['room'] as String,
    professor: m['professor'] as String,
    day: m['day'] as int,
    startMinutes: m['start_minutes'] as int,
    endMinutes: m['end_minutes'] as int,
  );
}
