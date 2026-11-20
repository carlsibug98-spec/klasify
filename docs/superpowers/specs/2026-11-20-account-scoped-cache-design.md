# Account-scoped local cache — design

Date: 2026-11-20
Status: implemented (2026-11-20, rev 3)
Related: `docs/superpowers/specs/2026-11-18-normalization-design.md`

## Problem

The app keeps one SQLite file (`class_schedule.db`) for every account that has
ever signed in on the install. No local table carries an owner, all reads are
unfiltered, pulls only upsert, and the push/pull cursors plus the device id live
in global `SharedPreferences`. Consequences, all verified in code:

- Account A logs out, account B signs in: A's classes are still listed.
- On the next push, A's classes are **re-created inside B's server account**.
  The server matches classes with `WHERE user_id = ? AND id = ?`; the lookup
  misses, so it inserts. (`php-backend/src/sync.php`)
- Personal events are skipped server-side when the owner differs, but the client
  still writes the foreign `server_id` onto the local row, leaving it stranded.
- `klasify_last_push_at` / `klasify_last_pull_at` are global, so after a switch
  the delta window belongs to the wrong account.
- `DeviceIdentity.forAccount()` mints a new id on every switch, which guarantees
  the server treats the old rows as new writes.

`AuthService.logout()` only clears the session (`lib/services/auth_service.dart:144`),
and the logout dialog promises "Your schedule stays on this phone" — true for a
single account, false as soon as a second one exists.

This is not a normalization defect inside any relation. It is a scope defect:
the cache is a lossy projection that drops the tenant attribute.

## Intent

Make the local cache structurally incapable of showing or pushing one account's
rows under another account, while preserving offline-first behavior and the
existing promise that logging out does not delete the schedule.

## Goals

- Rows written under account A are never readable or pushable under account B.
- The pre-login (anonymous) schedule is adopted by the first account that signs
  in, exactly once, without loss and without duplication.
- Logging out keeps the current schedule visible and editable offline.
- Device identity and sync cursors are scoped to the same file as the rows.
- Signing back into A resumes A's data and A's cursors.
- Deleting an account removes the account's identity, server copies, and
  account-scoped backups, and returns the schedule to the local (anonymous)
  scope instead of destroying it.

## Non-goals

- Repairing rows already mixed by the old build. The old file never recorded
  which account wrote a row, so they cannot be separated. See Known limits.
- Per-person isolation for a shared phone used logged out. Isolation is per
  account, not per human.
- Encrypting the database files.
- Erasing the user's local schedule as part of account deletion. The schedule is
  detached to the local scope; erasing it is a separate, explicit action and is
  out of scope for this change.
- Changing the wire protocol. No server change is required.

## Anti-goals

- Any design where correctness depends on every query remembering an owner
  predicate.
- Any design that wipes data on logout or on account switch.

## Constraints

- Existing installs must keep their data; the anonymous file name
  `class_schedule.db` must stay.
- The full Flutter suite (609 tests) and `flutter analyze --no-fatal-infos` must
  stay green.
- TDD: each behavior gets a failing test first.
- No fabricated data or test-only branches in production paths.

## Approaches considered

**A. One database file per account (chosen).** `class_schedule.db` for the
anonymous scope, `class_schedule_u<id>.db` per account. Switching accounts
switches files; the legacy file is adopted once by the first account. Isolation
is a property of which file is open, not of query discipline. Cursors and the
device id move into a `sync_state` row inside each file.

**B. One file, `owner_id` on every cached table.** Smaller disk change, no
adoption step, but every current and future read must filter, which is the exact
failure that produced the bug. Backups and exports would also need to filter.
Rejected.

**C. Wipe on switch.** Breaks the logout promise and loses offline work.
Rejected.

## Design

### 1. Scope model

```dart
// lib/data/local_scope.dart
class LocalScope {
  const LocalScope.anonymous() : userId = null;
  const LocalScope.account(int this.userId);
  final int? userId;

  String get fileName =>
      userId == null ? 'class_schedule.db' : 'class_schedule_u$userId.db';
  String get storageKey => userId == null ? 'anon' : '$userId';
}
```

`AppDatabase` changes from one cached connection to a name-keyed map:

```dart
static String databaseName = 'class_schedule.db'; // current file, set by the scope service
final Map<String, Database> _open = {};
Future<Database> get database async {
  await _gate;                                  // a switch in progress blocks new work
  return _open[databaseName] ??= await _openNamed(databaseName);
}
```

Handles are **not** closed on account-to-account switches. Closing a connection
while a query is in flight is the only real race in this change, and keeping
handles open removes it at the cost of a few hundred KB per account. The one
exception is adoption, which must close the legacy handle before renaming it.

`AppDatabase` exposes `beginSwitch()` / `endSwitch()` (a completer that the
`database` getter awaits), `closeScope(name)`, `closeAll()` (tests), and
`scopeGeneration` (an int bumped on every active-name change).

### 2. `LocalScopeService`

New `lib/services/local_scope_service.dart`, a singleton:

```dart
LocalScope get current;
bool get switching;
int get generation;          // mirrors AppDatabase.scopeGeneration
bool get syncBlocked;        // set when startup adoption failed
Future<void> ensureForUser(int? userId);   // serialized; switches + adopts
Future<void> detachAccount(int userId);    // return that account's data to local scope
```

Rules:

- `ensureForUser(id)` with `id != null`: switch to `u<id>` if not current.
- `ensureForUser(null)`: restore the persisted scope (`anon` by default) and
  **do not** switch to anonymous. This is what keeps a logged-out cold start on
  the last account's schedule.
- Calls are serialized through a future chain; concurrent calls cannot
  interleave.
- After a switch:
  1. bump `scopeGeneration`, release the gate,
  2. `DatabaseHelper.instance.notifyScopeChanged()` (notifies listeners so open
     screens reload),
  3. `await ReminderService.instance.sync()` inside `try/catch` — a reminder
     failure must never fail the switch,
  4. `AutoBackupService.instance.notifyScopeChanged()` (reloads per-scope state).
- Persistence key: `klasify_last_scope`, values `'anon'` or `'<userId>'`.

### 3. Where the switch is triggered

The switch follows the session at the moment the session changes, not via a
listener race:

- `AuthService._applySignIn`: `await LocalScopeService.instance.ensureForUser(id)`
  **before** `_session.save(...)` and `notifyListeners()`.
- `main()`: after `restoreSession()`, call
  `await LocalScopeService.instance.initialise()` (adoption recovery, §6a), then
  `ensureForUser(currentUserId)` inside `try/catch`, before
  `SyncService.ensureStarted()` and `AutoBackupService.attach()`.
- `AuthService.logout()`: no switch.
- `AuthService.deleteAccount()`: only on success, `detachAccount(id)` and keep
  the session cleared; on failure keep both the session and the data.
- `SyncService.syncNow()`: first line is
  `await LocalScopeService.instance.ensureForUser(currentUserId)`, then
  `if (scope.switching || scope.syncBlocked) return false;`.

### 4. Sync vs. switch

A switch can happen while a push or pull is waiting on HTTP. Repository calls
resolve `AppDatabase.databaseName` at call time, so without a guard the tail of
account A's sync would write into account B's file.

Rule: **the sync pins a generation and checks it before applying anything.**

- `SyncService` captures `final gen = scope.generation` after `ensureForUser`.
- `push`: build the body from the current scope, then after the response and
  before any `setServerId` / cursor write, `if (scope.generation != gen) return false;`
- `pull`: check the same guard before each batch of upserts, and before writing
  the pull cursor. Any change aborts the remainder and leaves the cursor
  untouched (the next sync re-pulls; upserts are idempotent by `server_id`).
- `logout()` does not change the generation, so a response that arrives after a
  logout is still applied to the same account's file — correct.
- No mutex and no waiting on the network: login never blocks on a slow sync, and
  there is no lock ordering between the scope service and `SyncService`.

### 5. Schema v13: `sync_state`

Inside every scope file:

```sql
CREATE TABLE sync_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  device_id TEXT,
  last_push_at TEXT,
  last_pull_at TEXT
)
```

One row or none. `SyncRepository` gains `deviceId()` (get-or-mint),
`lastPushAt()`, `lastPullAt()`, `setLastPushAt()`, `setLastPullAt()`.
`SyncService` stops reading `SharedPreferences` for cursors and stops using
`DeviceIdentity`; the class and its two prefs keys are removed.

One-shot migration of the old prefs, run by `LocalScopeService` the first time a
scope is active after upgrade (never in `onUpgrade`, which would run it on the
legacy file and then lose it when that file is renamed):

- **Device id**: reuse `klasify_device_id` only when
  `klasify_device_owner_id == userId`. Otherwise mint a fresh id. This matches
  today's rule (an ownerless or foreign id is never reused) and avoids a 409
  `DEVICE_CONFLICT` from the server.
- **Cursors are never copied.** `klasify_device_owner_id` records the device-id
  owner, not the cursor owner, and the old app minted a new id before the first
  push of a new account — so the cursors can belong to a different account.
  Starting at null is safe: the first push sends every row, classes and events
  reconcile by `server_id`, and the first pull is a full pull.
- After the device id is consumed (or deliberately skipped because the owner
  differs), delete `klasify_device_id`, `klasify_device_owner_id`,
  `klasify_last_push_at`, `klasify_last_pull_at`.
- If the active scope is anonymous, leave the keys alone.

Why a table instead of prefs: the cursor is part of the scope's identity. Putting
it in the file means it switches with the data and cannot be stale by
construction.

### 6. Adoption of the anonymous file

Adoption is a **rename**, not a copy. One atomic filesystem operation gives
exactly-once semantics; there is no partial state to verify or resume.

Trigger, evaluated in `ensureForUser(id)`:

1. the target `class_schedule_u<id>.db` does not exist, and
2. `class_schedule.db` exists, and
3. `klasify_legacy_claim` is absent or equals `<id>`.

Procedure:

1. Persist `klasify_legacy_claim = '<id>'` (survives a crash mid-adoption).
2. `beginSwitch()`; close the legacy handle for `class_schedule.db`.
3. Rename `class_schedule.db` → `class_schedule_u<id>.db`, and the `-wal` /
   `-shm` siblings if present.
4. Set the active name to the target, seed `sync_state` (§5), persist
   `klasify_last_scope`.
5. Delete `klasify_legacy_claim`; release the gate.

Failure of any step: keep `klasify_legacy_claim`, do not delete anything, and
rethrow (§7).

### 6a. Startup recovery for the adoption window

The rename and the scope write are two separate stores, so a crash between them
must not be allowed to create a fresh empty `class_schedule.db` on the next
launch. `LocalScopeService.initialise()` runs before the first `ensureForUser`
and reconciles from `klasify_legacy_claim`:

| legacy file | target file | action |
|---|---|---|
| exists | absent | resume the adoption for the claimed id (steps 2–5) |
| absent | exists | rename completed: persist `klasify_last_scope = '<claim>'`, clear the marker |
| absent | absent | clear the marker |
| exists | exists | impossible (rename is atomic); keep the target, clear the marker, log |

Recovery uses the claimed id, not the current session, so it also works on a
logged-out cold start.

Guards:

- A different account cannot adopt while `klasify_legacy_claim` names another
  user: condition 3 fails, so B's file is created empty and A's data stays put.
- A target that already exists is never overwritten.
- After a successful rename the legacy name no longer exists, so no second
  account can ever claim it.
- No "done" marker is needed: the absence of the legacy file is the marker.

### 7. Failure contract

- **Sign-in**: if `ensureForUser` throws, the session is **not** saved and the
  login fails with the existing error surface. Saving the session while writes
  still target the previous scope would recreate the original bug.
- **Startup**: `main()` catches, logs, keeps the persisted scope, sets
  `syncBlocked`, and launches. The schedule stays readable; sync resumes on the
  next successful `ensureForUser` (next launch or next sign-in).
- **Reminders / auto backup after a switch**: caught and logged; never fail the
  switch and never roll it back.
- **Adoption failure**: covered above; the legacy file is untouched and the
  login fails, so no mixed state is ever active.
- **Corrupt scope file**: existing open-failure behavior is unchanged; the file
  is not deleted automatically.

### 8. Side systems

- **Reminders**: `ReminderService.sync()` is a reconcile — it schedules the rows
  of the active file and cancels ids that are no longer present. Run it after
  every switch. Notification ids collide across accounts by design; the
  reconcile handles it.
- **Auto backup**: file names become scope-qualified. Anonymous keeps
  `klasify-auto-backup.json` / `klasify-backup-<stamp>.json` (so existing files
  still rotate). Account A gets `klasify-auto-backup-u7.json` /
  `klasify-backup-u7-<stamp>.json`. Rotation matches only the active scope's
  pattern; the anonymous pattern must not swallow `klasify-backup-u7-...`
  (match the timestamp shape, not just the prefix). `lastBackupAt` /
  `lastBackupCount` prefs keys get the scope suffix, and the restore screen reads
  the active scope's main file.
- **Office cache**: duplicated per scope. It is a cache; each scope pulls its
  own copy. No change to `office_statuses`.

### 9. Account deletion: detach, don't destroy

`AuthService.deleteAccount()` removes the account's identity and server copies,
then returns the schedule to the local scope. It does **not** delete the
schedule: the timetable is the user's primary artifact, the app's contract
already says phone data stays, and there is no bulk-undo if it is destroyed.

On success, `LocalScopeService.detachAccount(id)`:

1. `beginSwitch()`. If `class_schedule.db` exists **and has rows**, abort: log,
   release the gate, and leave the account scope active. A local schedule already
   occupies the anonymous slot, and overwriting it would be the data loss this
   section exists to prevent. If it exists and is empty, delete it.
2. Close `class_schedule_u<id>.db`, then rename it to `class_schedule.db`
   (plus `-wal` / `-shm` siblings if present).
3. Set the active scope to anonymous and persist `klasify_last_scope = 'anon'`.
4. Delete `klasify-auto-backup-u<id>.json`, every
   `klasify-backup-u<id>-*.json`, and the scoped backup prefs keys. They are
   redundant copies of a schedule that now lives in the anonymous scope.
5. Trigger one anonymous backup so the safety net exists under the new scope.
6. Bump the generation; release the gate.

On server failure, nothing is detached and the session is **kept** (today's
`finally` logs the user out on a failed delete; that changes), so the user can
retry.

The delete-account dialog and the FAQ already promise "The data on this phone
stays until you remove it" (`personal_details_screen.dart:123`,
`profile_sheets.dart:345`). Detaching keeps that promise exactly, so **no copy
changes**. No new UI.

A user who wants the schedule gone as well needs a separate destructive action;
that is a follow-up, not part of account deletion.

## Migration and upgrade

- Existing installs: `class_schedule.db` remains the anonymous file. If a
  session is restored at upgrade, `ensureForUser(id)` adopts it into
  `class_schedule_u<id>.db` before the first screen builds.
- If the install already held two accounts, the file holds both accounts' rows
  and all of it goes to the account that signs in first. This cannot be undone
  automatically (see Known limits).
- Schema v13 is additive: one table. The v12→v13 migration and a fresh v13
  install must be structurally identical, asserted the same way as v12.

## Testing (TDD, failing test first)

New files:

1. `test/local_scope_switch_test.dart` — anonymous/A/B isolation; return to A
   restores A's rows; A's rows are invisible in B; office cache is per scope.
2. `test/legacy_claim_test.dart` — adopts by rename; skipped when the target
   exists; a pending claim for A blocks B; an interrupted claim resumes; each row
   of the §6a recovery table; the legacy file is untouched on failure.
3. `test/scope_identity_test.dart` — device id is reused only when the prefs
   owner matches; cursors always start null; both are per scope; switching back
   to A restores A's row; `purgeDeleted` uses the active cursor.
4. `test/scope_lifecycle_test.dart` — logged-out cold start restores the
   persisted scope; logout keeps it; sign-in as another user switches;
   successful delete removes only that scope.
5. `test/account_delete_scope_test.dart` — a successful delete renames the
   account file to `class_schedule.db`, removes the scoped backups and prefs,
   writes a fresh anonymous backup, and leaves the schedule intact; a collision
   with an existing non-empty anonymous file leaves the account file untouched;
   a failed server delete keeps the session and every file.
6. `test/sync_scope_test.dart` — after A→B the push body contains only B's rows,
   B's device id, B's `last_push_at`; a push response that arrives after a switch
   writes nothing; a pull that starts before a switch stops at the boundary.
7. `test/auto_backup_scope_test.dart` — per-scope names; rotation never deletes
   another scope's files; restore reads the active file.
8. `test/app_database_v13_test.dart` — v12→v13 adds `sync_state` and preserves
   rows; migrated and fresh schemas are identical.

Updates: `test/auth_http_test.dart` (sign-in now switches scope; point the
database factory at a temp dir and reset the service), `test/sync_device_identity_test.dart`
(replaced by `scope_identity_test.dart`), and any test asserting on the old
prefs cursor keys.

Verification: `flutter analyze --no-fatal-infos`; full `flutter test`; PHP
harness unchanged (86 tests) as a regression check.

## Known limits

- Rows already merged by the old build cannot be attributed. On a device that
  ran two accounts before this change, the whole legacy file is adopted by the
  next account. The remedy is manual: delete the wrongly created rows in the
  app or on the server.
- A second person using the phone while logged out sees and edits the last
  account's schedule. Same as today; account isolation starts at sign-in.
- Per-account files are never garbage-collected. A successful account deletion
  returns the file to the anonymous name, so the only file that can be orphaned
  is one whose anonymous slot was already occupied (logged, not overwritten).
- Account deletion keeps the schedule by design; a full erase needs a separate
  action that does not exist yet.
- Backups are per scope, so restoring A's backup requires being in A's scope.
  After a detach, A's scoped backups are gone and the anonymous one holds the
  same schedule.

## Calls I made (check these while reading)

1. Per-account files over `owner_id` columns.
2. Logout keeps the last scope instead of switching to anonymous.
3. `sync_state` lives in the database, not in scoped prefs.
4. Adoption is a rename, guarded by a `klasify_legacy_claim` marker plus a
   startup recovery step, not a copy.
5. Cursors are never migrated; the device id is reused only when its owner
   matches.
6. Account deletion detaches the schedule to the anonymous scope instead of
   wiping it, deletes the account-scoped backups, and keeps the session on a
   failed server delete.
7. Sync pins a scope generation instead of holding a mutex.
