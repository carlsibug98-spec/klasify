import '../domain/entities/sync_record_kind.dart';
import '../domain/entities/sync_result.dart';
import '../domain/repositories/sync_ports.dart';
import 'sync_failure_message.dart';

/// Pulls server changes and applies them to the pinned local scope.
///
/// Every write after the response is guarded by the generation captured before
/// the request, so a response that arrives after an account switch writes
/// nothing.
class PullSync {
  const PullSync({
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
    if (session.userId != userId) {
      return const SyncResult.skipped('The session changed.');
    }

    final generation = session.scopeGeneration;
    var conflicts = 0;

    /// Counts a row the server sent that is older than the edit on this
    /// phone. The repository's own LWW check keeps the local edit; this only
    /// makes that decision visible to the user.
    Future<void> noteConflict(
      SyncRecordKind kind,
      int serverId,
      String? incomingRaw,
    ) async {
      final local = await store.localUpdatedAt(kind, serverId);
      final incoming =
          incomingRaw == null ? null : DateTime.tryParse(incomingRaw);
      if (local != null && incoming != null && local.isAfter(incoming)) {
        conflicts++;
      }
    }

    try {
      final deviceId = await store.deviceId();
      final lastPull = await store.lastPullAt();
      final lastPush = await store.lastPushAt();

      final batch = await gateway.pull(
        token: token,
        deviceId: deviceId,
        since: lastPull,
      );

      for (final row in batch.classes) {
        await noteConflict(SyncRecordKind.classItem, row.serverId, row.updatedAt);
        if (!await session.writeIfCurrent(
          generation,
          () => store.applyClass(row),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }
      for (final row in batch.events) {
        await noteConflict(SyncRecordKind.event, row.serverId, row.updatedAt);
        if (!await session.writeIfCurrent(
          generation,
          () => store.applyEvent(row),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }
      for (final row in batch.classStatuses) {
        await noteConflict(SyncRecordKind.status, row.serverId, row.updatedAt);
        if (!await session.writeIfCurrent(
          generation,
          () => store.applyStatus(row),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }

      // A full office list was applied: any cache row still without a server
      // id is a v11 leftover the server no longer knows about. An absent list
      // means an older backend, so keep the cache untouched.
      final officeRows = batch.officeStatuses;
      if (officeRows != null) {
        for (final row in officeRows) {
          if (!await session.writeIfCurrent(
            generation,
            () => store.applyOfficeStatus(row),
          )) {
            return const SyncResult.skipped('The local scope changed.');
          }
        }
        if (!await session.writeIfCurrent(
          generation,
          store.pruneUnadoptedOfficeStatuses,
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }

      // Purge soft-deleted rows the server already accepted. Unpushed
      // tombstones survive: purging them early would silently drop the
      // deletion and let the server resurrect the row.
      if (!await session.writeIfCurrent(
        generation,
        () => store.purgeDeleted(lastPush),
      )) {
        return const SyncResult.skipped('The local scope changed.');
      }

      final serverTime = batch.serverTime;
      if (serverTime != null) {
        if (!await session.writeIfCurrent(
          generation,
          () => store.setLastPullAt(serverTime),
        )) {
          return const SyncResult.skipped('The local scope changed.');
        }
      }
      return SyncResult.success(conflicts: conflicts);
    } on SyncGatewayException catch (error) {
      return SyncResult.failed(syncFailureMessage('Pull', error));
    } catch (error) {
      return SyncResult.failed('Pull error: $error');
    }
  }
}
