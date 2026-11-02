/// A status the user sets on one class occurrence (or a run of them).
enum DayStatus { finished, notAttending, cancelled }

extension DayStatusDetails on DayStatus {
  String get label => switch (this) {
    DayStatus.finished => 'Finished',
    DayStatus.notAttending => 'Not attending',
    DayStatus.cancelled => 'Cancelled',
  };

  String get dbValue => switch (this) {
    DayStatus.finished => 'finished',
    DayStatus.notAttending => 'not_attending',
    DayStatus.cancelled => 'cancelled',
  };
}

DayStatus dayStatusFromDb(String value) => switch (value) {
  'finished' => DayStatus.finished,
  'cancelled' => DayStatus.cancelled,
  _ => DayStatus.notAttending,
};

/// How long a status applies, as offered in the Mark class sheet.
enum StatusSpan { thisClass, untilDate, untilCleared }

extension StatusSpanDetails on StatusSpan {
  String get label => switch (this) {
    StatusSpan.thisClass => 'This class',
    StatusSpan.untilDate => 'Until date',
    StatusSpan.untilCleared => 'Until I clear',
  };
}

const List<String> shortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// yyyy-MM-dd, which sorts correctly as text.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String _shiftDateKey(String key, int days) {
  final d = parseDateKey(key);
  return dateKey(DateTime(d.year, d.month, d.day + days));
}

/// The date of [weekday] (1 = Monday ... 7 = Sunday) in the same Monday-to-Sunday week as [now].
DateTime dateForWeekday(DateTime now, int weekday) =>
    DateTime(now.year, now.month, now.day + (weekday - now.weekday));

/// The Sunday of the week that contains [d].
DateTime endOfWeekOf(DateTime d) =>
    DateTime(d.year, d.month, d.day + (7 - d.weekday));

/// Short human date, for example "Fri 23 Oct".
String shortDateLabel(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[d.weekday - 1]} ${d.day} ${shortMonthNames[d.month - 1]}';
}

class ClassStatusEntry {
  final int? id;
  final int classId;
  final DayStatus status;
  final String startDate; // yyyy-MM-dd, inclusive
  final String? endDate; // yyyy-MM-dd, inclusive; null = until cleared

  const ClassStatusEntry({
    this.id,
    required this.classId,
    required this.status,
    required this.startDate,
    this.endDate,
  });

  bool isActiveOn(DateTime date) {
    final key = dateKey(date);
    if (key.compareTo(startDate) < 0) return false;
    final end = endDate;
    return end == null || key.compareTo(end) <= 0;
  }

  /// The preset this entry matches, or null after a split left a custom range.
  StatusSpan? get presetSpan {
    final end = endDate;
    if (end == null) return StatusSpan.untilCleared;
    if (end == startDate) return StatusSpan.thisClass;
    return null;
  }

  ClassStatusEntry copyWith({String? startDate, String? endDate}) =>
      ClassStatusEntry(
        id: id,
        classId: classId,
        status: status,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
      );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'class_id': classId,
    'status': status.dbValue,
    'start_date': startDate,
    'end_date': endDate,
  };

  factory ClassStatusEntry.fromMap(Map<String, Object?> m) => ClassStatusEntry(
    id: m['id'] as int?,
    classId: m['class_id'] as int,
    status: dayStatusFromDb(m['status'] as String),
    startDate: m['start_date'] as String,
    endDate: m['end_date'] as String?,
  );
}

/// Statuses grouped by class id. A class can have several non-overlapping ranges.
typedef ClassStatuses = Map<int, List<ClassStatusEntry>>;

/// Returns [existing] with the days covered by [incoming] replaced by it.
/// Entries that only partly overlap are cut back, so days outside the new range keep their status.
List<ClassStatusEntry> replaceStatusRange(
  List<ClassStatusEntry> existing,
  ClassStatusEntry incoming,
) {
  final incomingEnd = incoming.endDate;
  final result = <ClassStatusEntry>[];
  for (final e in existing) {
    final entryEnd = e.endDate;
    final overlaps =
        (incomingEnd == null || e.startDate.compareTo(incomingEnd) <= 0) &&
        (entryEnd == null || entryEnd.compareTo(incoming.startDate) >= 0);
    if (!overlaps) {
      result.add(e);
      continue;
    }
    if (e.startDate.compareTo(incoming.startDate) < 0) {
      // Split segments are new rows: they must not keep the source row's
      // id, or re-inserting them collides with the original primary key.
      result.add(
        ClassStatusEntry(
          classId: e.classId,
          status: e.status,
          startDate: e.startDate,
          endDate: _shiftDateKey(incoming.startDate, -1),
        ),
      );
    }
    if (incomingEnd != null &&
        (entryEnd == null || entryEnd.compareTo(incomingEnd) > 0)) {
      result.add(
        ClassStatusEntry(
          classId: e.classId,
          status: e.status,
          startDate: _shiftDateKey(incomingEnd, 1),
          endDate: entryEnd,
        ),
      );
    }
  }
  result.add(incoming);
  return result;
}

/// Removes [day] from [target]'s range and keeps the rest of the range on either side.
/// Other entries are returned unchanged.
List<ClassStatusEntry> clearStatusOnDay(
  List<ClassStatusEntry> existing,
  ClassStatusEntry target,
  String day,
) {
  final result = <ClassStatusEntry>[];
  for (final e in existing) {
    if (e.id != target.id) {
      result.add(e);
      continue;
    }
    if (e.startDate.compareTo(day) < 0) {
      result.add(
        ClassStatusEntry(
          classId: e.classId,
          status: e.status,
          startDate: e.startDate,
          endDate: _shiftDateKey(day, -1),
        ),
      );
    }
    final end = e.endDate;
    if (end == null || end.compareTo(day) > 0) {
      result.add(
        ClassStatusEntry(
          classId: e.classId,
          status: e.status,
          startDate: _shiftDateKey(day, 1),
          endDate: end,
        ),
      );
    }
  }
  return result;
}

/// Short text for a status pill: "today", "this day", "until Sun", "until 25 Oct", "until cleared".
String statusDurationLabel(ClassStatusEntry entry, DateTime today) {
  final end = entry.endDate;
  if (end == null) return 'until cleared';
  if (end == entry.startDate) {
    return entry.startDate == dateKey(today) ? 'today' : 'this day';
  }
  final d = parseDateKey(end);
  return 'until ${d.day} ${shortMonthNames[d.month - 1]}';
}

/// The status entry that applies to a class occurrence on [date], or null.
ClassStatusEntry? activeStatusEntry(
  ClassStatuses statuses,
  int? classId,
  DateTime date,
) {
  if (classId == null) return null;
  for (final entry in statuses[classId] ?? const <ClassStatusEntry>[]) {
    if (entry.isActiveOn(date)) return entry;
  }
  return null;
}

/// Dates (yyyy-MM-dd) in the next [days] days, starting today, on which this class
/// has an active status. Only days that fall on [weekday] are checked.
List<String> markedDateKeys(
  ClassStatuses statuses,
  int? classId,
  int weekday,
  DateTime now, {
  int days = 8,
}) {
  final keys = <String>[];
  for (var i = 0; i < days; i++) {
    final d = DateTime(now.year, now.month, now.day + i);
    if (d.weekday != weekday) continue;
    if (activeStatusEntry(statuses, classId, d) != null) keys.add(dateKey(d));
  }
  return keys;
}

/// The status that applies to a class occurrence on [date], or null.
DayStatus? activeDayStatus(
  ClassStatuses statuses,
  int? classId,
  DateTime date,
) => activeStatusEntry(statuses, classId, date)?.status;
