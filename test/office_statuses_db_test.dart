import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/office_status.dart';

void main() {
  var counter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    counter += 1;
    DatabaseHelper.databaseName =
        'office_statuses_db_test_${DateTime.now().microsecondsSinceEpoch}_$counter.db';
    await DatabaseHelper.instance.resetForTesting();
  });

  test('pulled office rows are stored, ordered and overwritten', () async {
    final db = DatabaseHelper.instance;
    expect(await db.getOfficeStatuses(), isEmpty);

    await db.upsertOfficeStatusFromServer({
      'id': 2,
      'office_name': 'guidance',
      'department': null,
      'status': 'break',
      'custom_message': 'Back at 2pm',
      'updated_at': '2026-11-09T08:30:00.000Z',
    });
    await db.upsertOfficeStatusFromServer({
      'id': 1,
      'office_name': 'clinic',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-09T08:31:00.000Z',
    });

    var rows = await db.getOfficeStatuses();
    expect(rows.map((r) => r['office_name']), ['clinic', 'guidance']);

    // A newer pull replaces the cached value for the same server row.
    await db.upsertOfficeStatusFromServer({
      'id': 2,
      'office_name': 'guidance',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-09T09:00:00.000Z',
    });

    rows = await db.getOfficeStatuses();
    expect(rows, hasLength(2));
    final guidance = rows.firstWhere((r) => r['office_name'] == 'guidance');
    expect(guidance['status'], 'open');
    expect(guidance['custom_message'], isNull);

    final parsed = rows.map(OfficeStatus.fromMap).toList();
    expect(parsed.first.displayName, 'Clinic');
    expect(parsed.last.displayName, 'Guidance');
  });

  test('rows without a server id or an office name are ignored', () async {
    final db = DatabaseHelper.instance;
    final before = await db.getOfficeStatuses();

    await db.upsertOfficeStatusFromServer({
      'office_name': 'library',
      'status': 'closed',
      'updated_at': '2026-11-09T09:10:00.000Z',
    });
    await db.upsertOfficeStatusFromServer({
      'id': 99,
      'status': 'closed',
      'updated_at': '2026-11-09T09:10:00.000Z',
    });

    expect(await db.getOfficeStatuses(), hasLength(before.length));
  });

  test('a pulled tombstone deletes the cached office row', () async {
    final db = DatabaseHelper.instance;
    await db.upsertOfficeStatusFromServer({
      'id': 5,
      'office_name': 'guidance',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T08:30:00.000Z',
    });
    await db.upsertOfficeStatusFromServer({
      'id': 6,
      'office_name': 'clinic',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T08:30:00.000Z',
    });

    await db.upsertOfficeStatusFromServer({
      'id': 5,
      'office_name': 'registrar',
      'department': null,
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': true,
    });

    final remaining = await db.getOfficeStatuses();
    final names = remaining.map((r) => r['office_name']);
    expect(names, isNot(contains('registrar')));
    expect(names, contains('clinic'));
  });
}
