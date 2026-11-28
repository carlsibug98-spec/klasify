import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/sync/application/pull_sync.dart';
import 'package:klasify/features/sync/domain/entities/sync_record.dart';
import 'package:klasify/features/sync/domain/entities/sync_record_kind.dart';
import 'package:klasify/features/sync/domain/entities/sync_result.dart';
import 'package:klasify/features/sync/domain/repositories/sync_ports.dart';

import 'sync_test_fakes.dart';

void main() {
  late FakeLocalStore store;
  late FakeRemoteGateway gateway;
  late FakeSession session;
  late PullSync pull;

  setUp(() {
    store = FakeLocalStore()
      ..deviceIdValue = 'device-9'
      ..lastPull = DateTime.utc(2026, 1, 1)
      ..lastPush = DateTime.utc(2026, 1, 2);
    gateway = FakeRemoteGateway()
      ..pullBatch = SyncPullBatch(
        serverTime: DateTime.utc(2026, 1, 3),
        classes: [classRecord()],
        events: [eventRecord()],
        classStatuses: [statusRecord()],
        officeStatuses: [officeRecord()],
      );
    session = FakeSession();
    pull = PullSync(store: store, gateway: gateway, session: session);
  });

  test(
    'pull applies every row type, prunes offices, and stores the cursor',
    () async {
      final result = await pull();

      expect(result.isSuccess, isTrue);
      expect(gateway.pullToken, 'token-7');
      expect(gateway.pullDeviceId, 'device-9');
      expect(gateway.pullSince, DateTime.utc(2026, 1, 1));
      expect(store.appliedClasses.single.serverId, 10);
      expect(store.appliedEvents.single.serverId, 20);
      expect(store.appliedStatuses.single.serverId, 30);
      expect(store.appliedOffices.single.serverId, 40);
      expect(store.pruneCalled, isTrue);
      expect(store.purgedBefore, DateTime.utc(2026, 1, 2));
      expect(store.lastPull, DateTime.utc(2026, 1, 3));
      expect(store.calls, [
        'applyClass',
        'applyEvent',
        'applyStatus',
        'applyOfficeStatus',
        'pruneUnadoptedOfficeStatuses',
        'purgeDeleted',
        'setLastPullAt',
      ]);
    },
  );

  test('an absent office list keeps the cache and skips pruning', () async {
    gateway.pullBatch = SyncPullBatch(
      serverTime: DateTime.utc(2026, 1, 3),
      classes: [classRecord()],
      events: const [],
      classStatuses: const [],
      officeStatuses: null,
    );

    final result = await pull();

    expect(result.isSuccess, isTrue);
    expect(store.pruneCalled, isFalse);
    expect(store.calls, ['applyClass', 'purgeDeleted', 'setLastPullAt']);
  });

  test('a scope move during the response writes nothing', () async {
    gateway.onPull = () => session.generation = 2;

    final result = await pull();

    expect(result.outcome, SyncOutcome.skipped);
    expect(store.calls, isEmpty);
    expect(store.lastPull, DateTime.utc(2026, 1, 1));
    expect(session.writeGenerations, [1]);
  });

  test('a gateway failure keeps the cursor', () async {
    gateway.pullError = const SyncGatewayException('HTTP 503', statusCode: 503);

    final result = await pull();

    expect(result.isFailure, isTrue);
    expect(result.message, 'Pull failed: 503');
    expect(store.calls, isEmpty);
    expect(store.lastPull, DateTime.utc(2026, 1, 1));
  });

  test('a newer local edit is reported as a conflict', () async {
    store.localStamps['${SyncRecordKind.classItem.name}:10'] =
        DateTime.utc(2026, 1, 6);

    final result = await pull();

    expect(result.isSuccess, isTrue);
    expect(result.conflicts, 1,
        reason: 'an older server row discarded for a newer local edit must be reported');
    expect(store.appliedClasses.single.serverId, 10,
        reason: 'the row is still applied so its server mapping is adopted');
  });
}
