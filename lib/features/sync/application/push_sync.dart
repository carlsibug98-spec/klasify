import '../domain/entities/sync_change.dart';
import '../domain/entities/sync_result.dart';
import '../domain/repositories/sync_ports.dart';
import 'sync_failure_message.dart';

/// Pushes local changes, then applies the server's id mappings and cursor.
///
/// The scope is pinned before any read and every post-response write is guarded
/// by the generation captured before the request. A scope switch therefore
/// writes nothing from the old account's response.
class PushSync {
  const PushSync({
    required this.store,
    required this.gateway,
    required this.session,
  });

  final SyncLocalStore store;
  final SyncRemoteGateway gateway;
  final SyncSession session;

  Future<SyncResult> call() async {
    final userId = session.userId;
    final token = await session.freshToken();
    if (token == null) return const SyncResult.skipped('Not signed in.');

    if (!await session.pinScope(userId)) {
      return const SyncResult.skipped('The local scope is not ready.');
    }
    // The body is built from the scope pinned above. If the session changed
    // while pinning, sending it with this token would put one account's rows
    // into another account on the server.
    if (session.userId != userId) {
      return const SyncResult.skipped('The session changed.');
    }

    final generation = session.scopeGeneration;
    try {
      final deviceId = await store.deviceId();
      final lastPush = await store.lastPushAt();
      final since = lastPush ?? DateTime(1970);
      final classes = await store.changedClasses(since);
      final events = await store.changedEvents(since);
      final changedStatuses = await store.changedStatuses(since);
      final classServerIds = await store.classServerIds();

      final statuses = changedStatuses
          .map(
            (status) =>
                status.withServerClassId(classServerIds[status.localClassId]),
          )
          .toList(growable: false);

      final ack = await gateway.push(
        token: token,
        batch: SyncPushBatch(
          deviceId: deviceId,
          lastPushAt: lastPush,
          classes: classes,
          events: events,
          classStatuses: statuses,
        ),
      );

      for (final mapping in ack.classes) {
        if (!await session.writeIfCurrent(
          generation,
          () => store.setClassServerId(mapping.localId, mapping.serverId),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }
      for (final mapping in ack.events) {
        if (!await session.writeIfCurrent(
          generation,
          () => store.setEventServerId(mapping.localId, mapping.serverId),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }
      for (final mapping in ack.classStatuses) {
        if (!await session.writeIfCurrent(
          generation,
          () => store.setClassStatusServerId(mapping.localId, mapping.serverId),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }

      final serverTime = ack.serverTime;
      if (serverTime != null) {
        if (!await session.writeIfCurrent(
          generation,
          () => store.setLastPushAt(serverTime),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }
      return const SyncResult.success();
    } on SyncGatewayException catch (error) {
      return SyncResult.failed(syncFailureMessage('Push', error));
    } catch (error) {
      return SyncResult.failed('Push error: $error');
    }
  }
}
