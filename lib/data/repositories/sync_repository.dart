import '../app_database.dart';

/// Cross-aggregate cleanup that only runs after a successful sync push.
class SyncRepository {
  SyncRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

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
