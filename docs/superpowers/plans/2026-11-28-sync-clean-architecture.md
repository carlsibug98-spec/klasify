# Sync Clean Architecture Pilot — Implementation Plan

Spec: `docs/superpowers/specs/2026-11-28-sync-clean-architecture-design.md`

Goal: extract the sync feature into `domain -> application -> data` behind the
existing `SyncService` facade, with no behavior change and no screen edits.

Verification baseline: `flutter analyze --no-fatal-infos` clean, 609 tests
green at `b729c03`.

## Task 1 — Domain entities and ports

Files:

- `lib/features/sync/domain/entities/sync_change.dart`
- `lib/features/sync/domain/entities/sync_record.dart`
- `lib/features/sync/domain/entities/sync_result.dart`
- `lib/features/sync/domain/repositories/sync_ports.dart`

Steps:

1. Add immutable value classes for push changes and pull records.
2. Add `SyncPushBatch`, `SyncPushAck`, `SyncServerMapping`, `SyncPullBatch`.
3. Add `SyncResult` with `success`, `failure`, `skipped`, and `isSuccess`.
4. Add the three ports exactly as specified.
5. Keep every file free of Flutter and infrastructure imports.

Acceptance: `dart analyze lib/features/sync/domain` has no issues.

## Task 2 — Application tests first

Files:

- `test/features/sync/push_sync_test.dart`
- `test/features/sync/pull_sync_test.dart`
- `test/features/sync/sync_now_test.dart`
- `test/features/sync/sync_architecture_test.dart`

Fakes: in-memory `SyncLocalStore`, scripted `SyncRemoteGateway`, configurable
`SyncSession`. No `sqflite`, no HTTP server, no widget binding.

Cases:

1. Push sends the device id, cursor, and all three change lists; applies the
   three mappings and the server cursor.
2. Push with no token is skipped and sends nothing.
3. A session change after pinning is skipped and sends nothing.
4. A scope move before a guarded write writes nothing and returns skipped.
5. A gateway failure returns failure and leaves the cursor unchanged.
6. Pull applies classes, events, statuses, and offices; prunes only when the
   office list is present; purges with the last push cursor; stores the pull
   cursor.
7. A pull without an office list does not prune.
8. `SyncNow` does not pull when the push fails.
9. Architecture test: domain imports only `dart:` and same-folder files;
   presentation does not import `data`, `http`, or `sqflite`.

Acceptance: the new tests fail because the application classes do not exist.

## Task 3 — Application use cases

Files:

- `lib/features/sync/application/push_sync.dart`
- `lib/features/sync/application/pull_sync.dart`
- `lib/features/sync/application/sync_now.dart`

Steps:

1. Implement the push sequence from the spec, including both session checks and
   every guarded write.
2. Implement the pull sequence, preserving the office-present distinction and
   the purge-before-cursor order.
3. Implement `SyncNow` as push-then-pull with the push-failure stop.
4. Convert `SyncGatewayException` to a failure result; never let it escape.

Acceptance: the application tests pass.

## Task 4 — Wire mapper

File: `lib/features/sync/data/sync_wire_mapper.dart`

Steps:

1. Move the exact push body keys from `SyncService` into `SyncWireMapper`.
2. Move the status row builder and keep `buildStatusPushRow` behavior.
3. Parse pull JSON into the typed records, preserving raw timestamps, nulls,
   default values, and the `local_id` fields.
4. Add mapper tests comparing exact key sets and representative rows.

Acceptance: mapper tests pass; existing `buildStatusPushRow` tests still pass.

## Task 5 — Data adapters

Files:

- `lib/features/sync/data/http_sync_gateway.dart`
- `lib/features/sync/data/sqlite_sync_store.dart`
- `lib/features/sync/data/auth_sync_session.dart`

Steps:

1. `HttpSyncGateway` takes a base URL provider and an optional `http.Client`.
   It posts/pulls, checks 200, decodes, and delegates to the mapper.
2. `SqliteSyncStore` maps `ClassItem`, `EventItem`, and status maps to domain
   entities and back, delegating every write to `DatabaseHelper`.
3. `AuthSyncSession` implements token refresh, scope pinning, generation, and
   the guarded write, copying the existing `_writeOnPinnedScope` ordering.
4. Add adapter tests where they add value: HTTP status handling and mapper
   round-trips. The SQLite adapter is covered by the existing end-to-end sync
   tests.

Acceptance: adapter tests pass; no behavior code remains in the facade except
composition and forwarding.

## Task 6 — Presentation controller and facade

Files:

- `lib/features/sync/presentation/sync_controller.dart`
- `lib/services/sync_service.dart` (replace the implementation, keep the API)

Steps:

1. Move the timer, retry, auth listener, and `syncing` / `lastError` /
   `lastSyncAt` state into `SyncController`.
2. The controller calls the use cases and converts `SyncResult` to `bool`.
3. The facade constructs the adapters and use cases once, forwards the public
   API, forwards notifications, and keeps `autoStartEnabled`.
4. Re-export `buildStatusPushRow`.

Acceptance: `sync_scope_test.dart` passes unchanged.

## Task 7 — Verification

1. `flutter analyze --no-fatal-infos`.
2. `flutter test test/sync_scope_test.dart test/status_pull_cross_device_test.dart test/sync_mapping_integrity_test.dart test/features/sync --concurrency=1`.
3. Full suite. This machine has 7.8 GB RAM, and `flutter test --concurrency=2`
   OOM-crashed the Dart VM inside the benchmark image decoding, so the suite
   was verified in chunks: the 85 non-benchmark files at `--concurrency=2`
   (562 tests) and bench3/4/5/6/7 individually at `--concurrency=1`
   (13 + 10 + 23 + 20 + 7 tests). Total: 635 tests, 0 failures.
4. Confirm `git diff` contains only intended files and no mockups.
5. Commit explicit paths and push. Verify `HEAD == origin/main`.

## Rollback

Revert the sync feature folder and restore the pre-pilot
`lib/services/sync_service.dart`. No database, backend, or screen changes are
involved.

## Out of scope

- Auth and import migration.
- Riverpod/Bloc/get_it.
- `custom_lint` package; the architecture test is the enforcement for now.
- Any change to the sync wire contract or PHP backend.

## Status

- [x] Domain entities and ports.
- [x] Application tests written first, then the use cases.
- [x] Wire mapper, HTTP gateway, SQLite store, and auth/scope session.
- [x] Controller and facade; existing sync tests pass unchanged.
- [x] `flutter analyze --no-fatal-infos` clean.
- [x] Full suite green: 635 tests, 0 failures (chunked; see Task 7 step 3).
- [x] Commit and push.
