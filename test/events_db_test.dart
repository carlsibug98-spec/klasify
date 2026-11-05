import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/database/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/event_item.dart';

EventItem seedEvent(
  String title, {
  String date = '2026-11-07',
  int startMinutes = 540,
  String venue = 'Test Hall',
  bool remindMe = true,
  int lead = 30,
}) => EventItem(
  title: title,
  venue: venue,
  date: date,
  startMinutes: startMinutes,
  remindMe: remindMe,
  leadMinutes: lead,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databaseName =
        'events_db_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  test('an event is stored and read back whole', () async {
    final db = DatabaseHelper.instance;
    final id = await db.insertEvent(
      seedEvent('Test Event A', startMinutes: 9 * 60 + 30, remindMe: false, lead: 15),
    );

    final events = await db.getAllEvents();
    expect(events, hasLength(1));
    final stored = events.single;
    expect(stored.id, id);
    expect(stored.title, 'Test Event A');
    expect(stored.venue, 'Test Hall');
    expect(stored.date, '2026-11-07');
    expect(stored.startMinutes, 570);
    expect(stored.remindMe, isFalse);
    expect(stored.leadMinutes, 15);
  });

  test('events read soonest first, by date then start', () async {
    final db = DatabaseHelper.instance;
    // Inserted out of order on purpose.
    await db.insertEvent(seedEvent('Test Event D', date: '2026-12-01', startMinutes: 540));
    await db.insertEvent(seedEvent('Test Event B', date: '2026-11-10', startMinutes: 660));
    await db.insertEvent(seedEvent('Test Event C', date: '2026-11-10', startMinutes: 540));

    final titles = [
      for (final e in await db.getAllEvents()) e.title,
    ];
    expect(titles, ['Test Event A', 'Test Event C', 'Test Event B', 'Test Event D']);
  });

  test('an update sticks and requires an id', () async {
    final db = DatabaseHelper.instance;
    final id = await db.insertEvent(seedEvent('Test Event E'));
    await db.updateEvent(
      EventItem(
        id: id,
        title: 'Renamed Event',
        venue: 'Another Hall',
        date: '2026-11-08',
        startMinutes: 780,
        remindMe: false,
        leadMinutes: 5,
      ),
    );
    final stored = (await db.getAllEvents()).firstWhere((e) => e.id == id);
    expect(stored.title, 'Renamed Event');
    expect(stored.date, '2026-11-08');
    expect(stored.startMinutes, 780);
    expect(stored.remindMe, isFalse);
    expect(stored.leadMinutes, 5);

    expect(
      () => db.updateEvent(
        const EventItem(title: 'No Id Event', venue: '', date: '2026-11-08', startMinutes: 540),
      ),
      throwsArgumentError,
    );
  });

  test('a deleted event restores with its original id', () async {
    final db = DatabaseHelper.instance;
    final id = await db.insertEvent(seedEvent('Undo Event', startMinutes: 600));
    await db.deleteEvent(id);

    final restoring = EventItem(
      id: id,
      title: 'Undo Event',
      venue: 'Test Hall',
      date: '2026-11-07',
      startMinutes: 600,
      remindMe: true,
      leadMinutes: 30,
    );
    await db.restoreDeletedEvent(restoring);
    expect((await db.getAllEvents()).where((e) => e.id == id), hasLength(1));

    // Delete for real so later tests keep a clean slate.
    await db.deleteEvent(id);
  });

  test('bad events never reach the table', () async {
    final db = DatabaseHelper.instance;
    expect(
      () => db.insertEvent(const EventItem(title: ' x ', venue: '', date: '2026-11-07', startMinutes: 540)),
      throwsArgumentError,
      reason: 'one blank character is not a name',
    );
    // Real parser trap: DateTime reads 2026-02-30 as March 2.
    expect(
      () => db.insertEvent(seedEvent('Bad Date', date: '2026-02-30')),
      throwsArgumentError,
      reason: 'impossible calendar dates must never enter the table',
    );
    expect(
      () => db.insertEvent(seedEvent('Bad Shape', date: '20261107')),
      throwsArgumentError,
    );
    expect(
      () => db.insertEvent(seedEvent('Bad Time', startMinutes: 1500)),
      throwsArgumentError,
    );
    expect(() => db.insertEvent(seedEvent('Bad Lead', lead: 7)), throwsArgumentError);
  });

  test('a version 5 database upgrades to version 6 and keeps its classes', () async {
    final name = 'migrate_events_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final path = p.join(await sqflite.getDatabasesPath(), name);

    // Build a version 5 database the way the app had it before events.
    final old = await sqflite.openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject TEXT NOT NULL,
            room TEXT NOT NULL,
            professor TEXT NOT NULL,
            day INTEGER NOT NULL,
            start_minutes INTEGER NOT NULL,
            end_minutes INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE class_status (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT
          )
        ''');
        await db.execute(
          'INSERT INTO classes (subject, room, professor, day, start_minutes, end_minutes) '
          "VALUES ('Old Class', '101', 'Prof Old', 5, 540, 630)",
        );
      },
    );
    await old.close();

    // The suite's earlier tests left the singleton holding ITS file: forget
    // it so the reopen below actually runs the version 5 to 6 upgrade.
    await DatabaseHelper.instance.resetForTesting();
    DatabaseHelper.databaseName = name;
    final db = DatabaseHelper.instance;
    // Opening ran the upgrade; the schedule survives untouched.
    final classes = await db.getAll();
    expect(classes.single.subject, 'Old Class');

    // The events table exists and works the moment the app opens.
    final id = await db.insertEvent(seedEvent('Upgraded Event'));
    expect(id, greaterThan(0));
    expect((await db.getAllEvents()).single.title, 'Upgraded Event');
  });
}
