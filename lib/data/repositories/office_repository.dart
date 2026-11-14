import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../db_timestamps.dart';

/// The last-known office availability cache.
///
/// School-wide offices only (guidance / clinic / registrar), one row each,
/// overwritten by sync. Office statuses have no local mutations, so the
/// server value always wins.
class OfficeRepository {
  OfficeRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Cached office availability, one row per office, in display order.
  /// A pure cache of rows pulled from the server: the school-wide offices are
  /// seeded server-side when an admin opens the office screen (M8), so the
  /// strip shows real values after the first pull instead of fabricated
  /// "open" rows on a fresh offline install.
  Future<List<Map<String, Object?>>> getAll() async {
    final db = await _database.database;
    return db.query('office_statuses', orderBy: 'office_name');
  }

  /// Upserts one office row pulled from the server.
  ///
  /// Returns true when the cache changed and listeners should be notified;
  /// a row without a usable office name is ignored.
  Future<bool> upsertFromServer(Map<String, dynamic> data) async {
    final office = data['office_name'];
    if (office is! String || office.isEmpty) return false;
    final db = await _database.database;
    // Tombstone: the office was retired or renamed away on the server. The
    // local table has no deleted column, so the cached row is removed
    // outright — otherwise it would render on Today forever.
    if (data['deleted'] == true) {
      await db.delete(
        'office_statuses',
        where: 'office_name = ?',
        whereArgs: [office],
      );
      return true;
    }
    await db.insert('office_statuses', {
      'office_name': office,
      'status': data['status'] ?? 'open',
      'custom_message': data['custom_message'],
      'updated_at': data['updated_at'] ?? utcStamp(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }
}
