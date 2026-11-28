import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/sync/data/sync_wire_mapper.dart';
import 'package:klasify/features/sync/domain/entities/sync_change.dart';

import 'sync_test_fakes.dart';

void main() {
  test('a push body keeps the exact class, event, and status keys', () {
    final body = SyncWireMapper.pushBody(
      SyncPushBatch(
        deviceId: 'device-9',
        lastPushAt: DateTime.utc(2026, 1, 1),
        classes: [classChange()],
        events: [eventChange()],
        classStatuses: [statusChange().withServerClassId(40)],
      ),
    );

    expect(body.keys, {
      'device_id',
      'last_push_at',
      'classes',
      'events',
      'class_statuses',
    });
    expect(body['device_id'], 'device-9');
    expect(body['last_push_at'], '2026-01-01T00:00:00.000Z');

    final classRow = (body['classes'] as List).single as Map<String, dynamic>;
    expect(classRow.keys, {
      'local_id',
      'server_id',
      'subject',
      'room',
      'professor',
      'day',
      'start_minutes',
      'end_minutes',
      'deleted',
      'updated_at',
    });
    expect(classRow['deleted'], isFalse);
    expect(classRow['updated_at'], '2026-01-01T00:00:00.000Z');

    final eventRow = (body['events'] as List).single as Map<String, dynamic>;
    expect(eventRow.keys, {
      'local_id',
      'server_id',
      'title',
      'venue',
      'event_date',
      'start_minutes',
      'category',
      'department',
      'broadcast',
      'reminder_enabled',
      'lead_minutes',
      'deleted',
      'updated_at',
    });
    expect(eventRow['category'], 'school');
    expect(eventRow['reminder_enabled'], isTrue);

    final statusRow =
        (body['class_statuses'] as List).single as Map<String, dynamic>;
    expect(statusRow.keys, {
      'local_id',
      'server_id',
      'local_class_id',
      'server_class_id',
      'status',
      'start_date',
      'end_date',
      'deleted',
      'updated_at',
    });
    expect(statusRow['server_class_id'], 40);
    expect(statusRow['deleted'], isFalse);
  });

  test('a missing updated_at is filled with a UTC timestamp', () {
    final body = SyncWireMapper.pushBody(
      const SyncPushBatch(
        deviceId: 'device-9',
        lastPushAt: null,
        classes: [
          SyncClassChange(
            localId: 1,
            serverId: null,
            subject: 'Algebra',
            room: 'Room 1',
            professor: 'Prof',
            day: 1,
            startMinutes: 480,
            endMinutes: 540,
            deleted: false,
            updatedAt: null,
          ),
        ],
        events: [],
        classStatuses: [],
      ),
    );

    final row = (body['classes'] as List).single as Map<String, dynamic>;
    expect(DateTime.parse(row['updated_at'] as String).isUtc, isTrue);
  });

  test('push acks ignore mappings without integer ids', () {
    final ack = SyncWireMapper.parsePushAck({
      'server_time': '2026-01-02T00:00:00.000Z',
      'classes': [
        {'local_id': 1, 'server_id': 10},
        {'local_id': '2', 'server_id': 20},
        {'local_id': 3},
        'not a map',
      ],
      'events': <Object>[],
      'class_statuses': <Object>[],
    });

    expect(ack.serverTime, DateTime.utc(2026, 1, 2));
    expect(ack.classes.single.localId, 1);
    expect(ack.classes.single.serverId, 10);
  });

  test('pull rows keep raw timestamps and local ids', () {
    final batch = SyncWireMapper.parsePullBatch({
      'server_time': '2026-01-03T00:00:00.000Z',
      'classes': [
        {
          'id': 10,
          'local_id': 1,
          'subject': 'Algebra',
          'room': 'Room 1',
          'professor': 'Prof',
          'day': 1,
          'start_minutes': 480,
          'end_minutes': 540,
          'deleted': false,
          'updated_at': '2026-01-05T00:00:00.000Z',
        },
      ],
      'events': [
        {
          'id': 20,
          'local_id': 2,
          'title': 'Assembly',
          'venue': 'Gym',
          'event_date': '2026-12-01',
          'start_minutes': 600,
          'category': 'school',
          'department': null,
          'broadcast': false,
          'reminder_enabled': true,
          'lead_minutes': 30,
          'deleted': false,
          'updated_at': '2026-01-05T00:00:00.000Z',
        },
      ],
      'class_statuses': [
        {
          'id': 30,
          'local_id': 3,
          'class_id': 10,
          'local_class_id': null,
          'status': 'cancelled',
          'start_date': '2026-11-18',
          'end_date': '2026-11-18',
          'deleted': false,
          'updated_at': '2026-01-05T00:00:00.000Z',
        },
      ],
      'office_statuses': <Object>[],
    });

    expect(batch.serverTime, DateTime.utc(2026, 1, 3));
    expect(batch.classes.single.serverId, 10);
    expect(batch.classes.single.localId, 1);
    expect(batch.classes.single.updatedAt, '2026-01-05T00:00:00.000Z');
    expect(batch.events.single.eventDate, '2026-12-01');
    expect(batch.classStatuses.single.classId, 10);
    expect(batch.officeStatuses, isEmpty);
  });

  test('an absent office list stays null; an empty one stays empty', () {
    Map<String, dynamic> response({Object? offices}) => {
      'server_time': '2026-01-03T00:00:00.000Z',
      'classes': <Object>[],
      'events': <Object>[],
      'class_statuses': <Object>[],
      if (offices != null) 'office_statuses': offices,
    };

    expect(SyncWireMapper.parsePullBatch(response()).officeStatuses, isNull);
    expect(
      SyncWireMapper.parsePullBatch(
        response(offices: <Object>[]),
      ).officeStatuses,
      isEmpty,
    );
  });

  test('office rows without an id or name are skipped', () {
    final batch = SyncWireMapper.parsePullBatch({
      'server_time': '2026-01-03T00:00:00.000Z',
      'classes': <Object>[],
      'events': <Object>[],
      'class_statuses': <Object>[],
      'office_statuses': [
        {'id': 0, 'office_name': 'Invalid'},
        {'id': 40, 'office_name': ''},
        {'id': 41, 'office_name': 'Registrar'},
      ],
    });

    expect(batch.officeStatuses!.single.serverId, 41);
  });
}
