# Normalization implementation plan

Spec: `docs/superpowers/specs/2026-11-18-normalization-design.md`
Date: 2026-11-18

## Goal

Every stored relation in `docs/mysql_schema.sql` and the phone's SQLite store
is 1NF/2NF/3NF/BCNF; the two join-dependency defects (device-local ids and
cross-device marks) are removed, so the schema is also 5NF for the relations
that were decomposed, and no BCNF exception remains.

## Invariants

- Real migrations only; no invented backfill. Old `local_id` values cannot be
  attributed to a device, so they are dropped, not copied.
- App behavior is preserved: same routes, same wire names (`department` stays
  a name), same soft-delete semantics.
- TDD: a failing test precedes each behavior.
- Never stage the untracked mockups; commit explicit paths only.

## Task 1 — Post-normalization MySQL schema

**Files:** `docs/mysql_schema.sql`

1. `departments(id, name UNIQUE, created_at)`.
2. `users.department_id` FK; `CHECK role`.
3. `events.department_id` FK; `broadcast` as `VIRTUAL` generated column.
4. `office_statuses.department_id`, `scope_key` `VIRTUAL`,
   `UNIQUE (office_name, scope_key)`.
5. `class_statuses` loses `user_id`, `local_id`, `local_class_id`; index
   `(class_id, updated_at)`.
6. `password_resets(user_id PK, code_hash, created_at, ttl_seconds)`.
7. `sync_devices(device_id PK, user_id FK, ...)`.
8. `class_local_map`, `event_local_map`, `status_local_map`
   `(device_id, local_id) PK`, `UNIQUE (device_id, entity_id)`, FKs.
9. `sync_cursors(device_id PK)`.
10. `rate_limit_hits(scope, subject, hit_at)`.
11. Views unchanged; `active_*` still filter `deleted = 0`.

**Verify:** harness `db_rebuild()` parses and creates every table.

**Status (2026-11-18):** done. The harness builds `klasify_test` from this file
on every run, so all 82 tests execute against it.

## Task 2 — Failing backend tests

**Files:** `php-backend/tests/bootstrap.php`, `sync_test.php`, `auth_test.php`,
`admin_test.php`

`bootstrap.php`: `RESET_TABLES` includes `departments` before `users`;
`seed_user(['department' => 'IT'])` resolves or creates the row and stores
`department_id`. Add `seed_department(string $name): int`.

New/updated tests, all expected red before Task 3:

- device registration: `device_id` required (422), owned-by-another-account
  409, same id reused by owner ok;
- two devices of one user pushing `local_id = 1` create two classes;
- a reinstall (new device id) does not update the old install's row;
- `sync_cursors` keyed by device alone, cascade on account deletion;
- status pushed from device B for a class pulled from device A, resolved by
  `server_class_id`;
- status on an offline class resolved through `class_local_map`;
- status for another user's class skipped;
- account deletion tombstones marks through `classes.user_id`, then deletes
  devices;
- `broadcast` is generated: inserting `user_id NULL` yields 1, an owned row 0,
  and a direct write to `broadcast` fails;
- offices: duplicate school-wide name rejected by the unique key; same name in
  two departments allowed; rename keeps `id`;
- departments: `IT`/`it` one row; rename visible on read; FK blocks delete;
- password reset: old code invalid after a second forgot; 16-minute-old code
  rejected; exactly one row;
- rate limit: email/IP scopes still throttle; no `bucket` column.

**Verify:** `php-backend/tests/run.php` shows the new tests failing for the
intended reason (missing column/behavior), not parse errors.

**Status (2026-11-18):** done. `php-backend/tests/normalization_test.php` holds
14 strict-schema regressions (device ownership, per-device maps, generated
`broadcast`, the total office key, one-spelling departments, reset upsert and
expiry, rate-limit scope split, device-keyed cursors overwrite plus cascade).
They failed on the pre-change schema for the expected reasons before the
rewrite, and the harness is green at 82 after it.

## Task 3 — Departments helper

**Files:** new `php-backend/src/departments.php`; require it from
`php-backend/index.php` and `tests/bootstrap.php`.

```php
function department_id_for(?string $name, bool $create = true): ?int
function department_name_for(?int $id): ?string
```

`department_id_for` trims, returns `null` for `null`/`''`, selects
case-insensitively (`utf8mb4_unicode_ci`), inserts on miss, re-selects on a
duplicate-key race. `department_name_for` is a single-row lookup.

**Status (2026-11-18):** done, required from `index.php` and the test bootstrap.
A duplicate-key race re-selects instead of failing.

## Task 4 — Auth on department ids and the new reset table

**Files:** `php-backend/src/auth.php`

- Every user read joins `departments d ON d.id = u.department_id` and selects
  `d.name AS department`; `user_json` is unchanged.
- Register/Google: `department_id_for($name)` then insert `department_id`.
- `auth_update_me`: keep accepting `department` as a name if the body has it;
  write `department_id`.
- `auth_delete_account`: statuses via
  `UPDATE class_statuses s JOIN classes c ON c.id = s.class_id SET s.deleted = 1
  WHERE c.user_id = ?`; `DELETE FROM sync_devices WHERE user_id = ?`.
- Forgot: single `INSERT ... ON DUPLICATE KEY UPDATE code_hash = VALUES(...),
  created_at = VALUES(...), ttl_seconds = VALUES(...)`; `ttl_seconds = 900`.
- Reset: read `created_at`, `ttl_seconds`; accept only while
  `time() < strtotime($created_at . ' UTC') + ttl`; delete on success.
- Rate limits: `rate_limit_allow('login', 'email:'.strtolower($email), ...)`,
  etc. (`google` uses subject `''`).

**Verify:** auth tests green, including the 16-minute rejection.

**Status (2026-11-18):** done. Every user read joins `departments` and still
returns `department` as a name; register, Google sign-in, and profile edits all
store `department_id`; account deletion tombstones marks through the class join
and releases devices; forgot-password upserts and expiry is computed from
`created_at + ttl_seconds`.

## Task 5 — Rate-limit split

**Files:** `php-backend/src/common.php`

```php
function rate_limit_allow(string $scope, string $subject, int $max, int $windowSeconds): bool
```

Self-created DDL becomes the new shape. Count by `(scope, subject, hit_at)`.
Eight call sites updated in Task 4.

**Status (2026-11-18):** done. `rate_limit_allow` takes `(scope, subject, ...)`;
register, login, Google, forgot, and reset use `ip` / `email` / `sub` subjects.

## Task 6 — Sync rewrite

**Files:** `php-backend/src/sync.php`

Helpers:

```php
function require_device_id(array $source): string        // 422 DEVICE_REQUIRED
function register_device(int $userId, string $deviceId): void // 409 DEVICE_CONFLICT
function map_entity(string $map, string $column, string $deviceId, ?int $localId, int $entityId): void
```

- `sync_push` starts `db()->beginTransaction()` after auth/device
  registration; commits before `send_json`, rolls back on `Throwable`.
- Class: resolve by owned `server_id`, else
  `class_local_map -> classes (user_id = ?)`; upsert entity; write map.
- Event: same, plus department id resolution and scope checks; broadcast flag
  is never written (generated).
- Status: resolve class by owned `server_class_id`, else map through
  `local_class_id`; write entity + `status_local_map`.
- Cursor upsert by `device_id`.
- `sync_pull`: require/register device; join each map for `local_id` and join
  `departments` for names; statuses filter `classes.user_id`; offices return
  the full in-scope set (no `since`); no `local_class_id` in the payload.

**Verify:** Task 2 sync tests green; old behavior tests updated to seed maps
where they previously relied on `local_id`.

**Status (2026-11-18):** done. Push and pull require a valid `device_id`,
registration rejects a device owned by another account with 409, the three map
tables are written on every upsert, and pull returns this device's `local_id`
only. Status resolution prefers the owned `server_class_id` and falls back to
`local_class_id` through the map for a class created offline in the same push.

## Task 7 — Admin

**Files:** `php-backend/src/admin.php`

- `admin_caller()` joins departments for the name and returns `department_id`.
- User list joins departments; department filter by id.
- Department PATCH resolves via `department_id_for`.
- Office list/row/add/rename/retire use `department_id`; rename updates the
  row in place; uniqueness errors still 409.

**Verify:** admin tests green, including rename keeping `id`.

**Status (2026-11-18):** done. `admin_caller` returns both `department_id` and
the name; the user list and filter go through the relation; office rows store
`department_id`, resolve names with get-or-create, and a rename updates the row
in place.

## Task 8 — SQLite v12 office cache

**Files:** `lib/data/app_database.dart`

Version 12. Rebuild `office_statuses` as
`(id INTEGER PK AUTOINCREMENT, server_id INTEGER, office_name TEXT NOT NULL,
department TEXT, status ..., custom_message, updated_at)` and copy v11 rows
(`server_id` stays NULL). Partial unique index on `server_id`.

**Files:** `lib/data/repositories/office_repository.dart`

- upsert by `server_id`; else adopt a `server_id IS NULL` row with the same
  `(office_name, department)`; else insert.
- tombstone deletes by `server_id`.
- `pruneUnadopted()` removes rows still `server_id IS NULL` after a full batch.

**Files:** `lib/data/database_helper.dart`, `lib/services/sync_service.dart`

Call the prune after applying the pull's office list.

**Verify (red first):** `test/office_cache_v12_test.dart` covers v11 -> v12
preservation, adoption, rename, tombstone, sweep.

**Status (2026-11-18):** done. v11 rows survive the rebuild with `server_id`
NULL, are adopted by `(office_name, department)` on the first full pull, and
are swept if the server never mentions them. `test/office_statuses_db_test.dart`
covers the repository paths. 5 + 3 tests green.

## Task 9 — Client identity and cross-device marks

**Files:** `lib/services/sync_service.dart`

- Device id is account-scoped: store `(device_id, owner_user_id)`. Mint a new
  random 32-hex id when the signed-in user id differs; reuse otherwise.
- Push includes `server_class_id` for each status, read from the local class
  row's `server_id`.
- Pull no longer needs `local_class_id`; status upsert resolves by `class_id`.

**Files:** `lib/data/repositories/status_repository.dart`

- Resolve class by `class_id`; fall back to `local_class_id` only when present.
- Insert a new local status row when the class is known but no local row
  exists (another device's mark).

**Verify (red first):** `test/sync_device_identity_test.dart` and
`test/status_pull_cross_device_test.dart`.

**Status (2026-11-18):** done. `DeviceIdentity` stores `(device_id,
owner_user_id)`; an ownerless legacy id is replaced instead of claimed; a mark
pulled for a class this device knows is inserted with its `server_id`, and a
mark whose class is unknown is skipped. Push rows carry `local_class_id` plus
`server_class_id` (null for a class created offline in the same push).
3 + 4 tests green.

## Task 10 — MySQL migration

**Files:** new `php-backend/migrations/2026-11-18-normalize.sql`

Ordered, idempotent-at-start-once steps from the spec: departments and
backfill; `department_id` on users/events/offices; devices + cursors + maps;
drop status owner/client ids; generated `broadcast`; collapse duplicate
offices; rebuild `password_resets`; rebuild `rate_limit_hits`; drop client-id
columns. Header documents the backup command and the API-stop requirement.

**Verify:** create `klasify_migrate_rehearsal` from the pre-change schema
(`git show HEAD:docs/mysql_schema.sql`), apply the migration, compare
`SHOW CREATE TABLE` for every table against `docs/mysql_schema.sql` (allowing
only key/constraint naming), and run the harness against the migrated DB.

**Status (2026-11-18):** done. Rehearsal seeded duplicate school-wide offices,
mixed-case and padded departments, a device shared by two accounts, and used +
unused reset codes; every assertion passed. `mysqldump --no-data` of the
migrated database and a fresh `docs/mysql_schema.sql` install is now identical
(AUTO_INCREMENT values and view DEFINERs aside). Two bugs the rehearsal caught
and fixed: the backfill join compared untrimmed department text, and MariaDB
discarded `ORDER BY` inside `INSERT ... SELECT`, so device ownership now uses
`ROW_NUMBER()`. The fresh schema names the three department foreign keys and
the role check, and the debug views list columns explicitly, so both paths
produce the same physical schema. The harness always rebuilds from
`docs/mysql_schema.sql`; it cannot be pointed at another database, so the
migrated database is validated by the structural diff plus the same harness
run on that schema (82 tests).

## Task 11 — Docs and close-out

- Update `docs/mysql_schema.sql` comments, `docs/sync_api_contract.md`
  (device_id required on push and pull, `server_class_id` first with
  `local_class_id` as the offline fallback, full office payload),
  `php-backend/README.md` (migration, reset semantics),
  `CLAUDE.md` test counts if they change.
- Full `flutter test`, `flutter analyze --no-fatal-infos`, PHP harness.
- Commit explicit paths.

**Status (2026-11-18):** done. `flutter analyze --no-fatal-infos` reports no
issues; full suite passes 570 tests across 75 test files; the PHP harness
passes 82 tests. Beyond the files named above, `docs/ADMIN.md`,
`docs/DEPLOYMENT.md`, `docs/ROADMAP.md`, and `docs/APP_WALKTHROUGH.md` were
corrected where they still described `office_statuses` as school-wide only, a
rename as tombstone-plus-insert, `sync_cursors` as per user, `password_resets`
as keeping a used timestamp, or the SQLite office cache as v9/v11.

## Risks

- The migration is destructive; rehearsal is mandatory.
- Old app builds cannot sync after `device_id` becomes required; they get a
  clear 422 and must update.
- Rate-limit counters reset once.
