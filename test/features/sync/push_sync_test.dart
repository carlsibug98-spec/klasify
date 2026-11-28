import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/sync/application/push_sync.dart';
import 'package:klasify/features/sync/domain/entities/sync_change.dart';
import 'package:klasify/features/sync/domain/entities/sync_result.dart';
import 'package:klasify/features/sync/domain/repositories/sync_ports.dart';

import 'sync_test_fakes.dart';

void main() {
  late FakeLocalStore store;
  late FakeRemoteGateway gateway;
  late FakeSession session;
  late PushSync push;

  setUp(() {
    store = FakeLocalStore()
      ..deviceIdValue = 'device-9'
      ..lastPush = DateTime.utc(2026, 1, 1)
      ..classes = [classChange(localId: 1)]
      ..events = [eventChange(localId: 2)]
      ..statuses = [statusChange(localId: 3, localClassId: 4)]
      ..classIds = {4: 40};
    gateway = FakeRemoteGateway()
      ..pushAck = SyncPushAck(
        serverTime: DateTime.utc(2026, 1, 2),
        classes: const [SyncServerMapping(localId: 1, serverId: 10)],
        events: const [SyncServerMapping(localId: 2, serverId: 20)],
        classStatuses: const [SyncServerMapping(localId: 3, serverId: 30)],
      );
    session = FakeSession();
    push = PushSync(store: store, gateway: gateway, session: session);
  });

  test('push sends every change and applies mappings and cursor', () async {
    final result = await push();

    expect(result.isSuccess, isTrue);
    expect(gateway.pushToken, 'token-7');
    expect(gateway.pushedBatch!.deviceId, 'device-9');
    expect(gateway.pushedBatch!.lastPushAt, DateTime.utc(2026, 1, 1));
    expect(gateway.pushedBatch!.classes.single.localId, 1);
    expect(gateway.pushedBatch!.events.single.localId, 2);
    expect(gateway.pushedBatch!.classStatuses.single.serverClassId, 40);
    expect(store.calls, [
      'setClassServerId',
      'setEventServerId',
      'setClassStatusServerId',
      'setLastPushAt',
    ]);
    expect(store.lastPush, DateTime.utc(2026, 1, 2));
  });

  test('push without a token is skipped and sends nothing', () async {
    session.token = null;

    final result = await push();

    expect(result.outcome, SyncOutcome.skipped);
    expect(gateway.pushCalls, 0);
    expect(store.calls, isEmpty);
  });

  test('a session change after pinning sends nothing', () async {
    session.changeUserOnPin = true;

    final result = await push();

    expect(result.outcome, SyncOutcome.skipped);
    expect(gateway.pushCalls, 0);
    expect(store.calls, isEmpty);
  });

  test('a scope move during the response writes nothing', () async {
    gateway.onPush = () => session.generation = 2;

    final result = await push();

    expect(result.outcome, SyncOutcome.skipped);
    expect(store.calls, isEmpty);
    expect(store.lastPush, DateTime.utc(2026, 1, 1));
    expect(session.writeGenerations, [1]);
  });

  test('a gateway failure keeps the cursor and reports the status', () async {
    gateway.pushError = const SyncGatewayException('HTTP 500', statusCode: 500);

    final result = await push();

    expect(result.isFailure, isTrue);
    expect(result.message, 'Push failed: 500');
    expect(store.calls, isEmpty);
    expect(store.lastPush, DateTime.utc(2026, 1, 1));
  });

  test('a non-HTTP gateway error keeps the error wording', () async {
    gateway.pushError = const SyncGatewayException('Malformed response.');

    final result = await push();

    expect(result.isFailure, isTrue);
    expect(result.message, 'Push error: Malformed response.');
  });

  test('a blocked scope is skipped before any read', () async {
    session.pinResult = false;

    final result = await push();

    expect(result.outcome, SyncOutcome.skipped);
    expect(gateway.pushCalls, 0);
    expect(store.calls, isEmpty);
  });
}
