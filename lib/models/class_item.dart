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

/// "10:00 – 11:30 AM" — an en dash, with the period printed once when both
/// ends share it. The hero and widget use this shorter form; [ClassItem.timeRange]
/// keeps the older hyphen/duplicated-period form for the rest of the app.
String formatTimeRange(int startMinutes, int endMinutes) {
  final start = formatMinutes(startMinutes);
  final end = formatMinutes(endMinutes);
  final startPeriod = start.substring(start.length - 2);
  if (startPeriod == end.substring(end.length - 2)) {
    return '${start.substring(0, start.length - 3)} – $end';
  }
  return '$start – $end';
}

class ClassItem {
  final int? id;

  /// Server-side id, set after a successful sync push. Null until then.
  final int? serverId;

  final String subject;
  final String room;
  final String professor;
  final int day; // 1 = Monday ... 7 = Sunday (same as DateTime.weekday)
  final int startMinutes;
  final int endMinutes;

  /// Soft-delete flag for sync. Locally deleted rows are kept with
  /// deleted=true until the server confirms the deletion.
  final bool deleted;

  /// Last modification time (UTC). Used for last-write-wins conflict
  /// resolution during sync.
  final DateTime? updatedAt;

  const ClassItem({
    this.id,
    this.serverId,
    required this.subject,
    required this.room,
    required this.professor,
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    this.deleted = false,
    this.updatedAt,
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
    'deleted': deleted ? 1 : 0,
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    if (serverId != null) 'server_id': serverId,
  };

  factory ClassItem.fromMap(Map<String, Object?> m) => ClassItem(
    id: m['id'] as int?,
    serverId: m['server_id'] as int?,
    subject: m['subject'] as String,
    room: m['room'] as String,
    professor: m['professor'] as String,
    day: m['day'] as int,
    startMinutes: m['start_minutes'] as int,
    endMinutes: m['end_minutes'] as int,
    deleted: (m['deleted'] as int? ?? 0) != 0,
    updatedAt: m['updated_at'] != null
        ? DateTime.tryParse(m['updated_at'] as String)
        : null,
  );
}
