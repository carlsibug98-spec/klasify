import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/database_helper.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../models/event_item.dart';

/// Pending reminder IDs that the current schedule no longer uses.
@visibleForTesting
List<int> staleReminderIds(Iterable<int> pending, Set<int> scheduled) =>
    pending.where((id) => !scheduled.contains(id)).toList();

/// Local-only weekly system notifications scheduled before each class.
class ReminderService extends ChangeNotifier {
  ReminderService._();
  static final ReminderService instance = ReminderService._();
  static const _enabledKey = 'class_reminders_enabled';

  /// Master gate for one-off event alarms. The per-event switch stays the
  /// second gate on top of it (see sync()); events keep their per-event
  /// setting while this gate is off, so turning it back on restores them
  /// without editing each event.
  static const _eventsEnabledKey = 'event_reminders_enabled';

  /// Lead time in minutes before each class; one of [_leadChoices].
  static const _leadKey = 'class_reminders_lead_minutes';
  static const defaultLeadMinutes = 10;

  /// The Notifications screen's chip choices (mockup v9 frame 7):
  /// 10 min · 30 min · 1 hour. Legacy values outside this list fall back
  /// to the default on the next read.
  static const _leadChoices = [10, 30, 60];
  // Android keeps a channel's description from its first creation, so the ID
  // is bumped to pick up the corrected description on existing installs.
  static const _channelId = 'class_schedule_reminders_v5';
  static const _channelDescription = 'Reminders before each class, every week.';
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Upcoming classes',
        description: _channelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
    // Remove the channels from before the ID bumps so they stop appearing in
    // settings.
    await android?.deleteNotificationChannel(
      channelId: 'class_schedule_reminders_v4',
    );
    await android?.deleteNotificationChannel(
      channelId: 'class_schedule_reminders_v3',
    );
    await android?.deleteNotificationChannel(
      channelId: 'class_schedule_reminders_v2',
    );
    _initialized = true;
  }

  /// The stored lead time, or [defaultLeadMinutes] when unset or invalid.
  Future<int> get leadMinutes async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_leadKey);
      return value != null && _leadChoices.contains(value)
          ? value
          : defaultLeadMinutes;
    } catch (_) {
      return defaultLeadMinutes;
    }
  }

  /// Persists the lead time and re-schedules the reminders.
  ///
  /// Values outside [_leadChoices] are clamped to [defaultLeadMinutes].
  Future<void> setLeadMinutes(int minutes) async {
    final value = _leadChoices.contains(minutes) ? minutes : defaultLeadMinutes;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_leadKey, value);
    } catch (_) {
      // Non-critical: worst case the chips show the last value again later.
    }
    notifyListeners();
    if (await isEnabled) await sync();
  }

  Future<bool> get isEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;

  /// The event-reminders master gate. false silences every one-off event
  /// alarm on the next sync while weekly class reminders keep working.
  Future<bool> get eventsEnabled async =>
      (await SharedPreferences.getInstance()).getBool(_eventsEnabledKey) ??
      true;

  /// Persists the event gate and re-syncs so the pending alarms match:
  /// turning it off prunes the event reminders, turning it on schedules
  /// the ones per-event switches still ask for.
  Future<void> setEventsEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_eventsEnabledKey, value);
    } catch (_) {
      // Non-critical: worst case the toggle reads back its old value.
    }
    notifyListeners();
    if (await isEnabled) await sync();
  }

  Future<bool> enable() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final androidGranted = await android?.requestNotificationsPermission();
    if (android != null && androidGranted != true) return false;
    if (android != null) await requestExactAlarmsAccess();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted = android != null || ios != null
        ? android != null || iosGranted == true
        : false;
    if (!granted) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);
    notifyListeners();
    await sync();
    return true;
  }

  Future<bool> get exactAlarmsAvailable async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<bool> requestExactAlarmsAccess() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    if (await android.canScheduleExactNotifications() == true) return true;
    await android.requestExactAlarmsPermission();
    final granted = await android.canScheduleExactNotifications() == true;
    if (granted && await isEnabled) await sync();
    return granted;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    notifyListeners();
    await initialize();
    await _plugin.cancelAll();
  }

  Future<void> sync() async {
    if (!await isEnabled) return;
    await initialize();
    // Read everything before touching notifications. If a read fails, the
    // current reminders stay in place.
    final statuses = await DatabaseHelper.instance.getClassStatuses();
    final classes = await DatabaseHelper.instance.getAll();
    final events = await DatabaseHelper.instance.getAllEvents();
    final previousIds = (await _plugin.pendingNotificationRequests())
        .map((request) => request.id)
        .toList();
    // Nothing is cancelled up front. Reminder IDs are deterministic, so
    // rescheduling one replaces it, and stale ones are removed at the end. A
    // failure partway through leaves the reminders not yet rescheduled intact.
    final scheduledIds = <int>{};
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exactAlarmsAvailable =
        await android?.canScheduleExactNotifications() ?? false;
    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);
    final leadMinutes = await this.leadMinutes;
    try {
    for (final c in classes) {
      final reminderMinutes = c.startMinutes >= leadMinutes
          ? c.startMinutes - leadMinutes
          : c.startMinutes;
      final marks = statuses[c.id] ?? const <ClassStatusEntry>[];

      // The last day any mark still covers. An until-cleared mark covers every
      // later date, so it ends the schedule at the day it starts.
      DateTime? lastMarked;
      var openEnded = false;
      for (final e in marks) {
        final endKey = e.endDate;
        if (endKey == null) {
          openEnded = true;
          final start = parseDateKey(e.startDate);
          final stop = start.isBefore(today) ? today : start;
          if (lastMarked == null || stop.isAfter(lastMarked)) lastMarked = stop;
          continue;
        }
        final end = parseDateKey(endKey);
        if (end.isBefore(today)) continue;
        if (lastMarked == null || end.isAfter(lastMarked)) lastMarked = end;
      }

      // Up to the last mark: one reminder per date, skipping marked dates.
      if (lastMarked != null) {
        for (
          var date = today;
          !date.isAfter(lastMarked);
          date = _addDays(date, 1)
        ) {
          if (date.weekday != c.day) continue;
          if (activeStatusEntry(statuses, c.id, date) != null) continue;
          final when = _at(date, reminderMinutes);
          if (!when.isAfter(now)) continue;
          await _scheduleAt(
            id: _occurrenceId(c, date),
            scheduledIds: scheduledIds,
            c: c,
            when: when,
            repeat: false,
            exact: exactAlarmsAvailable,
            leadMinutes: leadMinutes,
          );
        }
      }

      // After the last mark: a weekly repeat, starting on the first matching
      // day after it. It turns back on by itself, with no app run needed.
      // Until-cleared marks have no tail; clearing one re-syncs.
      if (!openEnded) {
        var day = lastMarked == null ? today : _addDays(lastMarked, 1);
        while (day.weekday != c.day) {
          day = _addDays(day, 1);
        }
        var when = _at(day, reminderMinutes);
        if (!when.isAfter(now)) {
          when = _at(_addDays(day, 7), reminderMinutes);
        }
        await _scheduleAt(
          id: _repeatId(c),
          scheduledIds: scheduledIds,
          c: c,
          when: when,
          repeat: true,
          exact: exactAlarmsAvailable,
          leadMinutes: leadMinutes,
        );
      }
    }

    // Events: one-off alarms, independent of the weekly class cycle. Two
    // gates before an alarm books: this screen's event-reminders gate and
    // the per-event switch. Both are respected when the master switch is
    // turned back on, without editing each event.
    final eventsOn = await eventsEnabled;
    for (final e in events) {
      if (!eventsOn || !e.remindMe) continue;
      final reminderMinutes = e.startMinutes >= e.leadMinutes
          ? e.startMinutes - e.leadMinutes
          : e.startMinutes;
      final when = _at(parseDateKey(e.date), reminderMinutes);
      // Events already past (or due this instant) stay silent — no pitfall
      // alarm for "the fair started 20 seconds ago".
      if (!when.isAfter(now)) continue;
      await _scheduleEventAt(
        id: _eventReminderId(e),
        scheduledIds: scheduledIds,
        event: e,
        when: when,
        exact: exactAlarmsAvailable,
      );
    }
    } finally {
      // Runs even if scheduling failed, so a skipped or deleted class never
      // keeps an old reminder.
      await _pruneStale(previousIds, scheduledIds);
    }
  }

  /// Cancels every reminder the new schedule no longer uses. Each cancel is
  /// attempted even if an earlier one fails; the first failure is rethrown.
  Future<void> _pruneStale(List<int> previousIds, Set<int> scheduledIds) async {
    Object? firstError;
    for (final id in staleReminderIds(previousIds, scheduledIds)) {
      try {
        await _plugin.cancel(id: id);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  /// Notification details every reminder posts with, class or event.
  static const NotificationDetails _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Upcoming classes',
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  Future<void> _scheduleAt({
    required int id,
    required Set<int> scheduledIds,
    required ClassItem c,
    required tz.TZDateTime when,
    required bool repeat,
    required bool exact,
    required int leadMinutes,
  }) async {
    scheduledIds.add(id);
    await _plugin.zonedSchedule(
      id: id,
      title: 'Class starting soon',
      body: _reminderBody(c, leadMinutes: leadMinutes),
      scheduledDate: when,
      notificationDetails: _notificationDetails,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: repeat
          ? DateTimeComponents.dayOfWeekAndTime
          : null,
      payload: 'class:${c.id ?? _stableId(c)}',
    );
  }

  /// One-off event alarm: fires once at the chosen lead time, then the
  /// schedule has no use for the ID ([_pruneStale] drops it).
  Future<void> _scheduleEventAt({
    required int id,
    required Set<int> scheduledIds,
    required EventItem event,
    required tz.TZDateTime when,
    required bool exact,
  }) async {
    scheduledIds.add(id);
    await _plugin.zonedSchedule(
      id: id,
      title: event.category == EventCategory.school
          ? 'School event starting soon'
          : 'Event starting soon',
      body: _eventReminderBody(event),
      scheduledDate: when,
      notificationDetails: _notificationDetails,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'event:${event.id}',
    );
  }

  /// Deterministic per-row ID: editing any field re-posts the same row, yet
  /// a reminder survives an unrelated edit elsewhere. The `event:` prefix
  /// keeps its hash space disjoint from the class ID strings.
  int _eventReminderId(EventItem e) => 'event:${e.id}'.hashCode & 0x7fffffff;

  /// The class body's voice, for events: venue named, lead time spelled out,
  /// and "venue to confirm" when nothing was recorded.
  String _eventReminderBody(EventItem e) {
    final venue = e.venue.trim();
    final prefix = e.category == EventCategory.school ? 'School event: ' : '';
    return venue.isEmpty
        ? '$prefix${e.title}, venue to confirm. Starts in ${e.leadMinutes} minutes.'
        : '$prefix${e.title} · ${formatRoom(venue)}. '
            'Starts in ${e.leadMinutes} minutes.';
  }

  /// Id of a class's weekly repeat. Different from any single-date id.
  int _repeatId(ClassItem c) =>
      '${c.subject}|${c.room}|${c.day}|${c.startMinutes}|repeat'.hashCode &
      0x7fffffff;

  /// One notification per class per date, so each date can be skipped on its own.
  int _occurrenceId(ClassItem c, DateTime date) =>
      '${c.subject}|${c.room}|${c.day}|${c.startMinutes}|${dateKey(date)}'
          .hashCode &
      0x7fffffff;

  // Reads correctly with or without a room: "Network Lab, room to confirm."
  String _reminderBody(ClassItem c, {int leadMinutes = defaultLeadMinutes}) {
    final room = c.room.trim().toLowerCase();
    final roomKnown =
        room.isNotEmpty && room != 'room to confirm' && room != 'unknown room';
    return roomKnown
        ? '${c.subject} · ${formatRoom(c.room)}. Starts in $leadMinutes minutes.'
        : '${c.subject}, room to confirm. Starts in $leadMinutes minutes.';
  }

  int _stableId(ClassItem c) =>
      '${c.subject}|${c.room}|${c.day}|${c.startMinutes}'.hashCode;
}

DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

tz.TZDateTime _at(DateTime d, int minutes) => tz.TZDateTime(
  tz.local,
  d.year,
  d.month,
  d.day,
  minutes ~/ 60,
  minutes % 60,
);
