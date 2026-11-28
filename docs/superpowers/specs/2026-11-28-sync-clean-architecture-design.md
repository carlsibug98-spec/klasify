# Sync Clean Architecture Pilot — Design

Date: 2026-11-28
Status: Approved for implementation
Scope: `sync` only. Auth, import, and the rest of the app keep their current
structure until this pilot proves the seam.

## Problem

Klasify is layered in practice but not in rule. `SyncService` is a 455-line
singleton that owns HTTP, JSON wire shaping, SQLite reads and writes, account
scope pinning, auth session checks, timers, retries, and UI notification. The
same file is the composition root, the application logic, the data layer, and
the controller. That makes the riskiest feature in the app the hardest one to
test without a real database, a real HTTP server, and the auth singleton.

The rest of the app does not need a big-bang rewrite. The sync feature is the
right pilot because it has the most side effects and the existing tests already
pin its behavior.

## Goals

1. Put a real dependency rule around one feature:

   ```
   presentation -> application -> domain <- data
   ```

   `domain` is pure Dart. `application` depends only on `domain` ports.
   `data` implements the ports. `presentation` never imports `data`.

2. Preserve every observable behavior:
   - the `/sync/push` and `/sync/pull` request and response shapes,
   - the account-scope pinning and "write nothing after a switch" guard,
   - push-before-pull ordering and the skip-pull-on-push-failure rule,
   - background cadence, retry backoff, and `syncing` / `lastError` state,
   - the existing `SyncService.instance` API used by screens and tests.

3. Make the push and pull rules testable with in-memory fakes and no Flutter,
   `sqflite`, or `http` imports.

4. Enforce the boundary with a test that fails if `domain` imports Flutter or
   infrastructure packages, or if `presentation` imports `data`.

## Non-goals

- No schema change, no PHP change, no sync payload change.
- No state-management package (Riverpod, Bloc, get_it). Constructor injection
  and one composition root are enough for this slice.
- No feature packages, no `melos`, no versioned modules.
- No UI redesign. Screens keep calling the facade.
- No migration of auth or schedule import in this pass.

## Target structure

```
lib/
  features/
    sync/
      domain/
        entities/
          sync_change.dart        push-side entities
          sync_record.dart        pull-side entities
          sync_result.dart        success / failure / skipped
        repositories/
          sync_ports.dart         SyncLocalStore, SyncRemoteGateway, SyncSession
      application/
        push_sync.dart
        pull_sync.dart
        sync_now.dart
      data/
        sync_wire_mapper.dart     domain <-> JSON, exact wire contract
        http_sync_gateway.dart    SyncRemoteGateway over package:http
        sqlite_sync_store.dart    SyncLocalStore over DatabaseHelper
        auth_sync_session.dart    SyncSession over AuthService/LocalScope
      presentation/
        sync_controller.dart      timers, retry, ChangeNotifier state
  services/
    sync_service.dart             composition root + compatibility facade
```

### Dependency rules

| Layer | May import | Must not import |
|---|---|---|
| `domain` | `dart:` core only | Flutter, `http`, `sqflite`, `path_provider`, `shared_preferences`, `data`, `presentation` |
| `application` | `domain` | Flutter, `http`, `sqflite`, `data`, `presentation` |
| `data` | `domain`, `dart:`, packages | `presentation` |
| `presentation` | `domain`, `application`, Flutter | `data`, `http`, `sqflite` |
| `services/sync_service.dart` | all of the above | nothing (it is the composition root) |

The architecture test reads the source files and asserts these rules. It is a
plain `flutter_test` file, so no new lint package or build step is required.

## Domain model

### Push side

- `SyncClassChange` — local id, server id, subject, room, professor, day,
  start/end minutes, deleted, updated at.
- `SyncEventChange` — local id, server id, title, venue, date, start minutes,
  category name, department, broadcast, reminder flag, lead minutes, deleted,
  updated at.
- `SyncStatusChange` — local id, server id, local class id, resolved server
  class id, status, start/end date, deleted, updated at.
- `SyncPushBatch` — device id, last push cursor, the three change lists.
- `SyncServerMapping` — local id to server id.
- `SyncPushAck` — the three mapping lists plus server time.

The domain entities carry values, not wire keys. `data/sync_wire_mapper.dart`
owns the exact JSON keys, the `deleted` bool/int conversions, and the
`updated_at` fallback to "now".

### Pull side

- `SyncClassRecord`, `SyncEventRecord`, `SyncStatusRecord`,
  `SyncOfficeRecord` — typed rows with the fields the local upserts consume.
- `SyncPullBatch` — server time, the four row lists, and a nullable office list
  so "field absent" stays distinguishable from "present and empty".

Timestamps stay as the server's raw strings on pull records. The local
repositories already parse and compare them; re-encoding a `DateTime` could
change the wire format or the last-write-wins result.

### Result

`SyncResult` is a small value object: `success`, `failure(message)`, or
`skipped(message)`. `isSuccess` is true only for `success`. The facade converts
it back to the existing `bool` return values and keeps `lastError` behavior.

## Ports

```dart
abstract interface class SyncLocalStore {
  Future<String> deviceId();
  Future<DateTime?> lastPushAt();
  Future<DateTime?> lastPullAt();
  Future<List<SyncClassChange>> changedClasses(DateTime since);
  Future<List<SyncEventChange>> changedEvents(DateTime since);
  Future<List<SyncStatusChange>> changedStatuses(DateTime since);
  Future<Map<int, int>> classServerIds();
  Future<void> setClassServerId(int localId, int serverId);
  Future<void> setEventServerId(int localId, int serverId);
  Future<void> setClassStatusServerId(int localId, int serverId);
  Future<void> applyClass(SyncClassRecord row);
  Future<void> applyEvent(SyncEventRecord row);
  Future<void> applyStatus(SyncStatusRecord row);
  Future<void> applyOfficeStatus(SyncOfficeRecord row);
  Future<void> pruneUnadoptedOfficeStatuses();
  Future<void> purgeDeleted(DateTime? pushedBefore);
  Future<void> setLastPushAt(DateTime value);
  Future<void> setLastPullAt(DateTime value);
}

abstract interface class SyncRemoteGateway {
  Future<SyncPushAck> push({
    required String token,
    required SyncPushBatch batch,
  });
  Future<SyncPullBatch> pull({
    required String token,
    required String deviceId,
    required DateTime? since,
  });
}

abstract interface class SyncSession {
  int? get userId;
  bool get isLoggedIn;
  Future<String?> freshToken();
  Future<bool> pinScope(int? userId);
  int get scopeGeneration;
  Future<bool> writeIfCurrent(int generation, Future<void> Function() write);
  void addSessionListener(void Function() listener);
  void removeSessionListener(void Function() listener);
}
```

`writeIfCurrent` is the port form of the existing `_writeOnPinnedScope`:
check the generation, await the database gate, check again, then write. The
application layer cannot accidentally write to a file that was swapped in
while the response was in flight. Readiness is already answered by `pinScope`
(switching or blocked) and by the session-user re-check, so the port has no
separate `scopeIsCurrent` member.

## Use cases

### `PushSync`

1. Read the session user id and a fresh token. No token -> skipped.
2. Pin the local scope to that user. A switch in progress or a blocked scope ->
   skipped.
3. Re-check the session user id. A change -> skipped, and no request is sent.
4. Read the device id, last push cursor, changed rows, and class server ids.
5. Build `SyncPushBatch`; the status rows resolve their class server id from
   the map.
6. POST through the gateway.
7. Apply each returned mapping through `writeIfCurrent`. If the scope moved,
   stop and return skipped.
8. Apply the server cursor through `writeIfCurrent`.
9. Return success; the gateway failure becomes a failure result.

### `PullSync`

1. Same token, pin, and session checks.
2. Read device id, last pull cursor, and last push cursor.
3. GET through the gateway.
4. Apply classes, events, statuses, and office rows, each through
   `writeIfCurrent`.
5. If the office list was present, prune unadopted office rows.
6. Purge soft-deleted rows accepted before the last successful push.
7. Apply the server cursor.
8. Return success; any failure becomes a failure result.

### `SyncNow`

Push first. If the push is not successful, return it without pulling. This is
the existing data-loss guard: applying server rows while unserved local edits
are stuck can overwrite them.

## Data adapters

- `HttpSyncGateway` owns `package:http`, the base URL, the auth header, status
  codes, and JSON decoding. It throws `SyncGatewayException` on non-200 or a
  response that is not a JSON object; a row that violates the expected shape
  surfaces as a failure result from the use case. Either way no local write
  happens and the cursor stays put.
- `SqliteSyncStore` owns `DatabaseHelper` and the model-to-entity mapping. It
  is the only sync file that imports `sqflite` or the models.
- `AuthSyncSession` owns `AuthService`, `LocalScopeService`, and `AppDatabase`.
  It is the only sync file that touches the auth and scope singletons.
- `SyncWireMapper` owns the exact key names. `buildStatusPushRow` stays exported
  from `services/sync_service.dart` for the existing cross-device test, but its
  body delegates to the mapper.

## Presentation and facade

`SyncController` is a `ChangeNotifier` that owns the 5-minute timer, the
exponential retry timer, `syncing`, `lastError`, and `lastSyncAt`. It depends on
the three use cases and the `SyncSession` port, nothing else.

`services/sync_service.dart` stays the public singleton:

- constructs the adapters and use cases once,
- forwards `push`, `pull`, `syncNow`, `syncing`, `lastError`, `lastSyncAt`,
- forwards auth session changes to the controller,
- keeps `autoStartEnabled` as a static test hook,
- re-exports `buildStatusPushRow`.

This keeps `main.dart`, the four screens, and all existing tests unchanged.

## Scope-safety invariants

These are the behaviors the pilot must not lose. Each gets an application test
with fakes and is already covered end-to-end by `sync_scope_test.dart`.

1. A token is resolved before the scope is pinned.
2. The scope is pinned to the session user before any read.
3. The session user is re-checked after pinning; a mismatch sends nothing.
4. Every write after the response is guarded by the generation captured before
   the request.
5. A guarded write that observes a moved scope writes nothing and aborts the
   operation.
6. A failed push means no pull.

## Testing

1. **New application tests** with fakes:
   - push builds the batch, applies mappings and cursor, and reports success;
   - a session change after pinning sends no request;
   - a scope move during the response writes nothing and returns skipped;
   - a gateway failure becomes a failure result;
   - pull applies all four row types, prunes offices only when the list is
     present, and purges before the cursor;
   - `SyncNow` does not pull after a failed push.
2. **Architecture test** over the source tree: domain purity, presentation does
   not import data.
3. **Existing tests unchanged**: `sync_scope_test.dart`,
   `status_pull_cross_device_test.dart`, `sync_mapping_integrity_test.dart`.
4. `flutter analyze --no-fatal-infos`.
5. Full suite at the final commit.

## Migration and rollback

The migration is one commit series behind the facade. If the pilot regresses,
revert the feature folder and restore the previous `SyncService` body; no
schema, backend, or screen changes are involved. The existing tests are the
acceptance gate at every step.

## Risks

- **Wire drift.** The mapper is the highest-risk file. It is pinned by the
  existing HTTP-server tests and by new mapper tests that compare exact keys.
- **Scope races.** The guard moves behind a port but keeps the same ordering:
  generation check, database gate, generation check, write.
- **Double notification.** The controller notifies on `syncing`; the facade
  forwards it once. Existing screens do not listen to the facade, so the risk
  is limited to any future listener.
- **Over-extraction.** Only sync moves. If the pilot does not make sync easier
  to test and reason about, stop and do not roll it out to auth or import.
