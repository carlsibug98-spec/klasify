import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/database/database_helper.dart';
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
}
