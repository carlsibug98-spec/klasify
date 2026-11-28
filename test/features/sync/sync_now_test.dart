import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/sync/application/pull_sync.dart';
import 'package:klasify/features/sync/application/push_sync.dart';
import 'package:klasify/features/sync/application/sync_now.dart';
import 'package:klasify/features/sync/domain/entities/sync_result.dart';
import 'package:klasify/features/sync/domain/repositories/sync_ports.dart';

import 'sync_test_fakes.dart';

void main() {
  late FakeLocalStore store;
  late FakeRemoteGateway gateway;
  late FakeSession session;
  late SyncNow syncNow;

  setUp(() {
    store = FakeLocalStore();
    gateway = FakeRemoteGateway();
    session = FakeSession();
    syncNow = SyncNow(
      push: PushSync(store: store, gateway: gateway, session: session),
      pull: PullSync(store: store, gateway: gateway, session: session),
    );
  });

  test('a failed push does not pull', () async {
    gateway.pushError = const SyncGatewayException('HTTP 500', statusCode: 500);

    final result = await syncNow();

    expect(result.isFailure, isTrue);
    expect(gateway.pushCalls, 1);
    expect(gateway.pullCalls, 0);
  });

  test('a successful push is followed by a pull', () async {
    final result = await syncNow();

    expect(result.isSuccess, isTrue);
    expect(gateway.pushCalls, 1);
    expect(gateway.pullCalls, 1);
  });

  test('a skipped push does not pull', () async {
    session.token = null;

    final result = await syncNow();

    expect(result.outcome, SyncOutcome.skipped);
    expect(gateway.pushCalls, 0);
    expect(gateway.pullCalls, 0);
  });
}
