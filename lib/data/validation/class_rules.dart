import '../../models/class_item.dart';

/// Validates one class row before it reaches SQLite.
///
/// The database triggers repeat these checks, but throwing here gives the UI
/// a readable message and keeps invalid rows out of a transaction.
void validateClass(ClassItem c) {
  if (c.subject.trim().length < 2) {
    throw ArgumentError('Subject must contain at least 2 characters.');
  }
  if (c.room.trim().isEmpty) throw ArgumentError('Room is required.');
  if (c.professor.trim().length < 2) {
    throw ArgumentError('Professor must contain at least 2 characters.');
  }
  if (c.day < 1 || c.day > 7) throw ArgumentError('Day must be 1–7.');
  if (c.startMinutes < 0 || c.startMinutes >= 1440) {
    throw ArgumentError('Start time is invalid.');
  }
  if (c.endMinutes <= c.startMinutes || c.endMinutes > 1440) {
    throw ArgumentError(
      'End time must be after start time and within the day.',
    );
  }
}

/// Rejects overlapping classes inside one batch.
///
/// Rows are ordered by day and start time so only the previous end time has to
/// be remembered. Existing database rows are checked separately by the
/// repository, because this function only sees the incoming batch.
void validateNoOverlaps(Iterable<ClassItem> classes) {
  final ordered = classes.toList()
    ..sort((a, b) {
      final day = a.day.compareTo(b.day);
      return day == 0 ? a.startMinutes.compareTo(b.startMinutes) : day;
    });
  var day = 0;
  var latestEnd = 0;
  var latestClass = '';
  for (final item in ordered) {
    if (item.day != day) {
      day = item.day;
      latestEnd = item.endMinutes;
      latestClass = item.subject;
    } else if (item.startMinutes < latestEnd) {
      throw ArgumentError('${item.subject} overlaps $latestClass.');
    } else if (item.endMinutes > latestEnd) {
      latestEnd = item.endMinutes;
      latestClass = item.subject;
    }
  }
}
