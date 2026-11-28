import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasify/features/sync/data/http_sync_gateway.dart';
import 'package:klasify/features/sync/domain/entities/sync_change.dart';
import 'package:klasify/features/sync/domain/repositories/sync_ports.dart';

import 'sync_test_fakes.dart';

void main() {
  test('push posts the mapped body with the bearer token', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'server_time': '2026-01-02T00:00:00.000Z',
          'classes': [
            {'local_id': 1, 'server_id': 10},
          ],
          'events': <Object>[],
          'class_statuses': <Object>[],
        }),
        200,
      );
    });
    final gateway = HttpSyncGateway(
      baseUrl: () => 'http://example.test',
      client: client,
    );

    final ack = await gateway.push(
      token: 'token-7',
      batch: SyncPushBatch(
        deviceId: 'device-9',
        lastPushAt: DateTime.utc(2026, 1, 1),
        classes: [classChange()],
        events: const [],
        classStatuses: const [],
      ),
    );

    expect(captured.url.toString(), 'http://example.test/sync/push');
    expect(captured.headers['Authorization'], 'Bearer token-7');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['device_id'], 'device-9');
    expect(body['last_push_at'], '2026-01-01T00:00:00.000Z');
    expect((body['classes'] as List).single['subject'], 'Algebra');
    expect(ack.classes.single.serverId, 10);
  });

  test('a non-200 push carries the status code', () async {
    final client = MockClient((request) async => http.Response('nope', 500));
    final gateway = HttpSyncGateway(
      baseUrl: () => 'http://example.test',
      client: client,
    );

    await expectLater(
      gateway.push(
        token: 'token-7',
        batch: const SyncPushBatch(
          deviceId: 'device-9',
          lastPushAt: null,
          classes: [],
          events: [],
          classStatuses: [],
        ),
      ),
      throwsA(
        isA<SyncGatewayException>().having(
          (error) => error.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });

  test('pull sends the cursor and device id and parses the rows', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'server_time': '2026-01-03T00:00:00.000Z',
          'classes': <Object>[],
          'events': <Object>[],
          'class_statuses': <Object>[],
          'office_statuses': <Object>[],
        }),
        200,
      );
    });
    final gateway = HttpSyncGateway(
      baseUrl: () => 'http://example.test',
      client: client,
    );

    final batch = await gateway.pull(
      token: 'token-7',
      deviceId: 'device 9',
      since: DateTime.utc(2026, 1, 1),
    );

    expect(captured.url.path, '/sync/pull');
    expect(captured.url.queryParameters['since'], '2026-01-01T00:00:00.000Z');
    expect(captured.url.queryParameters['device_id'], 'device 9');
    expect(captured.headers['Authorization'], 'Bearer token-7');
    expect(batch.serverTime, DateTime.utc(2026, 1, 3));
    expect(batch.officeStatuses, isEmpty);
  });
}
