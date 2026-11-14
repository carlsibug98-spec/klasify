import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_status.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test('a version 4 database upgrades and keeps its marks', () async {
    final name = 'migrate_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final path = p.join(await sqflite.getDatabasesPath(), name);

    // Build a version 4 database the way the app created it before version 5.
    final old = await sqflite.openDatabase(
      path,
      version: 4,
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
            class_id INTEGER PRIMARY KEY,
            status TEXT NOT NULL CHECK (status IN ('not_attending', 'cancelled')),
            start_date TEXT NOT NULL,
            end_date TEXT
          )
        ''');
        await db.execute(
          "INSERT INTO classes (subject, room, professor, day, start_minutes, end_minutes) "
          "VALUES ('Old Class', '101', 'Prof Old', 5, 540, 630)",
        );
        await db.execute(
          "INSERT INTO class_status (class_id, status, start_date, end_date) "
          "VALUES (1, 'cancelled', '2026-10-23', '2026-10-23')",
        );
      },
    );
    await old.close();

    // Opening the app's database now runs the version 4 to 5 upgrade.
    DatabaseHelper.databaseName = name;
    final db = DatabaseHelper.instance;
    final statuses = await db.getClassStatuses();
    expect(statuses[1]!.single.status, DayStatus.cancelled);
    expect(statuses[1]!.single.endDate, '2026-10-23');

    // The upgraded table accepts the new status and more than one range per class.
    await db.setClassStatus(
      const ClassStatusEntry(
        classId: 1,
        status: DayStatus.finished,
        startDate: '2026-10-24',
        endDate: '2026-10-24',
      ),
    );
    expect((await db.getClassStatuses())[1]!.length, 2);
  });
}
