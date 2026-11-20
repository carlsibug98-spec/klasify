# Account-Scoped Local Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every signed-in account its own SQLite cache file so no row can be read, written, or pushed under the wrong account, while keeping the pre-login schedule and detaching it back to local storage when an account is deleted.

**Architecture:** `AppDatabase` keeps one connection per file name. A new `LocalScopeService` owns which file is active, switches it at sign-in, adopts the legacy anonymous file into the first account by renaming it once, and recovers from a crash mid-adoption. Device identity and sync cursors move into a `sync_state` table inside each file; sync pins a scope generation so a response that arrives after a switch is discarded.

**Tech Stack:** Flutter/Dart, sqflite (+ sqflite_common_ffi in tests), SharedPreferences, flutter_secure_storage, local `HttpServer` for sync tests, PHP backend unchanged.

**Spec:** `docs/superpowers/specs/2026-11-20-account-scoped-cache-design.md`

## Global Constraints

- The anonymous file name stays exactly `class_schedule.db`.
- No change to `php-backend/`, the wire format, or the SQL schema of the server. The PHP harness must stay at 86 passed / 0 failed.
- TDD: write the failing test, run it, watch it fail, then implement.
- Full `flutter test` and `flutter analyze --no-fatal-infos` stay green; final task re-runs both.
- No `dart format` on whole existing files; format only new files.
- No UI or copy changes. The delete dialog and FAQ keep their current text.
- Never stage `.rnd`, `.taste-skill/`, `mockup_*.html`, `profile_mockup.html`, or any untracked artifact.
- Flutter: `C:\flutter\flutter_windows_3.44.8-stable\flutter\bin\flutter.bat`.
- Commit only the files named in each task.

## Review Focus

- **Sign-in during an in-flight push:** account A's push response must not write `server_id`s, cursors, or rows into account B. Task 7 pins it with a delayed-response test.
- **Crash between adoption rename and scope write:** the next launch must find the data and must not create a fresh empty `class_schedule.db`. Task 5 pins every row of the recovery table.
- **Detach collision:** deleting an account while a non-empty anonymous schedule already exists must not overwrite it. Task 9 pins the no-op.
- **Upgrade with a restored session:** adoption must finish before the first screen builds, and a subsequent pull must not duplicate the adopted rows. Tasks 5 and 6 pin ordering and idempotence.
- **Logout then cold start:** the last account's schedule must still be visible, not an empty anonymous file. Task 4 pins the persisted-scope restore.

---

### Task 1: LocalScope model and name-keyed connections

**Files:**
- Create: `lib/data/local_scope.dart`
- Modify: `lib/data/app_database.dart:18-31` (connection slot), `:143-151` (reset)
- Create: `test/local_scope_switch_test.dart`
- Create: `test/scope_test_support.dart`

**Interfaces:**
- Produces:
  - `LocalScope.anonymous()`, `LocalScope.account(int userId)`, `bool get isAnonymous`, `String get fileName`, `String get storageKey`, value equality.
  - `AppDatabase.scopeGeneration` (int), `beginSwitch()`, `endSwitch()`, `closeScope(String name)`, `closeAll()`, `scopeFileExists(String name)`, `scopePath(String name)`.

- [ ] **Step 1: Write the failing test**

`test/local_scope_switch_test.dart`:

```dart
test('two file names keep separate rows', () async {
  final dir = await freshDatabasesPath('scope_files_');
  addTearDown(() => dir.delete(recursive: true));
  await resetLocalData();

  DatabaseHelper.databaseName = 'a.db';
  await DatabaseHelper.instance.add(classOf('Algebra'));
  DatabaseHelper.databaseName = 'b.db';
  expect(await DatabaseHelper.instance.getAll(), isEmpty);
  await DatabaseHelper.instance.add(classOf('Biology'));
  DatabaseHelper.databaseName = 'a.db';
  expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
});

test('generation increments when the active name changes', () {
  final before = AppDatabase.instance.scopeGeneration;
  DatabaseHelper.databaseName = 'next.db';
  expect(AppDatabase.instance.scopeGeneration, before + 1);
});

test('closeScope forgets the handle and keeps other scopes open', () async {
  final dir = await freshDatabasesPath('scope_close_');
  addTearDown(() => dir.delete(recursive: true));
  await resetLocalData();
  DatabaseHelper.databaseName = 'one.db';
  await DatabaseHelper.instance.getAll();
  DatabaseHelper.databaseName = 'two.db';
  await DatabaseHelper.instance.getAll();
  await AppDatabase.instance.closeScope('one.db');
  expect(await AppDatabase.instance.scopeFileExists('one.db'), isTrue);
});
```

`test/scope_test_support.dart` provides `freshDatabasesPath(prefix)`,
`resetLocalData()` (calls `DatabaseHelper.instance.resetForTesting()` then
`LocalScopeService.instance.resetForTesting()` once Task 4 exists — for now just
the database reset), and `classOf(subject)`.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/local_scope_switch_test.dart`
Expected: FAIL — `databaseName` switches are ignored because one `_db` slot is reused.

- [ ] **Step 3: Implement**

`LocalScope` is a two-field value class. In `AppDatabase`:

```dart
static String databaseName = 'class_schedule.db';
static int _generation = 0;
static int get scopeGeneration => _generation;

final Map<String, Database> _open = {};
final Map<String, Future<Database>> _pendingOpen = {};
Completer<void>? _gate;

Future<Database> get database async {
  final gate = _gate;
  if (gate != null) await gate.future;
  final name = databaseName;
  final existing = _open[name];
  if (existing != null) return existing;
  return _pendingOpen[name] ??= _openNamed(name).then((db) {
    _open[name] = db;
    _pendingOpen.remove(name);
    return db;
  });
}
```

The `databaseName` setter bumps `_generation` when the value changes. Extract the
current `_open()` body into `Future<Database> _openNamed(String name)` and use
`name` for the path. `beginSwitch()` creates an uncompleted `Completer`;
`endSwitch()` completes and clears it. `closeScope` closes and removes the
handle. `closeAll` closes every handle. `resetForTesting` becomes `closeAll`.
`scopePath` joins `getDatabasesPath()` with the name; `scopeFileExists` uses
`databaseFactory.databaseExists`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/local_scope_switch_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/local_scope.dart lib/data/app_database.dart test/local_scope_switch_test.dart test/scope_test_support.dart
git commit -m "feat(data): key sqlite connections by file name"
```

---

### Task 2: Schema v13 adds `sync_state`

**Files:**
- Modify: `lib/data/app_database.dart:30` (version), `:40-67` (onCreate), `:68-139` (onUpgrade)
- Create: `test/app_database_v13_test.dart`

**Interfaces:**
- Produces: table `sync_state(id INTEGER PRIMARY KEY CHECK (id = 1), device_id TEXT, last_push_at TEXT, last_pull_at TEXT)` in every file.

- [ ] **Step 1: Write the failing test**

`test/app_database_v13_test.dart`:

```dart
test('v12 file gains sync_state and keeps every row', () async {
  final name = 'v12_to_v13_${DateTime.now().microsecondsSinceEpoch}.db';
  await createV12File(name);                 // helper: v12 DDL from git history
  DatabaseHelper.databaseName = name;
  expect(await DatabaseHelper.instance.getAll(), hasLength(1));
  final db = await AppDatabase.instance.database;
  final tables = await db.query('sqlite_master',
      where: "type = 'table' AND name = 'sync_state'");
  expect(tables, hasLength(1));
});

test('fresh and migrated v13 schemas are identical', () async {
  final a = await freshFileWithApp('fresh_v13_');
  final b = await createV12File('migrated_v13_...db');
  expect(await schemaOf(a), await schemaOf(b));
});
```

`createV12File` copies the v12 DDL from
`git show acd68a8:lib/data/app_database.dart` (the `CREATE TABLE` blocks and
triggers), opens it at `version: 12`, and inserts one class row. `schemaOf`
returns `SELECT name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name`.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/app_database_v13_test.dart`
Expected: FAIL — no `sync_state` table; version is 12.

- [ ] **Step 3: Implement**

Bump `version: 13`. Add the table in `onCreate` and:

```dart
if (oldVersion < 13) {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sync_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      device_id TEXT,
      last_push_at TEXT,
      last_pull_at TEXT
    )
  ''');
}
```

Keep the DDL identical in both paths so the structural comparison passes.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/app_database_v13_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/app_database.dart test/app_database_v13_test.dart
git commit -m "feat(db): add per-scope sync_state at schema v13"
```

---

### Task 3: Device identity and cursors live in `sync_state`

**Files:**
- Modify: `lib/data/repositories/sync_repository.dart`
- Modify: `lib/data/database_helper.dart` (sync facade)
- Create: `test/scope_identity_test.dart`

**Interfaces:**
- Produces on `SyncRepository` and mirrored on `DatabaseHelper`:
  - `Future<String> syncDeviceId()`
  - `Future<DateTime?> lastPushAt()`
  - `Future<DateTime?> lastPullAt()`
  - `Future<void> setLastPushAt(DateTime value)`
  - `Future<void> setLastPullAt(DateTime value)`

- [ ] **Step 1: Write the failing test**

`test/scope_identity_test.dart`:

```dart
test('a device id is minted once per file and stays stable', () async {
  final first = await DatabaseHelper.instance.syncDeviceId();
  expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
  expect(await DatabaseHelper.instance.syncDeviceId(), first);
});

test('another file gets a different device id', () async {
  DatabaseHelper.databaseName = 'b.db';
  expect(await DatabaseHelper.instance.syncDeviceId(), isNot(first));
});

test('cursors start null and are read back per file', () async {
  expect(await DatabaseHelper.instance.lastPushAt(), isNull);
  await DatabaseHelper.instance.setLastPushAt(DateTime.utc(2026, 1, 2));
  DatabaseHelper.databaseName = 'b.db';
  expect(await DatabaseHelper.instance.lastPushAt(), isNull);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/scope_identity_test.dart`
Expected: FAIL — methods do not exist.

- [ ] **Step 3: Implement**

`deviceId()` reads `sync_state` row 1; when `device_id` is null it mints 32 hex
chars with `Random.secure()` and upserts the row. Cursors read/write the same row
with `ConflictAlgorithm.ignore` for the insert so an existing row is never
cleared. Timestamps are stored as UTC ISO-8601 like `utcStamp()`. Facade methods
delegate to `_sync`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/scope_identity_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/sync_repository.dart lib/data/database_helper.dart test/scope_identity_test.dart
git commit -m "feat(data): store sync identity and cursors in the scope file"
```

---

### Task 4: `LocalScopeService` switching and lifecycle

**Files:**
- Create: `lib/services/local_scope_service.dart`
- Modify: `lib/data/database_helper.dart` (`notifyScopeChanged`)
- Modify: `test/scope_lifecycle_test.dart`

**Interfaces:**
- Produces:
  - `LocalScopeService.instance`, `LocalScope get current`, `bool get switching`, `bool get syncBlocked`, `int get generation`
  - `Future<void> initialise()`, `Future<void> ensureForUser(int? userId)`
  - `@visibleForTesting Future<void> resetForTesting()`
  - `@visibleForTesting set reminderSyncOverride(Future<void> Function()? fn)`
  - `DatabaseHelper.notifyScopeChanged()`
- Consumes: `LocalScope`, `AppDatabase`, `DatabaseHelper`, `ReminderService.sync()`.

- [ ] **Step 1: Write the failing test**

`test/scope_lifecycle_test.dart`:

```dart
test('a null user restores the persisted account scope', () async {
  SharedPreferences.setMockInitialValues({'klasify_last_scope': '7'});
  await LocalScopeService.instance.initialise();
  await LocalScopeService.instance.ensureForUser(null);
  expect(LocalScopeService.instance.current, const LocalScope.account(7));
});

test('signing in as another user switches files', () async {
  await LocalScopeService.instance.ensureForUser(7);
  await DatabaseHelper.instance.add(classOf('Algebra'));
  await LocalScopeService.instance.ensureForUser(8);
  expect(await DatabaseHelper.instance.getAll(), isEmpty);
  await LocalScopeService.instance.ensureForUser(7);
  expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
});

test('a switch notifies database listeners exactly once', () async {
  var hits = 0;
  void listener() => hits++;
  DatabaseHelper.instance.addListener(listener);
  addTearDown(() => DatabaseHelper.instance.removeListener(listener));
  await LocalScopeService.instance.ensureForUser(7);
  expect(hits, 1);
});

test('the same user again does not bump the generation', () async {
  await LocalScopeService.instance.ensureForUser(7);
  final gen = LocalScopeService.instance.generation;
  await LocalScopeService.instance.ensureForUser(7);
  expect(LocalScopeService.instance.generation, gen);
});

test('a switch reconciles reminders', () async {
  var calls = 0;
  LocalScopeService.instance.reminderSyncOverride = () async => calls++;
  addTearDown(() => LocalScopeService.instance.reminderSyncOverride = null);
  await LocalScopeService.instance.ensureForUser(7);
  expect(calls, 1);
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/scope_lifecycle_test.dart`
Expected: FAIL — `LocalScopeService` does not exist.

- [ ] **Step 3: Implement**

Rules from spec §2: serialized future chain; `ensureForUser(null)` restores the
persisted scope without switching to anonymous; a real switch calls
`AppDatabase.beginSwitch()`, changes `databaseName`, persists
`klasify_last_scope`, bumps/publishes the generation, calls
`DatabaseHelper.notifyScopeChanged()`, then `ReminderService.sync()` inside
try/catch (or `reminderSyncOverride`). `switching` is true only for the duration.
`resetForTesting` clears the chain, scope, and flags, and calls
`AppDatabase.closeAll()`.

`initialise()` for now only restores the persisted scope; Task 5 adds recovery.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/scope_lifecycle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_scope_service.dart lib/data/database_helper.dart test/scope_lifecycle_test.dart
git commit -m "feat(sync): add account-scoped local database switching"
```

---

### Task 5: Adoption by rename plus startup recovery

**Files:**
- Modify: `lib/services/local_scope_service.dart`
- Create: `test/legacy_claim_test.dart`

**Interfaces:**
- Produces: `initialise()` recovery per spec §6a; adoption inside `ensureForUser(id)`.
- Consumes: `AppDatabase.scopeFileExists`, `scopePath`, `closeScope`; prefs keys `klasify_legacy_claim`.

- [ ] **Step 1: Write the failing test**

`test/legacy_claim_test.dart`:

```dart
test('the first account adopts the anonymous file by rename', () async {
  await seedAnonymousWithOneClass();
  await LocalScopeService.instance.ensureForUser(7);
  expect(await AppDatabase.instance.scopeFileExists('class_schedule.db'), isFalse);
  expect(await AppDatabase.instance.scopeFileExists('class_schedule_u7.db'), isTrue);
  expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
});

test('an existing account file is never overwritten', () async {
  await seedAnonymousWithOneClass();
  await File(AppDatabase.instance.scopePath('class_schedule_u7.db')).writeAsString('x');
  await LocalScopeService.instance.ensureForUser(7);   // open fails -> see failure contract
});
```

Replace the second test with the functional form: create `u7` through
`ensureForUser(7)` first, add a row, then recreate the anonymous file with a
different row and call `ensureForUser(7)` again; assert the account row survives.

```dart
test('a pending claim for 7 blocks 8', () async {
  SharedPreferences.setMockInitialValues({'klasify_legacy_claim': '7'});
  await seedAnonymousWithOneClass();
  await LocalScopeService.instance.ensureForUser(8);
  expect(await DatabaseHelper.instance.getAll(), isEmpty);
  expect(await AppDatabase.instance.scopeFileExists('class_schedule.db'), isTrue);
});

test('recovery: legacy exists, target absent -> adopts for the claimed id', () async {
  SharedPreferences.setMockInitialValues({'klasify_legacy_claim': '7'});
  await seedAnonymousWithOneClass();
  await LocalScopeService.instance.initialise();
  expect(LocalScopeService.instance.current, const LocalScope.account(7));
  expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
});

test('recovery: legacy absent, target exists -> restores the claimed scope', () async {
  await LocalScopeService.instance.ensureForUser(7);     // creates u7
  SharedPreferences.setMockInitialValues({'klasify_legacy_claim': '7'});
  await LocalScopeService.instance.resetForTesting();
  await LocalScopeService.instance.initialise();
  expect(LocalScopeService.instance.current, const LocalScope.account(7));
  expect(SharedPreferences.getInstance().then((p) => p.containsKey('klasify_legacy_claim')), completion(isFalse));
});

test('recovery: neither exists -> clears the marker', () async { ... });
test('recovery: both exist -> keeps the target and clears the marker', () async { ... });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/legacy_claim_test.dart`
Expected: FAIL — no adoption.

- [ ] **Step 3: Implement**

Before a switch to a non-null user: if the target file is absent and
`class_schedule.db` exists and the claim marker is absent or equal to the user,
write the marker, `beginSwitch()`, close the anonymous handle, rename the file
and its `-wal`/`-shm` siblings, set the active name, seed `sync_state` (§5: reuse
the prefs device id only when `klasify_device_owner_id == userId`; delete the
four old prefs keys only then), persist the scope, clear the marker, release.
If the target exists, never adopt. `initialise()` runs the §6a table before
restoring the persisted scope; use the claimed id, not the session.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/legacy_claim_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_scope_service.dart test/legacy_claim_test.dart
git commit -m "feat(sync): adopt the legacy cache by rename with crash recovery"
```

---

### Task 6: Wire sign-in, startup, and the failure contract

**Files:**
- Modify: `lib/services/auth_service.dart:301-308` (`_applySignIn`), `:80-95` (restore)
- Modify: `lib/main.dart:18-30`
- Modify: `test/auth_http_test.dart` (setup)
- Modify: `test/scope_lifecycle_test.dart`

**Interfaces:**
- Consumes: `LocalScopeService.ensureForUser`, `initialise`, `syncBlocked`.
- Produces: `AuthApiException('Couldn\'t open the local schedule on this phone.', code: 'LOCAL_SCOPE_FAILED')` on a failed switch; no session saved.

- [ ] **Step 1: Write the failing test**

In `scope_lifecycle_test.dart`:

```dart
test('a failed scope switch does not save the session', () async {
  // Point the database factory at a regular file so opening fails.
  final dir = await Directory.systemTemp.createTemp('scope_fail_');
  final blocker = File(p.join(dir.path, 'not_a_dir'));
  await blocker.writeAsString('x');
  await sqflite.databaseFactory.setDatabasesPath(blocker.path);
  addTearDown(() => dir.delete(recursive: true));

  await expectLater(
    AuthService.instance.login(email: 'a@b.c', password: 'secret-123'),
    throwsA(isA<AuthApiException>()),
  );
  expect(AuthService.instance.isLoggedIn, isFalse);
});
```

The fake auth server returns a valid login response; the failure must come from
the scope switch.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/scope_lifecycle_test.dart`
Expected: FAIL — login succeeds and saves the session.

- [ ] **Step 3: Implement**

`_applySignIn`:
```dart
final id = response.user['id'];
try {
  await LocalScopeService.instance.ensureForUser(id is int ? id : null);
} catch (e, st) {
  debugPrint('Local scope switch failed: $e\n$st');
  throw const AuthApiException(
    "Couldn't open the local schedule on this phone. Try again.",
    code: 'LOCAL_SCOPE_FAILED',
  );
}
// then _session.save(...), notifyListeners()
```
`main()`:
```dart
try {
  await LocalScopeService.instance.initialise();
  await LocalScopeService.instance.ensureForUser(
    AuthService.instance.currentUser?['id'] is int
        ? AuthService.instance.currentUser!['id'] as int
        : null,
  );
} catch (e, st) {
  debugPrint('Local scope init failed: $e\n$st');
  LocalScopeService.instance.markSyncBlocked();
}
```
Keep it before `SyncService.ensureStarted()`. Add
`@visibleForTesting`-free `markSyncBlocked()` to the service (used only by main).
Update `auth_http_test.dart` `setUp` to use a temp databases path and
`LocalScopeService.instance.resetForTesting()`.

- [ ] **Step 4: Run both test files**

Run: `flutter test test/scope_lifecycle_test.dart test/auth_http_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/auth_service.dart lib/main.dart lib/services/local_scope_service.dart test/auth_http_test.dart test/scope_lifecycle_test.dart
git commit -m "feat(auth): switch local scope before saving a session"
```

---

### Task 7: SyncService runs on the active scope with generation guards

**Files:**
- Modify: `lib/services/sync_service.dart` (delete `DeviceIdentity`, `_lastPushKey`, `_lastPullKey`, `_deviceId`, `lastPushAt`, `lastPullAt`; use `DatabaseHelper` sync facade)
- Delete: `test/sync_device_identity_test.dart`
- Create: `test/sync_scope_test.dart`

**Interfaces:**
- Consumes: `DatabaseHelper.syncDeviceId/lastPushAt/lastPullAt/setLastPushAt/setLastPullAt`, `LocalScopeService.generation/switching/syncBlocked`.
- Produces: `@visibleForTesting static bool autoStartEnabled = true` on `SyncService`.

- [ ] **Step 1: Write the failing test**

`test/sync_scope_test.dart`, with a local `HttpServer`:

```dart
test('push uses the active scope device id and no cursor', () async {
  await loginAs(7);
  pushBodies.clear();
  await SyncService.instance.push();
  expect(pushBodies.single['device_id'], await DatabaseHelper.instance.syncDeviceId());
  expect(pushBodies.single['last_push_at'], isNull);
});

test('a push response that arrives after a switch writes nothing', () async {
  await loginAs(7);
  await DatabaseHelper.instance.add(classOf('Algebra'));
  final release = Completer<void>();
  serverPush = () async { await release.future; return okPush(serverIds: [99]); };

  final pending = SyncService.instance.push();
  await serverSawPush.future;
  await LocalScopeService.instance.ensureForUser(8);
  release.complete();
  await pending;

  expect(await DatabaseHelper.instance.getAll(), isEmpty);
  expect((await (await AppDatabase.instance.database)
      .query('classes', where: 'server_id IS NOT NULL')), isEmpty);
});

test('pull stops at the scope boundary', () async { ... same shape for GET ... });

test('sync is skipped while switching or blocked', () async {
  LocalScopeService.instance.markSyncBlocked();
  expect(await SyncService.instance.syncNow(), isFalse);
});
```

`loginAs(id)` drives `AuthService.login` against the fake server. Set
`SyncService.autoStartEnabled = false` before the first `SyncService.instance`
access in `setUpAll`.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/sync_scope_test.dart`
Expected: FAIL — push reads global prefs and a new device id per switch.

- [ ] **Step 3: Implement**

At the top of `push()` and `pull()`:
```dart
final scope = LocalScopeService.instance;
await scope.ensureForUser(_currentUserId);
if (scope.switching || scope.syncBlocked) return false;
final gen = scope.generation;
```
Use `DatabaseHelper.instance.syncDeviceId()` and the DB cursors. After the HTTP
response and before any write:
```dart
if (scope.generation != gen) {
  debugPrint('Sync result discarded: local scope changed mid-flight.');
  return false;
}
```
Apply the same guard before each upsert loop in `pull` and before writing the
pull cursor and `purgeDeleted`. Remove the `shared_preferences` cursor keys and
the `DeviceIdentity` class.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/sync_scope_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/sync_service.dart test/sync_scope_test.dart
git rm test/sync_device_identity_test.dart
git commit -m "feat(sync): discard results that cross a scope switch"
```

---

### Task 8: Scope-aware auto backups

**Files:**
- Modify: `lib/services/auto_backup_service.dart:37-40` (names), `:161-214` (write/read), `:229-245` (rotate), prefs keys
- Modify: `lib/services/local_scope_service.dart` (call `notifyScopeChanged`)
- Create: `test/auto_backup_scope_test.dart`

**Interfaces:**
- Produces:
  - `static String get mainFileName` and `static String get datedPrefix` (scope-derived; anonymous values unchanged)
  - `Future<void> notifyScopeChanged()`
- Consumes: `LocalScopeService.instance.current`.

- [ ] **Step 1: Write the failing test**

`test/auto_backup_scope_test.dart`:

```dart
test('account backups use the scoped file name', () async {
  await LocalScopeService.instance.ensureForUser(7);
  await DatabaseHelper.instance.add(classOf('Algebra'));
  await AutoBackupService.instance.backupNow();
  expect(await File(p.join(tempDir.path, 'auto_backups', 'klasify-auto-backup-u7.json')).exists(), isTrue);
  expect(await File(p.join(tempDir.path, 'auto_backups', 'klasify-auto-backup.json')).exists(), isFalse);
});

test('rotation never deletes another scope\'s files', () async {
  // 8 dated u7 files + 1 dated u8 file; back up in u7; the u8 file survives.
});

test('loadMainBackupFile reads the active scope', () async {
  // write one backup in u7 and one in u8; assert the decoded subject per scope.
});
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/auto_backup_scope_test.dart`
Expected: FAIL — one shared file name.

- [ ] **Step 3: Implement**

`mainFileNameFor(LocalScope)` returns `klasify-auto-backup.json` for anonymous
and `klasify-auto-backup-u<id>.json` otherwise. `datedPrefixFor` likewise
(`klasify-backup-` vs `klasify-backup-u<id>-`). `_rotate` accepts only names
matching `^<prefix>\d{8}-\d{4}\.json$` so the anonymous prefix cannot swallow
account files. Scope the two prefs keys with `_u<id>` and add
`notifyScopeChanged()` to reload them. In `LocalScopeService`, call
`AutoBackupService.instance.notifyScopeChanged()` after the reminder reconcile,
inside try/catch.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/auto_backup_scope_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/auto_backup_service.dart lib/services/local_scope_service.dart test/auto_backup_scope_test.dart
git commit -m "feat(backup): keep one automatic backup per account scope"
```

---

### Task 9: Account deletion detaches instead of destroying

**Files:**
- Modify: `lib/services/local_scope_service.dart` (`detachAccount`)
- Modify: `lib/services/auth_service.dart:141-149` (`deleteAccount`)
- Create: `test/account_delete_scope_test.dart`

**Interfaces:**
- Produces: `Future<void> detachAccount(int userId)`; `deleteAccount()` keeps the session on server failure.
- Consumes: `AppDatabase.closeScope`, `scopeFileExists`, `scopePath`; `AutoBackupService.backupNow`.

- [ ] **Step 1: Write the failing test**

`test/account_delete_scope_test.dart`:

```dart
test('a successful delete detaches the schedule to the anonymous file', () async {
  await loginAs(7);
  await DatabaseHelper.instance.add(classOf('Algebra'));
  serverDelete = () => okNoContent();
  await AuthService.instance.deleteAccount();

  expect(AuthService.instance.isLoggedIn, isFalse);
  expect(await AppDatabase.instance.scopeFileExists('class_schedule_u7.db'), isFalse);
  expect(await AppDatabase.instance.scopeFileExists('class_schedule.db'), isTrue);
  expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
});

test('scoped backups and prefs are removed', () async { ... });

test('a non-empty anonymous file is never overwritten', () async {
  await loginAs(7);
  await DatabaseHelper.instance.add(classOf('Account'));
  // switch to anonymous and add a local row, then back to 7
  await LocalScopeService.instance.ensureForUser(null);   // restores 7; use the direct API instead
  // seed class_schedule.db through AppDatabase before login in this test
  ...
});

test('a failed server delete keeps the session and the file', () async {
  serverDelete = () => reply(500, {'error': 'boom'});
  await expectLater(AuthService.instance.deleteAccount(), throwsA(isA<AuthApiException>()));
  expect(AuthService.instance.isLoggedIn, isTrue);
  expect(await AppDatabase.instance.scopeFileExists('class_schedule_u7.db'), isTrue);
});
```

For the collision test, create `class_schedule.db` with a row before
`ensureForUser(7)`, and set `klasify_legacy_claim = '7'` so adoption is blocked;
then call `detachAccount(7)` and assert both files still exist.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/account_delete_scope_test.dart`
Expected: FAIL — the account file is not renamed and the session is cleared on failure.

- [ ] **Step 3: Implement**

`detachAccount` per spec §9: abort if the anonymous file exists with rows; delete
an empty anonymous file; close and rename `u<id>` (and siblings); set scope
`anon`; delete scoped backups and prefs; `await backupNow()` in try/catch; bump
the generation.

`deleteAccount`:
```dart
final id = currentUser?['id'];
await _api.deleteAccount();               // throws on failure; session untouched
try {
  if (id is int) await LocalScopeService.instance.detachAccount(id);
} catch (e, st) {
  debugPrint('Local detach failed: $e\n$st');
}
await _session.clear();
notifyListeners();
```
Remove the `finally` that cleared the session on failure.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/account_delete_scope_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/local_scope_service.dart lib/services/auth_service.dart test/account_delete_scope_test.dart
git commit -m "feat(auth): return a deleted account's schedule to local storage"
```

---

### Task 10: Documentation and full verification

**Files:**
- Modify: `docs/APP_WALKTHROUGH.md` (local storage section)
- Modify: `CLAUDE.md:24` (verification baseline)
- Modify: `docs/superpowers/specs/2026-11-20-account-scoped-cache-design.md` (status → implemented)

- [ ] **Step 1: Update the walkthrough**

Add one paragraph: the app keeps `class_schedule.db` for local use and
`class_schedule_u<id>.db` per signed-in account; the first sign-in adopts the
local file; deleting an account returns it to `class_schedule.db`; sync identity
and cursors live in `sync_state`, so they travel with the file.

- [ ] **Step 2: Run the full suite**

Run: `flutter test 2>&1 | Tee-Object -FilePath "$env:TEMP\flutter_test_scope.log"`
Expected: all tests pass. Record the file and test counts.

- [ ] **Step 3: Run analysis**

Run: `flutter analyze --no-fatal-infos`
Expected: no issues.

- [ ] **Step 4: Run the PHP harness as a regression check**

Run: `& C:\xampp\php\php.exe php-backend\tests\run.php`
Expected: 86 passed / 0 failed (unchanged; no server edits).

- [ ] **Step 5: Update `CLAUDE.md` and the spec status, then commit**

Copy the new totals into the verification baseline line and set the spec to
`Status: implemented`.

```bash
git add CLAUDE.md docs/APP_WALKTHROUGH.md docs/superpowers/specs/2026-11-20-account-scoped-cache-design.md
git commit -m "docs: record account-scoped local storage"
```
