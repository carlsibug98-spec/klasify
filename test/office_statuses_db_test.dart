import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/office_status.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    DatabaseHelper.databaseName =
        'office_statuses_db_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  test('pulled office rows are stored, ordered and overwritten', () async {
    final db = DatabaseHelper.instance;
    expect(await db.getOfficeStatuses(), isEmpty);

    await db.upsertOfficeStatusFromServer({
      'office_name': 'guidance',
      'status': 'break',
      'custom_message': 'Back at 2pm',
      'updated_at': '2026-11-09T08:30:00.000Z',
    });
    await db.upsertOfficeStatusFromServer({
      'office_name': 'clinic',
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-09T08:31:00.000Z',
    });

    var rows = await db.getOfficeStatuses();
    expect(rows.map((r) => r['office_name']), ['clinic', 'guidance']);

    // A newer pull replaces the cached value for the same office.
    await db.upsertOfficeStatusFromServer({
      'office_name': 'guidance',
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

  test('rows without an office name are ignored', () async {
    final db = DatabaseHelper.instance;
    await db.upsertOfficeStatusFromServer({
      'status': 'closed',
      'updated_at': '2026-11-09T09:10:00.000Z',
    });

    expect(await db.getOfficeStatuses(), hasLength(2));
  });

  test('a pulled tombstone deletes the cached office row', () async {
    final db = DatabaseHelper.instance;
    await db.upsertOfficeStatusFromServer({
      'office_name': 'guidance',
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T08:30:00.000Z',
    });
    await db.upsertOfficeStatusFromServer({
      'office_name': 'clinic',
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T08:30:00.000Z',
    });

    await db.upsertOfficeStatusFromServer({
      'office_name': 'guidance',
      'status': 'open',
      'custom_message': null,
      'updated_at': '2026-11-10T09:00:00.000Z',
      'deleted': true,
    });

    final names = (await db.getOfficeStatuses()).map((r) => r['office_name']);
    expect(names, ['clinic']);
  });
}
