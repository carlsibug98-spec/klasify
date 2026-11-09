import 'class_item.dart' show formatMinutes, formatRoom;
import 'class_status.dart' show dateKey, parseDateKey, shortMonthNames;

/// Lead-time choices for event reminders. Same set as the class engine's,
/// so one memory shape covers both.
const List<int> eventLeadChoices = [5, 10, 15, 30];

/// Events default to a longer heads-up than classes: they are one-off
/// whole-school affairs that people plan a block of time around, not a
/// five-minute walk across campus.
const int eventDefaultLeadMinutes = 30;

/// "Sat" for the event date block and sheet kicker (uppercase'd per use).
const List<String> shortWeekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

String shortWeekdayLabel(DateTime d) => shortWeekdayNames[d.weekday - 1];

/// Event categories. School events are whole-school affairs (assemblies,
/// exams, holidays) that everyone sees; personal events are the user's own.
enum EventCategory { personal, school }

/// yyyy-MM-dd date, minutes-since-midnight time. One-off school events
/// opposite the weekly [ClassItem]s.
class EventItem {
  final int? id;

  /// Server-side id, set after a successful sync push. Null until then.
  final int? serverId;

  /// Event name ("Culture Day"). At least 2 characters, mirroring classes.
  final String title;

  /// Where it happens ("Gymnasium"). Optional: events without a venue
  /// recorded yet read "venue to confirm" in copy, like classes do.
  final String venue;

  /// Event day as yyyy-MM-dd (the [dateKey] convention, which sorts as text).
  final String date;

  /// Start time in minutes since midnight. Events have no end time — the
  /// whole-school list treats them as "starts at" moments, not intervals.
  final int startMinutes;

  /// Per-event "Remind me" switch. The global reminders switch gates
  /// all reminders on top of this, exactly as for classes.
  final bool remindMe;

  /// How long before the start the reminder fires; one of [eventLeadChoices].
  final int leadMinutes;

  /// Whether this is a personal event or a school-wide event.
  final EventCategory category;

  /// Department scope: null = school-wide (everyone sees it), non-null =
  /// only that department's users see it (admin-created department events).
  final String? department;

  /// True when an admin posted this event to a whole department or the
  /// whole school. Broadcast rows are read-only for regular users: their
  /// long-press delete would otherwise remove the event for everyone.
  final bool broadcast;

  /// Soft-delete flag for sync. Locally deleted rows are kept with
  /// deleted=true until the server confirms the deletion.
  final bool deleted;

  /// Last modification time (UTC). Used for last-write-wins conflict
  /// resolution during sync.
  final DateTime? updatedAt;

  const EventItem({
    this.id,
    this.serverId,
    required this.title,
    required this.venue,
    required this.date,
    required this.startMinutes,
    this.remindMe = true,
    this.leadMinutes = eventDefaultLeadMinutes,
    this.category = EventCategory.personal,
    this.department,
    this.broadcast = false,
    this.deleted = false,
    this.updatedAt,
  });

  /// The event's day as [DateTime] (midnight, no time component).
  DateTime get day => parseDateKey(date);

  /// "9:00 AM"
  String get timeLabel => formatMinutes(startMinutes);

  /// "Gymnasium · 9:00 AM", or just the time when no venue is recorded.
  String get whenAndWhereLabel =>
      venue.trim().isEmpty ? timeLabel : '${formatRoom(venue)} · $timeLabel';

  /// "30 minutes before" for the alert picker and the reminder copy.
  String get leadLabel => '$leadMinutes minutes before';

  /// The reminder fire time in minutes since midnight, mirroring the
  /// reminder engine: a lead longer than the gap slides to the start
  /// minute itself, never before midnight.
  int get reminderFireMinutes =>
      startMinutes >= leadMinutes ? startMinutes - leadMinutes : startMinutes;

  /// The fire time label ("8:30 AM") for the reminder pill and copies.
  String get reminderFireLabel => formatMinutes(reminderFireMinutes);

  /// True when this event's alarm would fire at or after [now]'s minute —
  /// i.e. the pill can still show the concrete fire time.
  bool reminderStillFiresOn(DateTime now) {
    final todayKey = dateKey(DateTime(now.year, now.month, now.day));
    if (date.compareTo(todayKey) != 0) return true;
    return reminderFireMinutes > now.hour * 60 + now.minute;
  }

  /// True when this event has not started yet on [now]'s calendar day.
  bool isUpcomingOn(DateTime now) {
    final todayKey = dateKey(DateTime(now.year, now.month, now.day));
    if (date.compareTo(todayKey) < 0) return false;
    if (date.compareTo(todayKey) > 0) return true;
    return startMinutes > now.hour * 60 + now.minute;
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'venue': venue,
    'date': date,
    'start_minutes': startMinutes,
    'reminder_enabled': remindMe ? 1 : 0,
    'lead_minutes': leadMinutes,
    'category': category.name,
    'department': department,
    'broadcast': broadcast ? 1 : 0,
    'deleted': deleted ? 1 : 0,
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    if (serverId != null) 'server_id': serverId,
  };

  factory EventItem.fromMap(Map<String, Object?> m) => EventItem(
    id: m['id'] as int?,
    serverId: m['server_id'] as int?,
    title: m['title'] as String,
    venue: m['venue'] as String? ?? '',
    date: m['date'] as String,
    startMinutes: m['start_minutes'] as int,
    remindMe: (m['reminder_enabled'] as int? ?? 1) != 0,
    leadMinutes: m['lead_minutes'] as int? ?? eventDefaultLeadMinutes,
    category: EventCategory.values.firstWhere(
      (c) => c.name == (m['category'] as String? ?? 'personal'),
      orElse: () => EventCategory.personal,
    ),
    department: m['department'] as String?,
    broadcast: (m['broadcast'] as int? ?? 0) != 0,
    deleted: (m['deleted'] as int? ?? 0) != 0,
    updatedAt: m['updated_at'] != null
        ? DateTime.tryParse(m['updated_at'] as String)
        : null,
  );
}

/// "Sat, Nov 7" — the sheet kicker. The month names come from
/// [shortMonthNames] so the sheet and the settings copy stay in one voice.
String eventKickLabel(DateTime d) =>
    '${shortWeekdayLabel(d)}, ${shortMonthNames[d.month - 1]} ${d.day}';
