import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/sync/application/pull_sync.dart';
import 'package:klasify/features/sync/application/push_sync.dart';
import 'package:klasify/features/sync/application/sync_now.dart';
import 'package:klasify/features/sync/domain/entities/sync_record.dart';
import 'package:klasify/features/sync/presentation/sync_controller.dart';

import 'sync_test_fakes.dart';

void main() {
  test('the controller exposes conflicts found by the last pull', () async {
    final store = FakeLocalStore()
      ..deviceIdValue = 'device-1'
      ..lastPull = DateTime.utc(2026, 1, 1)
      ..lastPush = DateTime.utc(2026, 1, 2);
    store.localStamps['classItem:10'] = DateTime.utc(2026, 1, 6);
    final gateway = FakeRemoteGateway()
      ..pullBatch = SyncPullBatch(
        serverTime: DateTime.utc(2026, 1, 3),
        classes: [classRecord()],
        events: const [],
        classStatuses: const [],
        officeStatuses: const [],
      );
    final session = FakeSession();
    final push = PushSync(store: store, gateway: gateway, session: session);
    final pull = PullSync(store: store, gateway: gateway, session: session);
    final controller = SyncController(
      push: push,
      pull: pull,
      syncNow: SyncNow(push: push, pull: pull),
      session: session,
      autoStart: () => false,
    );

    await controller.pull();

    expect(controller.lastConflictCount, 1);
    controller.dispose();
  });
}
