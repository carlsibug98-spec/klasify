import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/features/sync/data/sqlite_sync_store.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/event_item.dart';
import 'package:klasify/screens/profile/settings_privacy_screen.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databaseName =
        'offline_queue_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  setUp(() async {
    final db = DatabaseHelper.instance;
    await db.replaceAll([]);
    for (final event in await db.getAllEvents()) {
      await db.deleteEvent(event.id!);
    }
    await db.setLastPushAt(DateTime.utc(2020, 1, 1));
  });

  test('an empty schedule has no changes waiting', () async {
    expect(await SqliteSyncStore().pendingChangeCount(), 0);
  });

  test('classes and events changed since the last push are counted', () async {
    final db = DatabaseHelper.instance;
    await db.insert(
      const ClassItem(
        subject: 'Queue Class',
        room: 'Room 1',
        professor: 'Prof',
        day: 1,
        startMinutes: 540,
        endMinutes: 600,
      ),
    );
    await db.insertEvent(
      const EventItem(
        title: 'Queue Event',
        venue: 'Hall',
        date: '2026-12-01',
        startMinutes: 600,
      ),
    );

    expect(await SqliteSyncStore().pendingChangeCount(), 2);
  });

  test('the sync subtitle hides a zero queue and names a non-zero one', () {
    expect(syncNowSubtitle(0, false), 'Push and pull changes');
    expect(
      syncNowSubtitle(3, false),
      'Push and pull changes · 3 changes waiting',
    );
    expect(syncNowSubtitle(3, true), 'Syncing…');
  });
}
