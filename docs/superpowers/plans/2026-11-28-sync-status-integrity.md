# Plan: sync and status integrity fixes

Spec: `docs/superpowers/specs/2026-11-28-sync-status-integrity.md`

## Step 1 — Tombstone replaced status rows (TDD)

1. Add failing tests to `test/class_status_db_test.dart`:
   - replacing a server-known range leaves a tombstone with the original id
     and server id, while the visible ranges are the split result;
   - a range that never reached the server is dropped with no tombstone;
   - `restore` (undo of a range edit) tombstones a live server-known row that
     the snapshot does not cover.
2. Run: `flutter test test/class_status_db_test.dart` (expect failures).
3. Add `_tombstonesForReplaced` to `StatusRepository` and use it in
   `setStatus`, `clearStatus`, and `restore`.
4. Re-run the test file (expect green).

## Step 2 — Scope undo to the delete stamp (TDD)

1. Add a failing test: a cleared mark with a server id survives delete + undo
   as deleted.
2. Run the test file (expect failure).
3. In `ClassRepository.restoreDeleted`, capture the class stamp before the
   update and revive only statuses with that stamp.
4. Re-run the test file (expect green).

## Step 3 — Backup scope guard (TDD)

1. Extract `backupScopeIsCurrent(captured, current)` as a small pure helper.
2. Add a failing unit test for the helper in `test/auto_backup_scope_test.dart`
   and a test that `backupNow` writes nothing when the scope changes during
   the read (inject a scope reader through the existing seam if present;
   otherwise cover the guard directly).
3. Use the guard in `backupNow` after the reads.
4. Re-run the test file (expect green).

## Step 4 — Honest status pills

1. `Settings & privacy`: replace the hardcoded `StatusPill(on: true)` with a
   widget that listens to `SyncService.instance` and maps
   syncing/ok/error to `Syncing`/`On`/`Off`.
2. `Password & security`: show `Active` only when the session is live.
3. Add widget tests with a fake sync controller if the existing test seams
   allow it; otherwise assert the pill labels from the state mapping helper.

## Step 5 — Reminder permission truth

1. Add `notificationsAllowed` to `ReminderService` (platform query, never
   throws, returns true on unsupported platforms).
2. `RemindersScreen`: on load and on resume, if the stored pref is on but the
   permission is gone, show a warning row with an "Open Android settings"
   action.
3. Widget test for the warning state using the existing fake/injection seam.

## Step 6 — Verification

- `flutter analyze --no-fatal-infos`
- `flutter test test/class_status_db_test.dart test/auto_backup_scope_test.dart test/class_status_test.dart test/weekly_schedule_view_test.dart`
- Non-benchmark suite: `flutter test --exclude-tags benchmark` (or the
  project's established non-benchmark invocation).
- Commit explicit paths only. Do not stage `.rnd`, `.taste-skill/`, or
  `mockup_*.html`.
