import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../data/database_helper.dart';
import '../data/local_scope.dart';
import 'reminder_service.dart';

/// Owns which local scope is active and moves the app between them.
///
/// A switch is serialized: two sign-ins cannot interleave their file changes.
/// While one is running, [AppDatabase] holds its gate closed so no query can
/// read a file that is about to be replaced.
class LocalScopeService {
  LocalScopeService._();
  static final LocalScopeService instance = LocalScopeService._();

  /// Prefs key holding the last active scope (`anon` or a user id).
  static const lastScopeKey = 'klasify_last_scope';

  LocalScope? _current;
  bool _switching = false;
  bool _syncBlocked = false;

  /// Serializes switches. The chain survives a failed switch so the next
  /// attempt still runs.
  Future<void> _chain = Future<void>.value();

  /// Test seam: replaces [ReminderService.sync] during a switch.
  @visibleForTesting
  Future<void> Function()? reminderSyncOverride;

  /// The scope queries currently run against.
  ///
  /// Before [initialise] this is the anonymous scope, matching the default
  /// file name.
  LocalScope get current => _current ?? const LocalScope.anonymous();

  /// True only while a switch is changing files.
  bool get switching => _switching;

  /// Set when startup could not establish the persisted scope. Sync stays off
  /// so it cannot act on a file it was not meant to touch.
  bool get syncBlocked => _syncBlocked;

  /// Monotonic scope generation from [AppDatabase]; sync pins it.
  int get generation => AppDatabase.instance.scopeGeneration;

  /// Restores the persisted scope and finishes any interrupted adoption.
  ///
  /// Runs before the first screen builds. Dirty shutdowns are reconciled here
  /// rather than at the next sign-in, because the user may stay logged out.
  Future<void> initialise() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(lastScopeKey);
    final id = stored == null ? null : int.tryParse(stored);

    _current = id == null
        ? const LocalScope.anonymous()
        : LocalScope.account(id);
    AppDatabase.databaseName = _current!.fileName;
  }

  /// Makes [userId]'s file active, creating it on first sign-in.
  ///
  /// A null [userId] keeps whatever scope is active: signing out must not
  /// hide the schedule the person was just looking at.
  Future<void> ensureForUser(int? userId) {
    final result = _chain.then((_) => _ensureForUser(userId));
    _chain = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _ensureForUser(int? userId) async {
    if (userId == null) {
      if (_current == null) await initialise();
      return;
    }

    final target = LocalScope.account(userId);
    if (_current == target) return;

    await _switchTo(target);
  }

  Future<void> _switchTo(LocalScope target) async {
    final database = AppDatabase.instance;
    database.beginSwitch();
    _switching = true;
    try {
      AppDatabase.databaseName = target.fileName;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastScopeKey, target.storageKey);

      _current = target;

      // Screens reload from the file they now own.
      DatabaseHelper.instance.notifyScopeChanged();
    } finally {
      _switching = false;
      database.endSwitch();
    }

    await _reconcileReminders();
  }

  Future<void> _reconcileReminders() async {
    try {
      final override = reminderSyncOverride;
      if (override != null) {
        await override();
      } else {
        await ReminderService.instance.sync();
      }
    } catch (error, stack) {
      debugPrint('Reminder reconcile after scope switch failed: $error\n$stack');
    }
  }

  /// Test-only: forget the active scope and every cached connection.
  @visibleForTesting
  Future<void> resetForTesting() async {
    _current = null;
    _switching = false;
    _syncBlocked = false;
    _chain = Future<void>.value();
    reminderSyncOverride = null;
    AppDatabase.databaseName = 'class_schedule.db';
    await AppDatabase.instance.closeAll();
  }
}
