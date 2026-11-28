# Mobile hardening design

Date: 2026-11-28
Status: approved for implementation

## Context

The information-governance work closed the policy gaps. Four device-level
gaps remain and are now in scope by explicit product decision:

1. Sync stops when Android kills the app because the cadence is an in-process
   `Timer.periodic`.
2. Tapping a reminder notification has no handler, so the payload
   (`class:<id>` / `event:<id>`) is ignored.
3. The sync pill reports outcome but not how many local changes are waiting.
4. Diagnostics use ad-hoc `debugPrint` with no levels or stable shape.

Explicitly out of scope: size/startup budgets, tablet/landscape layouts and
localization (recorded in `docs/INFORMATION_GOVERNANCE.md`).

## Requirements

- Behaviour-preserving except for the new background sync schedule and the new
  UI affordances.
- No new architecture slices; changes follow the existing auth/sync seams.
- `flutter analyze --no-fatal-infos` stays clean; full non-benchmark suite green.
- Phone verification is authorised even while the user is in another app.

## Design

### Background sync

Register a WorkManager periodic job (15-minute minimum, network connected but
not unmetered) whose callback restores session + scope and calls
`SyncService.instance.syncNow()`. The existing 5-minute in-process timer stays
for foreground freshness; both paths converge on the same facade. A testable
top-level function performs the callback work behind a seam.

### Notification taps

Add a navigator key to `AppRouter` and set it on `MaterialApp`. The local
notifications plugin gets an `onDidReceiveNotificationResponse` callback that
routes any `class:`/`event:` payload to Today. Terminated-app taps are consumed
at startup via `getNotificationAppLaunchDetails()`.

### Offline queue count

Add `pendingChangeCount()` to the sync local-store port, implemented from the
existing `changed*` methods using the last successful push as the cutoff.
`SyncService` exposes the count and the Settings "Sync now" row appends
"· N changes waiting" when non-zero.

### Structured logging

Introduce `AppLogger` with `debug/info/warning/error` levels, a fixed
`[scope] message` shape and an injectable sink for tests. Migrate the
diagnostics in the services touched here (sync, reminders, auto backup, main)
to the logger. No log file and no new PII: the sink remains stderr/debug output.

## Out of scope

- ICS export, app lock/SQLCipher, runtime Sentry toggle.
- Conflict-resolution UI beyond the notice already shipped.
- Changing the documented last-write-wins policy.
