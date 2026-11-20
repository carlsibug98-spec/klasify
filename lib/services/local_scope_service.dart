import 'dart:io';

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

  /// Prefs key naming the account that is adopting the legacy file. It exists
  /// only while the rename may be in flight.
  static const legacyClaimKey = 'klasify_legacy_claim';

  /// Prefs keys written by the pre-scope sync implementation. They are consumed
  /// once and removed; a second scope never sees them.
  static const _legacyDeviceIdKey = 'klasify_device_id';
  static const _legacyDeviceOwnerKey = 'klasify_device_owner_id';
  static const _legacyLastPushKey = 'klasify_last_push_at';
  static const _legacyLastPullKey = 'klasify_last_pull_at';
  static const _legacyKeys = [
    _legacyDeviceIdKey,
    _legacyDeviceOwnerKey,
    _legacyLastPushKey,
    _legacyLastPullKey,
  ];

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

    final claim = prefs.getString(legacyClaimKey);
    final claimedId = claim == null ? null : int.tryParse(claim);
    if (claim != null) {
      if (claimedId == null) {
        await prefs.remove(legacyClaimKey);
      } else {
        await _recoverClaim(claimedId, prefs);
      }
    }

    final stored = prefs.getString(lastScopeKey);
    final id = stored == null ? null : int.tryParse(stored);
    _current = id == null ? const LocalScope.anonymous() : LocalScope.account(id);
    AppDatabase.databaseName = _current!.fileName;

    await _migrateLegacyPrefs(_current!);
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

    if (await _tryAdopt(target)) return;

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

    await _migrateLegacyPrefs(target);
    await _reconcileReminders();
  }

  /// Renames the anonymous file into the first account that signs in.
  ///
  /// Returns false when this is not an adoption (no legacy file, the target
  /// already exists, or another account left a claim). One rename gives
  /// exactly-once semantics; there is no partial state to copy or clean up.
  Future<bool> _tryAdopt(LocalScope target) async {
    final database = AppDatabase.instance;
    if (await database.scopeFileExists(target.fileName)) return false;
    if (!await database.scopeFileExists(const LocalScope.anonymous().fileName)) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final claim = prefs.getString(legacyClaimKey);
    if (claim != null && claim != target.storageKey) return false;

    await _adopt(target, prefs);
    return true;
  }

  Future<void> _adopt(LocalScope target, SharedPreferences prefs) async {
    final database = AppDatabase.instance;
    const legacyName = 'class_schedule.db';

    // The marker survives a crash between the rename and the scope write.
    await prefs.setString(legacyClaimKey, target.storageKey);

    database.beginSwitch();
    _switching = true;
    try {
      await database.closeScope(legacyName);
      await _renameWithSiblings(
        await database.scopePath(legacyName),
        await database.scopePath(target.fileName),
      );
      AppDatabase.databaseName = target.fileName;
      _current = target;
    } finally {
      _switching = false;
      database.endSwitch();
    }

    await _migrateLegacyPrefs(target);
    await prefs.setString(lastScopeKey, target.storageKey);
    await prefs.remove(legacyClaimKey);
    DatabaseHelper.instance.notifyScopeChanged();
    await _reconcileReminders();

    debugPrint('Adopted the local schedule into ${target.fileName}.');
  }

  /// Renames the main file and any write-ahead sidecars together.
  Future<void> _renameWithSiblings(String from, String to) async {
    for (final suffix in const ['', '-wal', '-shm']) {
      final source = File('$from$suffix');
      if (await source.exists()) {
        await source.rename('$to$suffix');
      }
    }
  }

  /// Startup reconciliation for a claim left behind by a crash.
  Future<void> _recoverClaim(int userId, SharedPreferences prefs) async {
    final database = AppDatabase.instance;
    final target = LocalScope.account(userId);
    final legacyExists = await database.scopeFileExists(
      const LocalScope.anonymous().fileName,
    );
    final targetExists = await database.scopeFileExists(target.fileName);

    if (legacyExists && !targetExists) {
      // The rename never happened: resume the adoption for the claimed id.
      await _adopt(target, prefs);
      return;
    }

    if (!legacyExists && targetExists) {
      // The rename completed; only the scope write was lost.
      await prefs.setString(lastScopeKey, target.storageKey);
      await prefs.remove(legacyClaimKey);
      return;
    }

    if (!legacyExists && !targetExists) {
      await prefs.remove(legacyClaimKey);
      return;
    }

    // Both files exist, which the atomic rename makes impossible. Never
    // overwrite either one: keep the target and let the operator investigate.
    debugPrint(
      'Legacy claim $userId found both files; keeping ${target.fileName}.',
    );
    await prefs.remove(legacyClaimKey);
  }

  /// Consumes the pre-scope sync keys once, for the active account.
  ///
  /// The device id is reused only when the recorded owner is this account.
  /// Cursors are never copied: the owner key names the device-id owner, not
  /// the cursor owner, so a copied cursor could belong to someone else.
  Future<void> _migrateLegacyPrefs(LocalScope scope) async {
    final userId = scope.userId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!_legacyKeys.any(prefs.containsKey)) return;

    final owner = prefs.getInt(_legacyDeviceOwnerKey);
    final deviceId = prefs.getString(_legacyDeviceIdKey);
    if (owner == userId && deviceId != null && deviceId.isNotEmpty) {
      await DatabaseHelper.instance.seedDeviceId(deviceId);
    }

    for (final key in _legacyKeys) {
      await prefs.remove(key);
    }
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
