import '../models/class_item.dart';
import '../models/class_status.dart';

class NextClass {
  final ClassItem item;
  final bool isNow;
  final int minutesUntil;
  final int minutesToEnd;

  const NextClass(
    this.item,
    this.isNow,
    this.minutesUntil, {
    this.minutesToEnd = 0,
  });

  String get whenText {
    final prefix = isNow ? 'Ends in' : 'Starts in';
    final minutes = isNow ? minutesToEnd : minutesUntil;
    if (minutes < 60) return '$prefix $minutes min';
    if (minutes < 1440) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m == 0 ? '$prefix ${h}h' : '$prefix ${h}h ${m}m';
    }
    final days = minutes ~/ 1440;
    final remainingMinutes = minutes % 1440;
    final hours = remainingMinutes ~/ 60;
    final remainingMinutePart = remainingMinutes % 60;
    if (hours == 0 && remainingMinutePart == 0) return '$prefix ${days}d';
    if (remainingMinutePart == 0) return '$prefix ${days}d ${hours}h';
    if (hours == 0) return '$prefix ${days}d ${remainingMinutePart}m';
    return '$prefix ${days}d ${hours}h ${remainingMinutePart}m';
  }

  String dayPillText(DateTime now) {
    final tomorrowWeekday = (now.weekday % 7) + 1;
    if (item.day == tomorrowWeekday) {
      return 'TOMORROW';
    }
    return item.dayName.toUpperCase();
  }
}

/// Returns the class happening now, or the soonest upcoming one (this week).
/// A class occurrence with an active status (not attending / cancelled) is skipped.
NextClass? findNextClass(
  List<ClassItem> classes,
  DateTime now, {
  ClassStatuses statuses = const {},
}) {
  if (classes.isEmpty) return null;
  final nowMin = now.hour * 60 + now.minute;
  final today = DateTime(now.year, now.month, now.day);

  for (final c in classes) {
    if (c.day == now.weekday &&
        c.startMinutes <= nowMin &&
        nowMin < c.endMinutes &&
        activeDayStatus(statuses, c.id, today) == null) {
      return NextClass(c, true, 0, minutesToEnd: c.endMinutes - nowMin);
    }
  }

  NextClass? best;
  for (final c in classes) {
    var dayDiff = (c.day - now.weekday + 7) % 7;
    var until = dayDiff * 1440 + c.startMinutes - nowMin;
    if (until <= 0) {
      until += 7 * 1440; // already passed today -> next week
      dayDiff += 7;
    }
    final occurrence = DateTime(today.year, today.month, today.day + dayDiff);
    if (activeDayStatus(statuses, c.id, occurrence) != null) continue;
    if (best == null || until < best.minutesUntil) {
      best = NextClass(c, false, until);
    }
  }
  return best;
}
