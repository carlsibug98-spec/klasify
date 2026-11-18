import '../app_database.dart';
import '../db_timestamps.dart';

/// The last-known office availability cache.
///
/// Rows are keyed by the server's id. A pull may carry school-wide offices and
/// the caller's department ones; both are cached. Office statuses have no
/// local mutations, so the server value always wins.
class OfficeRepository {
  OfficeRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Cached office availability, one row per office, in display order.
  Future<List<Map<String, Object?>>> getAll() async {
    final db = await _database.database;
    return db.query('office_statuses', orderBy: 'office_name');
  }

  /// Upserts one office row pulled from the server.
  ///
  /// Returns true when the cache changed and listeners should be notified.
  /// A row without the server's id is ignored: the id is the row's identity,
  /// and a name alone cannot tell a rename from a different office.
  Future<bool> upsertFromServer(Map<String, dynamic> data) async {
    final serverId = data['id'];
    if (serverId is! int || serverId <= 0) return false;
    final office = data['office_name'];
    if (office is! String || office.isEmpty) return false;
    final department = data['department'] is String
        ? data['department'] as String
        : null;
    final db = await _database.database;

    // Tombstone: the office was retired on the server. Deleting by id works
    // even when the tombstone carries the new name of a renamed office.
    if (data['deleted'] == true) {
      final removed = await db.delete(
        'office_statuses',
        where: 'server_id = ?',
        whereArgs: [serverId],
      );
      return removed > 0;
    }

    final values = <String, Object?>{
      'server_id': serverId,
      'office_name': office,
      'department': department,
      'status': data['status'] ?? 'open',
      'custom_message': data['custom_message'],
      'updated_at': data['updated_at'] ?? utcStamp(),
    };

    final known = await db.query(
      'office_statuses',
      columns: ['id'],
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (known.isNotEmpty) {
      await db.update(
        'office_statuses',
        values,
        where: 'id = ?',
        whereArgs: [known.single['id']],
      );
      return true;
    }

    // A version-11 row has no server id. Adopt it on the first pull so the
    // cached value (and its local row) survives instead of duplicating.
    final legacy = await db.query(
      'office_statuses',
      columns: ['id'],
      where:
          "server_id IS NULL AND office_name = ? "
          "AND IFNULL(department, '') = ?",
      whereArgs: [office, department ?? ''],
      limit: 1,
    );
    if (legacy.isNotEmpty) {
      await db.update(
        'office_statuses',
        values,
        where: 'id = ?',
        whereArgs: [legacy.single['id']],
      );
      return true;
    }

    await db.insert('office_statuses', values);
    return true;
  }

  /// Removes cached rows the previous schema left behind. Called after a full
  /// pull has had the chance to adopt every row the server still knows.
  Future<int> pruneUnadopted() async {
    final db = await _database.database;
    return db.delete('office_statuses', where: 'server_id IS NULL');
  }
}
