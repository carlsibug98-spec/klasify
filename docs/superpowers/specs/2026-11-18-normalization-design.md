# Full normalization of the Klasify schema

Date: 2026-11-18
Status: proposed

## Problem

Nine defects. Two of them lose data.

1. **Device-local ids are stored in user-scoped rows.** `classes.local_id`,
   `events.local_id`, `class_statuses.local_id`, and
   `class_statuses.local_class_id` identify a row on *one* phone, but they live
   in rows owned by a *user*. Push matches on `(user_id, local_id)` with no
   device in the key (`sync.php:161,303,318`). A reinstall clears
   SharedPreferences, so local ids restart at 1 and a new device id is minted;
   the next push then matches the previous install's row and overwrites it. The
   pull mirrors the defect: the server echoes the remembered `local_id` and the
   client treats it as its own (`class_repository.dart:253`,
   `status_repository.dart:184`). `local_id -> server_id` depends on
   `(user, device)`, not `user`; it is a relation, not an attribute.

2. **A mark on a class pulled to a second device is silently dropped.** The
   status push resolves its class only through `classes.local_id`
   (`sync.php:303`), which holds the *creating* device's local id. The second
   device's local class id is different, so the class lookup fails and the
   status is skipped. Every status created on a synced class from another
   device is lost.

3. **Status ownership is transitively dependent on the class.**
   `class_statuses.user_id` repeats `classes.user_id`. Nothing enforces that
   the two agree, so a mark can claim an owner that is not its class's owner.

4. **Department names are repeated as text** in `users`, `events`, and
   `office_statuses` (`users:30`, `events:81`, `office_statuses:104`). Renaming
   a department means rewriting every row, a typo silently creates a second
   scope, and no foreign key can catch either.

5. **Offices have two identities.** The server keys an office by its surrogate
   `id` plus `(office_name, department)`; the phone keys its cache by the
   mutable `office_name`. A rename is a delete plus an insert on the phone, and
   the cached `department` is dropped because the table has no column for it.

6. **`events.broadcast` is a derived flag.** Every write sets
   `broadcast = (user_id IS NULL)` (`sync.php:218,226`), so `user_id` determines
   a non-prime attribute. Storing both lets a row disagree with itself.

7. **The office candidate key is not enforced.** `UNIQUE (office_name,
   department)` cannot stop a second school-wide office with the same name,
   because SQL treats every `NULL` as distinct. The schema comment admits this
   and the backend compensates with an explicit duplicate query.

8. **`rate_limit_hits.bucket` is a packed value.** Rows hold
   `'forgot:ip:1.2.3.4'` or `'login:email:a@b.c'`: a policy name and a subject
   crammed into one column. Nothing ever splits it, but the domain is not
   atomic and the index is a string prefix rather than two facts.

9. **`password_resets` stores values it does not own.** `expires_at` is
   `created_at + 15 minutes`, so it is functionally dependent on a non-key
   column. `used_at` is never written: the row is deleted on a successful
   reset, so the column is always `NULL`.

## Decision

### 1. Device identity is a relation

A device id becomes account-scoped, and the server records which account owns
it:

```sql
CREATE TABLE sync_devices (
  device_id    VARCHAR(64)     NOT NULL PRIMARY KEY,
  user_id      BIGINT UNSIGNED NOT NULL,
  created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_seen_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_devices_user (user_id)
) ENGINE=InnoDB;
```

The phone mints a new random 128-bit id whenever the signed-in account changes
and stores the owning user id next to it. Logging back into the same account
reuses the id, so its local mappings survive. Logging into a different account
on the same install mints a different id, so the two accounts can never claim
each other's mapping rows.

Push and pull both register the device. If an id is already registered to a
different user, the request fails with `409 DEVICE_CONFLICT` instead of quietly
reassigning it. `device_id` becomes a required, validated field on both routes.

`sync_cursors` loses its redundant `user_id` and becomes one row per device:

```sql
CREATE TABLE sync_cursors (
  device_id    VARCHAR(64) NOT NULL PRIMARY KEY,
  last_push_at DATETIME(3) NULL,
  last_pull_at DATETIME(3) NULL,
  created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  FOREIGN KEY (device_id) REFERENCES sync_devices(device_id) ON DELETE CASCADE
) ENGINE=InnoDB;
```

`device_id -> user_id` is now a fact of `sync_devices` (where `device_id` is the
key), not a hidden assumption behind a composite primary key.

### 2. Local-id identity becomes its own relation

Three typed map tables, one per syncable entity, so each one carries real
foreign keys:

```sql
CREATE TABLE class_local_map (
  device_id VARCHAR(64)     NOT NULL,
  local_id  BIGINT          NOT NULL,
  class_id  BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (device_id, local_id),
  UNIQUE KEY uq_class_map_row (device_id, class_id),
  FOREIGN KEY (device_id) REFERENCES sync_devices(device_id) ON DELETE CASCADE,
  FOREIGN KEY (class_id)  REFERENCES classes(id) ON DELETE CASCADE
) ENGINE=InnoDB;
```

`event_local_map(device_id, local_id, event_id)` and
`status_local_map(device_id, local_id, class_status_id)` have the same shape.
The only determinants in each map are its two keys, so each map is in BCNF
without a documented exception.

One polymorphic map table was rejected: it cannot carry a foreign key to three
parents, and the whole point of this change is enforcement.

The four client-id columns are dropped from the entity tables. Push resolves a
row by `server_id` first, then by `(device_id, local_id)` through the map, and
writes the map in the same transaction as the entity. The entity row always
wins a disagreement: stale map rows for that `(device, local_id)` or
`(device, entity_id)` are removed and the map is rewritten. Pull joins the map
for the requesting `device_id` only, so a row created on another device arrives
with `local_id = NULL` and the client inserts it instead of adopting a
stranger.

A status row resolves its class by the class's `server_id` when the client
knows it, and otherwise through `class_local_map`:

```json
{ "local_id": 4, "server_id": 12, "server_class_id": 7, "local_class_id": 3, ... }
```

`server_class_id` is a new, optional push field. It fixes defect 2: a class
pulled to a second device has a server id long before its local id means
anything on that device. A class created offline in the same push still
resolves through the map, because classes are processed before statuses.

**No backfill of existing `local_id` values.** The migration cannot know which
device wrote a row — that information was never stored, and `sync_cursors`
records only that a device synced, not which row it claimed. Any mapping we
invented would be a guess. After the migration, identity comes from `server_id`
(which every successfully pushed client row already holds) or from a map row
written by the next push. A local row whose `server_id` is null was never
acknowledged by the server, so inserting it is correct rather than duplicating.

Broadcast events keep working: the map is keyed by the admin's device, and a
student's pull joins on the student's own device, so the broadcast arrives
without a local id and is inserted. The old
`(user_id IS NULL, local_id, department)` probe in `sync.php` is replaced by the
map lookup.

**Push runs in one transaction.** A successful response therefore means every
entity row and every map row it reports were committed together; a database
failure rolls the whole request back, so a retry cannot leave a half-written row
that duplicates on the next push.

### 3. Ownership is derived, not duplicated

`class_statuses.user_id` is removed. Ownership is `classes.user_id` reached
through the existing `class_id` foreign key:

- delta pull: `JOIN classes c ON c.id = s.class_id WHERE c.user_id = ?`;
- push ownership check: the status's class is resolved by `server_class_id` or
  through `class_local_map`, and that lookup is always scoped to
  `classes.user_id = ?`;
- account deletion: `UPDATE class_statuses s JOIN classes c ON c.id = s.class_id
  SET s.deleted = 1 WHERE c.user_id = ?`, then
  `DELETE FROM sync_devices WHERE user_id = ?` so the device ids are released
  and the maps and cursors cascade;
- index `idx_cs_user_updated (user_id, updated_at)` becomes
  `idx_cs_class_updated (class_id, updated_at)`.

A map row cannot be used to reach another user's row: every map lookup joins
the entity and filters on its owner, so a tampered map row resolves to no row
and the push inserts a fresh row for the caller.

### 4. Departments become a relation

```sql
CREATE TABLE departments (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  created_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY uq_departments_name (name)
) ENGINE=InnoDB;
```

`users.department`, `events.department`, and `office_statuses.department`
become nullable `department_id` foreign keys to `departments(id)`. `NULL` keeps
its current meaning in every table: school-wide scope.

The wire format does not change. Signup, the admin department PATCH, and the
sync push/pull still carry `department` as a name; the backend resolves it with
a case-insensitive get-or-create (`utf8mb4_unicode_ci` makes `IT` and `it` the
same row) and joins back to a name on read. The helper selects, inserts, and on
a duplicate-key race selects again, so two simultaneous signups cannot create
two spellings of one department. Renaming a department becomes one `UPDATE`,
and every server read that joins it follows.

`users.role` gains `CHECK (role IN ('user','admin','super_admin'))`: a domain
constraint, not an FD, but the same "the database cannot lie" rule.

### 5. Offices key on the server row

The server already has the correct identity. Its key becomes total:

```sql
department_id BIGINT UNSIGNED NULL,
scope_key     BIGINT UNSIGNED AS (COALESCE(department_id, 0)) VIRTUAL,
UNIQUE KEY uq_office (office_name, scope_key)
```

`0` is outside the `AUTO_INCREMENT` range, so a school-wide row is unique
without a sentinel department and without relying on SQL's NULL semantics. The
unique key is on the `COALESCE` expression; `scope_key` is virtual and occupies
no storage (see section 6). The explicit duplicate query in `admin.php` stays
for a friendly 409, but it is no longer the only guard.

`admin_rename_office` updates the name in place instead of tombstoning the row
and inserting a copy. The server id is the office's identity, so a rename keeps
it and the phone updates the row it already has.

The phone cache changes to:

```sql
CREATE TABLE office_statuses (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id      INTEGER,
  office_name    TEXT NOT NULL,
  department     TEXT,
  status         TEXT NOT NULL DEFAULT 'open',
  custom_message TEXT,
  updated_at     TEXT NOT NULL,
  CHECK (status IN ('open', 'closed', 'break'))
);
CREATE UNIQUE INDEX idx_office_statuses_server_id
  ON office_statuses (server_id) WHERE server_id IS NOT NULL;
```

Upsert matches `server_id` first. A row left from v11 has `server_id = NULL`;
when the pull brings the same `office_name` and `department`, the cache adopts
that row instead of inserting a duplicate, so an offline strip keeps its
last-known value. A tombstone deletes by `server_id`.

Because the office batch is the full in-scope set, after applying it the phone
drops any row that is still `server_id = NULL`. That sweeps stale v11 entries —
an office retired before the upgrade, or one whose name changed before the
cache was adopted — without guessing which name it used to have. A live office
that the v11 cache knew is adopted before the sweep, so it survives.

The office set is a handful of rows, so pull returns every in-scope office
(including tombstones) on every request instead of filtering by `since`. That
guarantees a rename or retirement reaches a phone whose cache predates the
upgrade, and it makes the one-time v11 adoption deterministic. `since` still
governs classes, events, and statuses.

### 6. Derived values are computed, not stored

`events.broadcast` becomes a virtual generated column:

```sql
broadcast TINYINT(1) AS (CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) VIRTUAL
```

Reads and the wire field are unchanged; the two write statements stop supplying
it. A row can no longer claim to be a broadcast while carrying an owner, or the
reverse.

`office_statuses.scope_key` is virtual for the same reason. Neither column
occupies storage in the base row and neither can be written, so normal forms
are assessed on the stored relation, exactly as they would be for a view. If a
future change makes either column `STORED`, it becomes a materialized copy and
the table stops being BCNF; the schema comment says so.

### 7. The last two relations

`rate_limit_hits` splits the packed bucket into the policy and its subject:

```sql
CREATE TABLE rate_limit_hits (
  id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  scope   VARCHAR(32)  NOT NULL,   -- register_ip, login_email, google, ...
  subject VARCHAR(255) NOT NULL,   -- ip, lowercased email, '' for a global scope
  hit_at  DATETIME(3)  NOT NULL,
  KEY idx_rl_scope_subject_time (scope, subject, hit_at)
) ENGINE=InnoDB;
```

`rate_limit_allow` takes `(scope, subject, max, windowSeconds)`; every call site
passes its two values instead of concatenating them. The self-creating DDL in
`common.php` is updated to the same shape, because it is what runs on a live
database before the migration file is applied.

`password_resets` loses both derived and dead columns. A user has at most one
live code (the code deletes before inserting), so `user_id` is the key:

```sql
CREATE TABLE password_resets (
  user_id     BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  code_hash   VARCHAR(255) NOT NULL,
  created_at  DATETIME(3)  NOT NULL,
  ttl_seconds INT UNSIGNED NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CHECK (ttl_seconds > 0)
) ENGINE=InnoDB;
```

Forgot-password upserts on `user_id` (`ON DUPLICATE KEY UPDATE`), which closes
the delete-then-insert race that could leave two live codes and makes the
newest email the only working one. The reset endpoint compares
`created_at + INTERVAL ttl_seconds SECOND` with the current UTC time, so the
expiry is still the policy in force when the code was minted, without storing a
second copy of it. `created_at` is written explicitly in UTC (`now_mysql()`)
rather than left to the database's session timezone.

### 8. Migrations

**MySQL.** `docs/mysql_schema.sql` is the post-change schema and the PHP test
bootstrap builds from it verbatim. Existing deployments get
`php-backend/migrations/2026-11-18-normalize.sql`, run once with the API
stopped:

1. create `departments` and backfill it from every distinct non-empty
   department name (case-insensitively, first spelling wins);
2. add `department_id` to `users`, `events`, and `office_statuses`, update it
   by name, drop the text columns, then add the foreign keys;
3. create `sync_devices`, recreate `sync_cursors` keyed by `device_id`, and
   create the three map tables;
4. drop `class_statuses.user_id` and its index, add the class/updated index;
5. convert `events.broadcast` to the virtual generated column. Rows whose flag
   disagrees with `user_id` are counted and reported; the generated value then
   decides (an owned row is personal, an unowned row is a broadcast), with no
   manual flag left to drift;
6. collapse duplicate offices per `(office_name, COALESCE(department_id, 0))`
   keeping the newest `updated_at` then the lowest id, add `scope_key`, and move
   the unique key;
7. rebuild `password_resets` with `user_id` as the key and
   `ttl_seconds = 900`, keeping the newest row per user;
8. drop and recreate `rate_limit_hits` on the new shape; the table holds only
   transient counters, so the split is not backfilled and limits reset once;
9. drop `local_id` / `local_class_id` from the entity tables.

The script is run once, against a backup, because steps 2-9 are destructive.
`sync_devices` starts empty by design: old `sync_cursors` device ids cannot be
trusted to belong to one account, and clients mint account-scoped ids on the
first sync after the upgrade.

**SQLite v12.** Only `office_statuses` is rebuilt. `classes`, `events`, and
`class_status` are unchanged: their `server_id` is a one-to-one mapping inside a
single local store, which is already in BCNF, and their local ids never cross a
device boundary.

### 9. Normal-form result

Every stored relation is in 1NF, 2NF, 3NF, and BCNF.

- **1NF**: every column is atomic. Splitting `bucket` removes the last packed
  value; no table stores a list, JSON blob, or repeating group.
- **2NF**: only the three maps have composite keys, and each non-key attribute
  depends on the whole key (`class_id` depends on the device *and* the local
  id, not on either alone). Every other relation has a single-column key, so
  2NF holds vacuously.
- **3NF / BCNF**: every determinant is a superkey. The old violations are gone:
  `class_statuses.user_id` (transitive), `events.broadcast` (derived),
  `password_resets.expires_at` (derived), and `sync_cursors(user_id,
  device_id)` (device determines user) no longer exist as stored attributes.

| Relation | 1NF | 2NF | 3NF | BCNF |
|---|---|---|---|---|
| `users` | yes | yes | yes | yes |
| `departments` | yes | yes | yes | yes |
| `classes` | yes | yes | yes | yes |
| `events` | yes | yes | yes | yes |
| `class_statuses` | yes | yes | yes | yes |
| `office_statuses` | yes | yes | yes | yes |
| `password_resets` | yes | yes | yes | yes |
| `class_local_map` | yes | yes | yes | yes |
| `status_local_map` | yes | yes | yes | yes |
| `event_local_map` | yes | yes | yes | yes |
| `sync_devices` | yes | yes | yes | yes |
| `sync_cursors` | yes | yes | yes | yes |
| `rate_limit_hits` | yes | yes | yes | yes |

Three clarifications, because they are the places a reviewer will push:

- `events.broadcast` and `office_statuses.scope_key` are `VIRTUAL` generated
  columns. They occupy no storage in the base row and cannot be written, so the
  relations are assessed on their stored attributes. Materializing either one
  with `STORED` would create `user_id -> broadcast` or
  `scope_key -> department_id`; the schema keeps them virtual for that reason.
- The `local_id` defect is a **join dependency**, not a multivalued one: a row
  stored the class's schedule and "device D calls this class N" as one tuple,
  while dropping `device_id`. The fix is the decomposition into the entity and
  its map. Calling it 4NF would have been imprecise; it is 5NF / project-join.
- Departments were **not** a 3NF violation: with only a name, there is no
  non-key attribute for it to depend on. It was a missing domain relation
  (DKNF) plus an update anomaly on rename. The table is still the right fix,
  but the label matters.

`password_resets` is the one place where the previous draft stored a snapshot.
It now stores the independent facts (`created_at`, `ttl_seconds`) and computes
expiry at read time; the code's lifetime is still the policy from mint time.

## API contract

Request and response shapes are unchanged except:

- `device_id` is required and validated on `POST /sync/push` and
  `GET /sync/pull`; a missing value is `422 DEVICE_REQUIRED`, an id owned by
  another account is `409 DEVICE_CONFLICT`.
- A status push may include `server_class_id`; a pull no longer returns
  `local_class_id`.
- `local_id` in a pull response is the local id **for the requesting device**,
  or `null` when this device never pushed that row.
- `office_statuses` is returned in full on every pull, not filtered by `since`.
- `office_statuses[].id` is the cache's identity on the phone; it was already
  present in the payload.

`department` remains a name on the wire. `password_resets` and
`rate_limit_hits` are internal and do not appear in any response.

## Non-goals

- P3 (overlapping status ranges per class) stays out.
- No new department rename UI; the schema makes a rename possible, and the
  existing office rename admin action keeps the office's id.
- No department sync delta. The phone keeps the department *name* it received,
  because it has no department entity to reference. A rename reaches a phone
  only when the row is read again (offices are refetched in full; events and
  users on their next update or refresh). Propagating it everywhere would need
  a departments delta and is a separate feature.
- No account partitioning of the local SQLite store. Logout still clears only
  the session, so two accounts on one install share local rows. This schema
  change prevents map collisions by scoping device ids per account, but it does
  not partition the local data; that privacy fix is separate.
- The local `classes`, `events`, and `class_status` tables keep `server_id` as a
  column. Inside one store that is a 1:1 relation in BCNF.
- Rows already overwritten by the old `(user_id, local_id)` match cannot be
  recovered. This prevents recurrence, it does not repair history.

## Verification

- PHP: two devices of the same user pushing the same `local_id` create two
  server rows; a new device id (reinstall) does not touch the previous install's
  rows; a device id owned by another account gets 409; the map's unique keys
  reject a second local id for the same row; a status on a class pulled to a
  second device is stored via `server_class_id`; a status on an offline class is
  stored via the map; a status for another user's class is skipped; account
  deletion tombstones the user's marks without a `user_id` column and releases
  the device.
- Generated `broadcast`: a row written with an owner is personal and a row
  written without one is a broadcast, with no way to set the flag directly;
  `information_schema` reports it as a virtual generated column.
- Offices: a duplicate school-wide name is rejected by the unique key, not only
  by the endpoint's pre-check; the same name in two departments is allowed; a
  rename keeps the id; a retired office propagates its tombstone.
- Departments: `IT` and `it` resolve to one row; a rename is visible on the
  next user/event/office read; a department with dependants cannot be deleted.
- Password reset: a code minted 16 minutes ago is rejected, a fresh one is
  accepted, two forgot requests leave exactly one row and only the newest code
  works, and the reset deletes the row. No `expires_at` / `used_at` column
  exists.
- Rate limiting: the same window still limits by email and by IP after the
  split, including the global `google` scope; the table has no packed bucket.
- Dart: v11 -> v12 keeps cached office rows, the first pull adopts them by name
  and department, a rename updates the same row, a tombstone deletes by
  `server_id`, and a still-unadopted v11 row is swept after the full batch; the
  device id rotates when the account changes and is reused for the same
  account.
- Migration rehearsal on a dump of `klasify_sync`: the script applies cleanly,
  demotes and counts any mismatched broadcast flag, collapses duplicate offices
  and duplicate reset rows, recreates the rate-limit table, and leaves no text
  `department` column, no client-id column, no `expires_at` / `used_at`, no
  packed `bucket`, and no `user_id` in the maps or `class_statuses`.
- Full `flutter test`, `flutter analyze --no-fatal-infos`, and the PHP harness
  stay green; docs are updated with the new schema version and counts.

## Risks

- Removing `class_statuses.user_id` touches the delta query, the push class
  resolution, and account deletion. Each is covered by a test before
  implementation.
- The MySQL migration drops columns and rebuilds tables; a backup is mandatory,
  the script documents the dump command, and the API stays stopped for the
  window because old and new code cannot share `rate_limit_hits` or
  `password_resets`.
- `rate_limit_hits` counters reset once at migration, so a burst of requests
  immediately after the window is not throttled by pre-migration history.
- The client re-mints its device id once after the upgrade. Previously pushed
  rows keep their `server_id`, so nothing is re-created; unpushed rows are
  inserted once.
- An old app build on a shared install sends one device id for two accounts and
  gets `409 DEVICE_CONFLICT` for the second account until it updates. A single
  account keeps working.
- Department get-or-create preserves today's behavior where a typo creates a
  new scope. It is not made stricter here; that is a product decision.
- The local store is still shared between accounts on one install (see
  Non-goals). That is a privacy issue with its own fix, not a normalization
  one; the server-side maps can no longer collide across accounts.
</content>
