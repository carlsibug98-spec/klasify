import '../../models/event_item.dart';
import '../app_database.dart';
import '../db_timestamps.dart';
import '../validation/event_rules.dart';

/// Persistence for school and personal events.
class EventRepository {
  EventRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<List<EventItem>> getAll() async {
    final db = await _database.database;
    final rows = await db.query(
      'events',
      where: 'deleted = 0',
      orderBy: 'date, start_minutes',
    );
    return rows.map(EventItem.fromMap).toList();
  }

  /// Inserts one event. Returns its new id.
  Future<int> insert(EventItem event) async {
    validateEvent(event);
    final db = await _database.database;
    return db.insert('events', event.toMap()..['updated_at'] = utcStamp());
  }

  Future<int> update(EventItem event) async {
    validateEvent(event);
    if (event.id == null) {
      throw ArgumentError('Cannot update an event without an ID.');
    }
    final db = await _database.database;
    return db.update(
      'events',
      event.toMap()..['updated_at'] = utcStamp(),
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  /// Restores a recently deleted event with its original ID. Returns that ID
  /// when the row was tombstoned (contract from the re-insert era), or 0 when
  /// there was nothing to restore.
  Future<int> restoreDeleted(EventItem event) async {
    validateEvent(event);
    if (event.id == null) {
      throw ArgumentError('Cannot restore an event without its original ID.');
    }
    final db = await _database.database;
    final restored = await db.update(
      'events',
      {'deleted': 0, 'updated_at': utcStamp()},
      where: 'id = ? AND deleted = 1',
      whereArgs: [event.id],
    );
    return restored > 0 ? event.id! : 0;
  }

  /// Removes one event. Tombstones rather than hard-deletes so the deletion
  /// syncs. Returns rows affected. Events have no dependents (unlike classes
  /// and their marks), so there is nothing else to clean up.
  Future<int> delete(int id) async {
    final db = await _database.database;
    return db.update(
      'events',
      {'deleted': 1, 'updated_at': utcStamp()},
      where: 'id = ? AND deleted = 0',
      whereArgs: [id],
    );
  }

  /// Replaces the full event set atomically. Used by JSON restore; a failed
  /// import leaves the current events intact.
  Future<int> replaceAll(List<EventItem> events) async {
    for (final item in events) {
      validateEvent(item);
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      await txn.update('events', {
        'deleted': 1,
        'updated_at': utcStamp(),
      }, where: 'deleted = 0');
      var inserted = 0;
      for (final item in events) {
        await txn.insert(
          'events',
          item.toMap()
            ..remove('id')
            ..['updated_at'] = utcStamp(),
        );
        inserted++;
      }
      return inserted;
    });
  }

  /// Returns all events modified since [since] (for sync push).
  Future<List<EventItem>> getChangedSince(DateTime since) async {
    final db = await _database.database;
    final rows = await db.query(
      'events',
      where: 'updated_at IS NULL OR updated_at > ?',
      whereArgs: [since.toUtc().toIso8601String()],
      orderBy: 'updated_at',
    );
    return rows.map(EventItem.fromMap).toList();
  }

  /// Upserts an event from the server. Same matching and last-write-wins
  /// rules as `ClassRepository.upsertFromServer`.
  Future<void> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _database.database;
    final serverId = data['id'] as int;
    final map = <String, Object?>{
      'title': data['title'],
      'venue': data['venue'] ?? '',
      'date': data['event_date'],
      'start_minutes': data['start_minutes'],
      'category': data['category'] ?? 'personal',
      'department': data['department'],
      'broadcast': (data['broadcast'] as bool? ?? false) ? 1 : 0,
      'reminder_enabled': (data['reminder_enabled'] as bool? ?? true) ? 1 : 0,
      'lead_minutes': data['lead_minutes'] ?? 30,
      'deleted': (data['deleted'] as bool? ?? false) ? 1 : 0,
      'updated_at': data['updated_at'],
      'server_id': serverId,
    };

    var rows = await db.query(
      'events',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) {
      // A broadcast row's local_id belongs to the admin who posted it, so
      // it must never be matched against this device's unrelated local
      // rows. Only rows this device pushed use the id fallback.
      final isBroadcast = data['broadcast'] as bool? ?? false;
      final localFallback = data['local_id'];
      if (!isBroadcast && localFallback is int) {
        rows = await db.query(
          'events',
          where: 'id = ? AND server_id IS NULL',
          whereArgs: [localFallback],
          limit: 1,
        );
      }
    }
    if (rows.isEmpty) {
      await db.insert('events', map);
      return;
    }

    final local = rows.first;
    final localAt = parseInstant(local['updated_at']);
    final serverAt = parseInstant(data['updated_at']);
    if (localAt != null && serverAt != null && localAt.isAfter(serverAt)) {
      await db.update(
        'events',
        {'server_id': serverId},
        where: 'id = ? AND server_id IS NULL',
        whereArgs: [local['id'] as int],
      );
    } else {
      await db.update(
        'events',
        map,
        where: 'id = ?',
        whereArgs: [local['id'] as int],
      );
    }
  }

  /// Stores the server-assigned id for a pushed event.
  Future<void> setServerId(int localId, int serverId) async {
    final db = await _database.database;
    await db.update(
      'events',
      {'server_id': serverId},
      where: 'id = ? AND server_id IS NULL',
      whereArgs: [localId],
    );
  }
}
