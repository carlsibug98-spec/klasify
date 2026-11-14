import '../../models/class_status.dart' show dateKey, parseDateKey;
import '../../models/event_item.dart';

/// Validates one event row before it reaches SQLite.
void validateEvent(EventItem e) {
  if (e.title.trim().length < 2) {
    throw ArgumentError('Event name must contain at least 2 characters.');
  }
  // A malformed key must round-trip to itself: SQLite stores the string,
  // so "2026-02-30" would live on despite never being a real date.
  var dated = false;
  try {
    dated = dateKeyForEvent(e.date) == e.date;
  } catch (_) {
    dated = false;
  }
  if (!dated) throw ArgumentError('Event date is invalid.');
  if (e.startMinutes < 0 || e.startMinutes >= 1440) {
    throw ArgumentError('Event time is invalid.');
  }
  if (!eventLeadChoices.contains(e.leadMinutes)) {
    throw ArgumentError('Event lead time is invalid.');
  }
}

/// Parsed-with-validation equivalent of [dateKey]: throws on shapes it cannot
/// fully round-trip, because DateTime parses overflow silently
/// ("2026-02-30" becomes March 2).
String dateKeyForEvent(String date) {
  final d = parseDateKey(date);
  return dateKey(d);
}
