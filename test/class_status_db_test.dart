import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';

ClassStatusEntry mark(
  int classId,
  DayStatus status,
  String start, [
  String? end,
]) => ClassStatusEntry(
  classId: classId,
  status: status,
  startDate: start,
  endDate: end,
);

/// (start, end, status) for each saved range, in date order.
List<(String, String?, DayStatus)> ranges(List<ClassStatusEntry> rows) => [
  for (final r in rows) (r.startDate, r.endDate, r.status),
];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databaseName =
        'status_db_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  // Each class gets its own time slot on Saturday, so inserts never overlap.
  var slot = 0;
  Future<int> newClass() {
    final start = 60 + slot * 70;
    slot++;
    return DatabaseHelper.instance.insert(
      ClassItem(
        subject: 'Status Test $slot',
        room: 'Room 1',
        professor: 'Prof Test',
        day: 6,
        startMinutes: start,
        endMinutes: start + 60,
      ),
    );
  }

  test('a saved mark is read back for its class', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.cancelled, '2026-10-23', '2026-10-23'),
    );

    final statuses = await db.getClassStatuses();
    expect(ranges(statuses[id]!), [
      ('2026-10-23', '2026-10-23', DayStatus.cancelled),
    ]);
  });

  test('a one-day mark inside a longer mark keeps both sides', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(mark(id, DayStatus.notAttending, '2026-10-19'));
    await db.setClassStatus(
      mark(id, DayStatus.cancelled, '2026-10-23', '2026-10-23'),
    );

    final statuses = await db.getClassStatuses();
    expect(ranges(statuses[id]!), [
      ('2026-10-19', '2026-10-22', DayStatus.notAttending),
      ('2026-10-23', '2026-10-23', DayStatus.cancelled),
      ('2026-10-24', null, DayStatus.notAttending),
    ]);
  });

  test('clearing one day keeps the rest of a longer mark', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(mark(id, DayStatus.notAttending, '2026-10-19'));

    // Clear only Friday 23 Oct from the open-ended mark.
    final open = (await db.getClassStatuses())[id]!.single;
    await db.clearClassStatus(open, day: '2026-10-23');

    final statuses = await db.getClassStatuses();
    expect(ranges(statuses[id]!), [
      ('2026-10-19', '2026-10-22', DayStatus.notAttending),
      ('2026-10-24', null, DayStatus.notAttending),
    ]);
  });

  test('clearing the only day of a mark removes it', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.finished, '2026-10-23', '2026-10-23'),
    );

    final only = (await db.getClassStatuses())[id]!.single;
    await db.clearClassStatus(only, day: '2026-10-23');

    expect((await db.getClassStatuses()).containsKey(id), isFalse);
  });

  test('a weekday change drops marks that start on or after the cutoff', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.finished, '2026-10-01', '2026-10-01'),
    );
    await db.setClassStatus(
      mark(id, DayStatus.cancelled, '2026-11-02', '2026-11-02'),
    );

    final removed = await db.deleteStatusesFrom(id, '2026-10-29');

    expect(removed, 1);
    expect(ranges((await db.getClassStatuses())[id]!), [
      ('2026-10-01', '2026-10-01', DayStatus.finished),
    ]);
  });

  test('a mark that starts before the cutoff and runs past it is kept', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.notAttending, '2026-10-20', '2026-11-05'),
    );

    final removed = await db.deleteStatusesFrom(id, '2026-10-29');

    expect(removed, 0);
    expect(ranges((await db.getClassStatuses())[id]!), [
      ('2026-10-20', '2026-11-05', DayStatus.notAttending),
    ]);
  });

  test('deleting a class and undoing it restores its marks', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.finished, '2026-10-23', '2026-10-23'),
    );
    final item = (await db.getAll()).firstWhere((c) => c.id == id);

    final marks = await db.statusesForClass(id);
    await db.delete(id);
    expect((await db.getClassStatuses()).containsKey(id), isFalse);

    await db.restoreDeleted(item);
    await db.restoreClassStatuses(id, marks);
    expect(ranges((await db.getClassStatuses())[id]!), [
      ('2026-10-23', '2026-10-23', DayStatus.finished),
    ]);
  });

  test('replacing a server-known mark tombstones the row it replaced', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(mark(id, DayStatus.notAttending, '2026-10-19'));
    final original = (await db.getClassStatuses())[id]!.single;
    final raw = await AppDatabase.instance.database;
    // The server already knows this range.
    await raw.update(
      'class_status',
      {'server_id': 77},
      where: 'id = ?',
      whereArgs: [original.id],
    );

    await db.setClassStatus(
      mark(id, DayStatus.cancelled, '2026-10-23', '2026-10-23'),
    );

    // The split segments are live; the original row must be tombstoned so the
    // next push deletes the un-narrowed range on the server.
    expect(ranges((await db.getClassStatuses())[id]!), [
      ('2026-10-19', '2026-10-22', DayStatus.notAttending),
      ('2026-10-23', '2026-10-23', DayStatus.cancelled),
      ('2026-10-24', null, DayStatus.notAttending),
    ]);
    final tombstone = (await raw.query(
      'class_status',
      where: 'id = ?',
      whereArgs: [original.id],
    )).single;
    expect(tombstone['deleted'], 1);
    expect(tombstone['server_id'], 77);
  });

  test('a mark that never reached the server is dropped, not tombstoned', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.finished, '2026-10-23', '2026-10-23'),
    );

    await db.setClassStatus(
      mark(id, DayStatus.cancelled, '2026-10-23', '2026-10-23'),
    );

    expect(ranges((await db.getClassStatuses())[id]!), [
      ('2026-10-23', '2026-10-23', DayStatus.cancelled),
    ]);
    final raw = await AppDatabase.instance.database;
    // A tombstone without a server id would insert a deleted row server-side.
    expect(
      await raw.query('class_status', where: 'class_id = ? AND deleted = 1', whereArgs: [id]),
      isEmpty,
    );
  });

  test('undoing a range edit tombstones a server row the snapshot drops', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.finished, '2026-10-23', '2026-10-23'),
    );
    final before = await db.statusesForClass(id);
    final raw = await AppDatabase.instance.database;

    // Another device's mark lands between the edit and its undo.
    final otherId = await raw.insert('class_status', {
      'class_id': id,
      'status': 'cancelled',
      'start_date': '2026-11-02',
      'end_date': '2026-11-02',
      'server_id': 88,
      'deleted': 0,
    });

    await db.restoreClassStatuses(id, before);

    expect(ranges((await db.getClassStatuses())[id]!), [
      ('2026-10-23', '2026-10-23', DayStatus.finished),
    ]);
    final dropped = (await raw.query(
      'class_status',
      where: 'id = ?',
      whereArgs: [otherId],
    )).single;
    expect(dropped['deleted'], 1);
    expect(dropped['server_id'], 88);
  });

  test('undo after a class delete does not revive an older cleared mark', () async {
    final db = DatabaseHelper.instance;
    final id = await newClass();
    await db.setClassStatus(
      mark(id, DayStatus.finished, '2026-10-23', '2026-10-23'),
    );
    final only = (await db.getClassStatuses())[id]!.single;
    final raw = await AppDatabase.instance.database;
    await raw.update(
      'class_status',
      {'server_id': 66},
      where: 'id = ?',
      whereArgs: [only.id],
    );

    // Clear the mark: its tombstone is still waiting for the next push.
    await db.clearClassStatus(only, day: '2026-10-23');
    final item = (await db.getAll()).firstWhere((c) => c.id == id);
    await db.delete(id);

    // Undo only the class delete: the earlier clear must stay cleared.
    await db.restoreDeleted(item);

    expect((await db.getClassStatuses()).containsKey(id), isFalse);
  });
}
