import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// Cross-aggregate cleanup and the per-file sync identity.
///
/// The device id and both cursors live in `sync_state` inside the active
/// scope's file. They therefore travel with the account they describe: a
/// different scope cannot inherit them, and deleting the scope deletes them.
class SyncRepository {
  SyncRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// This file's sync identity, minted on first use and stable afterwards.
  Future<String> syncDeviceId() async {
    final db = await _database.database;
    // Get-or-mint must be atomic: two concurrent syncs for the same scope
    // must never return different ids, or the server sees one scope as two
    // devices.
    return db.transaction((txn) async {
      await txn.insert(
        'sync_state',
        {'id': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final stored = (await _stateRow(txn))?['device_id'];
      if (stored is String && stored.isNotEmpty) return stored;

      final minted = _mintDeviceId();
      await txn.update(
        'sync_state',
        {'device_id': minted},
        where: 'id = 1',
      );
      return minted;
    });
  }

  /// Stores [id] if this file has no device id yet. Used once, when upgrading
  /// an install whose identity lived in prefs.
  Future<void> seedDeviceId(String id) async {
    final db = await _database.database;
    await db.insert(
      'sync_state',
      {'id': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    final stored = (await _stateRow(db))?['device_id'];
    if (stored is String && stored.isNotEmpty) return;
    await db.update('sync_state', {'device_id': id}, where: 'id = 1');
  }

  /// Clears the device id and both cursors, so the file can change hands
  /// without carrying another account's server identity.
  Future<void> resetSyncIdentity() async {
    final db = await _database.database;
    await db.insert(
      'sync_state',
      {'id': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      'sync_state',
      {'device_id': null, 'last_push_at': null, 'last_pull_at': null},
      where: 'id = 1',
    );
  }

  /// Last successful push time for this scope, or null if it never pushed.
  Future<DateTime?> lastPushAt() => _readInstant('last_push_at');

  /// Last successful pull time for this scope, or null if it never pulled.
  Future<DateTime?> lastPullAt() => _readInstant('last_pull_at');

  Future<void> setLastPushAt(DateTime value) =>
      _writeInstant('last_push_at', value);

  Future<void> setLastPullAt(DateTime value) =>
      _writeInstant('last_pull_at', value);

  Future<DateTime?> _readInstant(String column) async {
    final db = await _database.database;
    final value = (await _stateRow(db))?[column];
    return value is String ? DateTime.tryParse(value) : null;
  }

  Future<void> _writeInstant(String column, DateTime value) async {
    final db = await _database.database;
    final stamp = value.toUtc().toIso8601String();
    await db.insert(
      'sync_state',
      {'id': 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update('sync_state', {column: stamp}, where: 'id = 1');
  }

  Future<Map<String, Object?>?> _stateRow(DatabaseExecutor db) async {
    final rows = await db.query('sync_state', where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.single;
  }

  static String _mintDeviceId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  /// Hard-deletes soft-deleted rows. Only tombstones that were already
  /// pushed ([pushedBefore] cutoff, i.e. everything the last successful
  /// push covered) are safe to purge: purging an unpushed tombstone would
  /// erase the deletion locally before the server ever learns of it and
  /// the row would resurrect on the next pull.
  Future<void> purgeDeleted(DateTime? pushedBefore) async {
    if (pushedBefore == null) return;
    final db = await _database.database;
    final cutoff = pushedBefore.toUtc().toIso8601String();
    await db.delete(
      'classes',
      where: 'deleted = 1 AND updated_at IS NOT NULL AND updated_at <= ?',
      whereArgs: [cutoff],
    );
    await db.delete(
      'events',
      where: 'deleted = 1 AND updated_at IS NOT NULL AND updated_at <= ?',
      whereArgs: [cutoff],
    );
    await db.delete(
      'class_status',
      where: 'deleted = 1 AND updated_at IS NOT NULL AND updated_at <= ?',
      whereArgs: [cutoff],
    );
  }
}
