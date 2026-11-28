# Mobile Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reliable background sync, notification-tap routing, a visible offline queue count and structured diagnostics without changing app behaviour otherwise.

**Architecture:** Four small changes on existing seams: `AppLogger` is a standalone utility; the queue count extends the sync local-store port; notification taps use a navigator key on `MaterialApp`; WorkManager calls the existing `SyncService` facade.

**Tech Stack:** Flutter/Dart, `logging` package, `workmanager`, `flutter_local_notifications`, existing sync facade.

**Spec:** `docs/superpowers/specs/2026-11-28-mobile-hardening-design.md`

## Global Constraints

- Keep domain layers pure; no Flutter imports under `lib/features/*/domain/`.
- `flutter analyze --no-fatal-infos` clean; non-benchmark suite green.
- Phone verification is authorised; do not ask before launching the app.

## Review Focus

- Process killed mid-sync: WorkManager callback must restore scope before syncing.
- Notification tap while app terminated: payload must still reach Today.
- Zero pending changes: the subtitle must not show a count.
- Log sink failure: diagnostics must never crash the app.
- WorkManager on unsupported platforms: registration must be skipped safely.

---

### Task 1 — AppLogger

**Files:** Create `lib/services/app_logger.dart`, `test/app_logger_test.dart`. Modify `pubspec.yaml`.

**Interfaces:** Produces `AppLogger.d/i/w/e(String scope, String message, {Object? error})`; test seam `AppLogger.sink`.

- [ ] Write failing tests: exact `[scope] message` shape, level prefix, error appended; sink receives all four levels.
- [ ] Run the test file; expect failure (class missing).
- [ ] Implement the logger with the injectable sink; default sink uses `debugPrint`.
- [ ] Run tests; commit.

### Task 2 — Offline queue count

**Files:** Modify `lib/features/sync/domain/repositories/sync_ports.dart`, `lib/features/sync/data/sqlite_sync_store.dart`, `lib/data/database_helper.dart`, `lib/data/repositories/sync_repository.dart`, `lib/services/sync_service.dart`, `lib/screens/profile/settings_privacy_screen.dart`; tests in `test/features/sync/sync_test_fakes.dart` and a new `test/offline_queue_test.dart`.

**Interfaces:** `SyncLocalStore.pendingChangeCount()` → `Future<int>`; `SyncService.pendingChangeCount`.

- [ ] Write failing tests: count sums classes/events/statuses changed since `lastPushAt`; zero renders no suffix; three renders `· 3 changes waiting`.
- [ ] Run tests; expect failures.
- [ ] Implement port + SQLite adapter + facade + subtitle.
- [ ] Run tests; commit.

### Task 3 — Notification tap routing

**Files:** Modify `lib/routes/app_router.dart`, `lib/main.dart`, `lib/services/reminder_service.dart`; create `lib/services/notification_tap_service.dart` and `test/notification_tap_test.dart`.

**Interfaces:** `handleNotificationTap(String? payload)` routes to `AppRoutes.home`; `ReminderService.consumeLaunchPayload()`.

- [ ] Write failing tests: `class:12`, `event:9`, unknown/null payloads all route home without throwing.
- [ ] Implement navigator key, callback wiring and startup consumption.
- [ ] Run tests; commit.

### Task 4 — WorkManager background sync

**Files:** Modify `pubspec.yaml`, `lib/main.dart`; create `lib/services/background_sync.dart` and `test/background_sync_test.dart`.

**Interfaces:** `runBackgroundSync()` uses an injectable `Future<bool> Function()` seam; `registerBackgroundSync()` registers a periodic job only on supported platforms.

- [ ] Write failing test: callback invokes the injected sync exactly once and propagates false.
- [ ] Implement callback + registration guarded by platform/support checks.
- [ ] Run tests; commit.

### Task 5 — Verification

- [ ] `flutter analyze --no-fatal-infos`
- [ ] Full non-benchmark suite in batches; PHP harness unchanged.
- [ ] Launch on the TECNO LJ6 and verify notification tap + settings subtitle.
