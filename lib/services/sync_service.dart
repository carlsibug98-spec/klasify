import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import '../database/database_helper.dart';

/// Configurable sync backend client. Syncs local SQLite data to the
/// MySQL-backed API. All operations are best-effort: failures are queued
/// and retried on the next sync attempt.
class SyncService extends ChangeNotifier {
  SyncService._() {
    AuthService.instance.addListener(_onAuthChanged);
    _onAuthChanged();
  }
  static final SyncService instance = SyncService._();

  static String get baseUrl => AuthService.baseUrl;

  static const _lastPushKey = 'klasify_last_push_at';
  static const _lastPullKey = 'klasify_last_pull_at';
  static const _deviceIdKey = 'klasify_device_id';

  bool _syncing = false;
  bool get syncing => _syncing;

  Timer? _backgroundTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  String? _lastError;
  String? get lastError => _lastError;
  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;

  Future<String> get _deviceId async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  Future<DateTime?> get lastPushAt async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastPushKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<DateTime?> get lastPullAt async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastPullKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  /// Push local changes to the server. Returns true on success.
  Future<bool> push() async {
    final token = await _token;
    if (token == null) return false;

    _syncing = true;
    notifyListeners();
    try {
      final deviceId = await _deviceId;
      final lastPush = await lastPushAt;

      // Collect local changes since last push.
      final db = DatabaseHelper.instance;
      final changedClasses = await db.getChangedClasses(lastPush ?? DateTime(1970));
      final changedEvents = await db.getChangedEvents(lastPush ?? DateTime(1970));
      final changedStatuses = await db.getChangedClassStatuses(lastPush ?? DateTime(1970));

      final body = <String, dynamic>{
        'device_id': deviceId,
        'last_push_at': lastPush?.toUtc().toIso8601String(),
        'classes': changedClasses.map((c) => {
          'local_id': c.id,
          'server_id': c.serverId,
          'subject': c.subject,
          'room': c.room,
          'professor': c.professor,
          'day': c.day,
          'start_minutes': c.startMinutes,
          'end_minutes': c.endMinutes,
          'deleted': c.deleted,
          'updated_at': c.updatedAt?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String(),
        }).toList(),
        'events': changedEvents.map((e) => {
          'local_id': e.id,
          'server_id': e.serverId,
          'title': e.title,
          'venue': e.venue,
          'event_date': e.date,
          'start_minutes': e.startMinutes,
          'category': e.category.name,
          'department': e.department,
          'broadcast': e.broadcast,
          'reminder_enabled': e.remindMe,
          'lead_minutes': e.leadMinutes,
          'deleted': e.deleted,
          'updated_at': e.updatedAt?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String(),
        }).toList(),
        'class_statuses': changedStatuses.map((s) => {
          'local_id': s['id'],
          'server_id': s['server_id'],
          'local_class_id': s['class_id'],
          'status': s['status'],
          'start_date': s['start_date'],
          'end_date': s['end_date'],
          'deleted': (s['deleted'] as int? ?? 0) != 0,
          'updated_at': s['updated_at'] ?? DateTime.now().toUtc().toIso8601String(),
        }).toList(),
      };

      final res = await http.post(
        Uri.parse('$baseUrl/sync/push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final db = DatabaseHelper.instance;

        // Store the local_id -> server_id mappings the server answered
        // with, so pushed rows stop matching the change queries and can
        // identify themselves in future pushes (no duplicate server rows).
        for (final list in const ['classes', 'events', 'class_statuses']) {
          for (final item in data[list] as List? ?? []) {
            if (item is Map && item['local_id'] is int && item['server_id'] is int) {
              final localId = item['local_id'] as int;
              final serverId = item['server_id'] as int;
              if (list == 'classes') {
                await db.setClassServerId(localId, serverId);
              } else if (list == 'events') {
                await db.setEventServerId(localId, serverId);
              } else {
                await db.setClassStatusServerId(localId, serverId);
              }
            }
          }
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastPushKey, data['server_time'] as String);
        _lastError = null;
        _lastSyncAt = DateTime.now();
        return true;
      }
      debugPrint('Sync push failed: ${res.statusCode} ${res.body}');
      _lastError = 'Push failed: ${res.statusCode}';
      return false;
    } catch (e) {
      debugPrint('Sync push error: $e');
      _lastError = 'Push error: $e';
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Pull server changes since last pull. Returns true on success.
  Future<bool> pull() async {
    final token = await _token;
    if (token == null) return false;

    _syncing = true;
    notifyListeners();
    try {
      final deviceId = await _deviceId;
      final lastPull = await lastPullAt;
      final since = lastPull?.toUtc().toIso8601String() ?? '1970-01-01T00:00:00.000Z';

      final res = await http.get(
        Uri.parse(
          '$baseUrl/sync/pull?since=$since'
          '&device_id=${Uri.encodeQueryComponent(deviceId)}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final db = DatabaseHelper.instance;

        // Upsert pulled classes
        for (final row in (data['classes'] as List? ?? [])) {
          await db.upsertClassFromServer(row as Map<String, dynamic>);
        }

        // Upsert pulled events
        for (final row in (data['events'] as List? ?? [])) {
          await db.upsertEventFromServer(row as Map<String, dynamic>);
        }

        // Upsert pulled class statuses (their class ids resolve locally)
        for (final row in (data['class_statuses'] as List? ?? [])) {
          await db.upsertClassStatusFromServer(row as Map<String, dynamic>);
        }

        // Upsert pulled office availability (last-known value offline)
        for (final row in (data['office_statuses'] as List? ?? [])) {
          await db.upsertOfficeStatusFromServer(row as Map<String, dynamic>);
        }

        // Purge soft-deleted rows the server already accepted. Unpushed
        // tombstones survive: purging them early would silently drop the
        // deletion and let the server resurrect the row.
        await db.purgeDeleted(await lastPushAt);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_lastPullKey, data['server_time'] as String);
        _lastError = null;
        _lastSyncAt = DateTime.now();
        return true;
      }
      debugPrint('Sync pull failed: ${res.statusCode} ${res.body}');
      _lastError = 'Pull failed: ${res.statusCode}';
      return false;
    } catch (e) {
      debugPrint('Sync pull error: $e');
      _lastError = 'Pull error: $e';
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Full sync: push then pull. The pull is skipped when the push fails:
  /// applying server rows while unserved local changes are stuck can
  /// silently overwrite them (lose local edits) if the push just missed
  /// the network. Nothing is lost by waiting — the next cycle pushes first.
  Future<bool> syncNow() async {
    final pushOk = await push();
    if (!pushOk) {
      debugPrint('Sync pull skipped: push did not succeed.');
      return false;
    }
    return pull();
  }

  /// Background sync: a 5-minute periodic timer plus exponential-backoff
  /// retry after a failed attempt. Started/stopped automatically with the
  /// auth session (see [_onAuthChanged]).
  ///
  /// Boot hook: constructing the singleton (called from main) wires the auth
  /// listener so a restored session starts the timer without opening Settings.
  void ensureStarted() {}

  bool _sessionActive = false;

  void _onAuthChanged() {
    final loggedIn = AuthService.instance.isLoggedIn;
    // Auth notifies on every profile refresh; only session transitions should
    // restart the cadence.
    if (loggedIn == _sessionActive) return;
    _sessionActive = loggedIn;
    if (loggedIn) {
      _startBackgroundTimer();
      unawaited(syncNow());
    } else {
      _stopBackgroundTimer();
    }
  }

  void _startBackgroundTimer() {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (AuthService.instance.isLoggedIn && !_syncing) {
        unawaited(_backgroundSync());
      }
    });
  }

  void _stopBackgroundTimer() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
  }

  Future<void> _backgroundSync() async {
    final ok = await syncNow();
    if (ok) {
      _retryAttempt = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    } else {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final seconds = (30 * (1 << _retryAttempt)).clamp(30, 300);
    _retryAttempt = (_retryAttempt + 1).clamp(0, 4);
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (AuthService.instance.isLoggedIn && !_syncing) {
        unawaited(_backgroundSync());
      }
    });
  }

  Future<String?> get _token async {
    if (!AuthService.instance.isLoggedIn) return null;
    // Silent refresh when the JWT is expired or close to it, so the request
    // doesn't bounce on TOKEN_EXPIRED.
    await AuthService.instance.ensureFreshToken();
    return AuthService.instance.token;
  }
}
