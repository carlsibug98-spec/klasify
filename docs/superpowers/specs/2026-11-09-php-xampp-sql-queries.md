# Complete SQL inventory — PHP/XAMPP migration

Date: 2026-11-09
Companion to: `2026-11-09-php-xampp-migration-design.md`

This is **every** SQL statement the Klasify backend service executes, grouped
by module and endpoint. The PHP port runs these queries query-for-query
against XAMPP's MariaDB with PDO prepared statements (parameterized
everywhere — no interpolation of user input). `@` marks bind parameters.

Not included here: the app's **local SQLite** statements
(`lib/database/database_helper.dart`) — they never touch the server and are
unchanged by this migration.

## 0. Connection bootstrap (per request)

```sql
SET time_zone = '+00:00'   -- every DATETIME(3) value is UTC, matching mysql2's timezone:'Z'
```

## 1. Schema (`docs/mysql_schema.sql`, imported verbatim)

- `CREATE DATABASE IF NOT EXISTS klasify_sync ... utf8mb4_unicode_ci`
- `CREATE TABLE users / classes / events / office_statuses / class_statuses
  / password_resets / sync_cursors`
- Debug views: `active_classes`, `active_events`, `active_class_statuses`
- Admin provisioning comments (UPDATE examples only)

Plus the **one addition** (ADOPTED-BASE AMENDMENT: the port self-creates the
table at first use; the DDL is added here for documentation parity):

```sql
CREATE TABLE IF NOT EXISTS rate_limit_hits (
  id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  bucket VARCHAR(300) NOT NULL,           -- 'forgot:<email>' | 'google'
  hit_at DATETIME(3)    NOT NULL,
  KEY idx_rl_bucket_time (bucket, hit_at)
) ENGINE=InnoDB;
```

## 2. Rate limiting (`src/common.php` in the adopted base)

Replaces the Node build's two in-memory Maps. Same windows and limits:
forgot-password **5 requests / email / 60 min** (`forgot:<lowercased email>`
bucket), `/auth/google` **30 / global `google` bucket / 60 s**. The table
`rate_limit_hits` self-creates on first use and is swept 1-in-100 requests.

| # | Purpose | Query |
|---|---|---|
| R1 | count hits inside the window | `SELECT COUNT(*) FROM rate_limit_hits WHERE bucket = @bucket AND hit_at >= @since` |
| R2 | record the hit (after passing) | `INSERT INTO rate_limit_hits (bucket, hit_at) VALUES (@bucket, @now)` |
| R3 | occasional 1-day sweep of all buckets | `DELETE FROM rate_limit_hits WHERE hit_at < @cutoff` |

## 3. `/sync/push` (`src/sync.php`)

**Caller context**

| # | Purpose | Query |
|---|---|---|
| S1 | caller role/dept for broadcast rights | `SELECT role, department FROM users WHERE id = @uid AND deleted = 0 LIMIT 1` |

**Classes section** (per pushed row; order matters — server id first, then local_id)

| # | Purpose | Query |
|---|---|---|
| S2 | match by echoed server id | `SELECT id FROM classes WHERE user_id = @uid AND id = @sid LIMIT 1` |
| S3 | fallback match by client local_id | `SELECT id FROM classes WHERE user_id = @uid AND local_id = @lid LIMIT 1` |
| S4 | update existing | `UPDATE classes SET subject=@,room=@,professor=@,day=@,start_minutes=@,end_minutes=@,deleted=@,updated_at=@ WHERE id=@id` |
| S5 | insert new | `INSERT INTO classes (user_id,local_id,subject,room,professor,day,start_minutes,end_minutes,deleted,updated_at) VALUES (@uid,@lid,@,@,@,@,@,@,@,@at)` |

**Events section** (broadcast rules: super admin any dept, dept admin own
dept, non-admin broadcast silently demoted to personal)

| # | Purpose | Query |
|---|---|---|
| S6 | inspect target row by server id | `SELECT id, user_id, department FROM events WHERE id = @sid LIMIT 1` |
| S7 | match broadcast row (dept scope) | `SELECT id FROM events WHERE user_id IS NULL AND local_id = @lid AND department <=> @dept LIMIT 1` |
| S8 | match personal row | `SELECT id FROM events WHERE user_id = @uid AND local_id = @lid LIMIT 1` |
| S9 | update (user_id follows broadcast state) | `UPDATE events SET user_id=@,title=@,venue=@,event_date=@,start_minutes=@,category=@,department=@,broadcast=@,reminder_enabled=@,lead_minutes=@,deleted=@,updated_at=@ WHERE id=@id` |
| S10 | insert | `INSERT INTO events (user_id,local_id,title,venue,event_date,start_minutes,category,department,broadcast,reminder_enabled,lead_minutes,deleted,updated_at) VALUES (@x13)` |

**Class-statuses section** (class resolved via the class push that ran first)

| # | Purpose | Query |
|---|---|---|
| S11 | resolve server class id from local_class_id | `SELECT id FROM classes WHERE user_id = @uid AND local_id = @lclass LIMIT 1` |
| S12 | match by server id | `SELECT id FROM class_statuses WHERE user_id = @uid AND id = @sid LIMIT 1` |
| S13 | fallback by local_id | `SELECT id FROM class_statuses WHERE user_id = @uid AND local_id = @lid LIMIT 1` |
| S14 | update | `UPDATE class_statuses SET class_id=@,status=@,start_date=@,end_date=@,deleted=@,updated_at=@ WHERE id=@id` |
| S15 | insert (rows whose class isn't on the server yet are skipped) | `INSERT INTO class_statuses (user_id,local_id,class_id,local_class_id,status,start_date,end_date,deleted,updated_at) VALUES (@x9)` |

**Cursor**

| # | Purpose | Query |
|---|---|---|
| S16 | upsert push cursor (device_id from body, defaults 'unknown') | `INSERT INTO sync_cursors (user_id, device_id, last_push_at) VALUES (@uid, @device, @now) ON DUPLICATE KEY UPDATE last_push_at = VALUES(last_push_at), updated_at = CURRENT_TIMESTAMP(3)` |

## 4. `/sync/pull` (`src/sync.php`)

`@since` is the client cursor (inclusive). `@dept` = caller department.

| # | Purpose | Query |
|---|---|---|
| P1 | caller dept filter | `SELECT department FROM users WHERE id = @uid AND deleted = 0 LIMIT 1` |
| P2 | classes delta (own only) | `SELECT id,local_id,subject,room,professor,day,start_minutes,end_minutes,deleted,updated_at FROM classes WHERE user_id = @uid AND updated_at >= @since` |
| P3 | events delta (own + broadcasts for dept/school) | `SELECT id,local_id,title,venue,event_date,start_minutes,category,department,broadcast,reminder_enabled,lead_minutes,deleted,updated_at FROM events WHERE (user_id = @uid OR (user_id IS NULL AND (department IS NULL OR department = @dept))) AND updated_at >= @since` |
| P4 | class-status delta (own only) | `SELECT id,local_id,class_id,local_class_id,status,start_date,end_date,deleted,updated_at FROM class_statuses WHERE user_id = @uid AND updated_at >= @since` |
| P5 | office statuses delta (school-wide + own dept) | `SELECT id,office_name,department,status,custom_message,updated_at,deleted FROM office_statuses WHERE (department IS NULL OR department = @dept) AND updated_at >= @since` |
| P6 | upsert pull cursor (device_id from query string) | `INSERT INTO sync_cursors (user_id, device_id, last_pull_at) VALUES (@uid, @device, @now) ON DUPLICATE KEY UPDATE last_pull_at = VALUES(last_pull_at), updated_at = CURRENT_TIMESTAMP(3)` |

## 5. `/auth/*` (`src/auth.php`)

### POST /auth/register

| # | Purpose | Query |
|---|---|---|
| A1 | dup check — **every row, soft-deleted included** (unique email) | `SELECT id FROM users WHERE email = @email` |
| A2 | create | `INSERT INTO users (email, password_hash, display_name, department) VALUES (@email, @hash, @name, @dept)` |
| A3 | read back for response | `SELECT id,email,password_hash,display_name,role,department,google_sub FROM users WHERE id = @id` |

### POST /auth/login

| # | Purpose | Query |
|---|---|---|
| A4 | find active user + hash | `SELECT id,email,password_hash,display_name,role,department FROM users WHERE email = @email AND deleted = 0 LIMIT 1` |

### POST /auth/google (mode: signin/signup)

| # | Purpose | Query |
|---|---|---|
| A5 | lookup by Google subject | `SELECT id,email,password_hash,display_name,google_sub,role,department FROM users WHERE google_sub = @sub AND deleted = 0 LIMIT 1` |
| A6 | lookup by verified email | `SELECT id,email,password_hash,display_name,google_sub,role,department FROM users WHERE email = @email AND deleted = 0 LIMIT 1` |
| A7 | google_sub backfill on email match | `UPDATE users SET google_sub = @sub WHERE id = @id` |
| A8 | soft-deleted / inactive holdout check before signup insert → 409 | `SELECT id FROM users WHERE email = @email OR google_sub = @sub LIMIT 1` |
| A9 | signup create (password_hash NULL, typed name preferred over profile name) | `INSERT INTO users (email, password_hash, google_sub, display_name, department) VALUES (@email, NULL, @sub, @name, @dept)` |
| A10 | read back for response | `SELECT id,email,password_hash,display_name,google_sub,role,department FROM users WHERE id = @id` |

### POST /auth/refresh

| # | Purpose | Query |
|---|---|---|
| A11 | fresh `user` incl. role/dept (expired token accepted, signature only) | `SELECT id,email,display_name,role,department FROM users WHERE id = @uid AND deleted = 0 LIMIT 1` |

### DELETE /auth/account (soft-delete cascade, then 204)

| # | Purpose | Query |
|---|---|---|
| A12 | tombstone user | `UPDATE users SET deleted = 1 WHERE id = @uid` |
| A13 | tombstone classes | `UPDATE classes SET deleted = 1 WHERE user_id = @uid` |
| A14 | tombstone events | `UPDATE events SET deleted = 1 WHERE user_id = @uid` |
| A15 | tombstone class statuses | `UPDATE class_statuses SET deleted = 1 WHERE user_id = @uid` |
| A16 | purge outstanding reset codes (hard delete) | `DELETE FROM password_resets WHERE user_id = @uid` |

### PATCH /auth/me

| # | Purpose | Query |
|---|---|---|
| A17 | email dup check — all rows, others only | `SELECT id FROM users WHERE email = @email AND id <> @uid LIMIT 1` |
| A18 | partial update (`display_name` / `email` / both, built from presence) | `UPDATE users SET display_name = @name, email = @email WHERE id = @uid` |
| A19 | read back fresh user | `SELECT id,email,display_name,role,department FROM users WHERE id = @uid LIMIT 1` |

### POST /auth/change-password

| # | Purpose | Query |
|---|---|---|
| A20 | current hash | `SELECT password_hash FROM users WHERE id = @uid AND deleted = 0 LIMIT 1` |
| A21 | store new hash | `UPDATE users SET password_hash = @hash WHERE id = @uid` |
| A22 | outstanding codes now meaningless | `DELETE FROM password_resets WHERE user_id = @uid` |

### POST /auth/forgot-password (uses R1–R3 with bucket `email:<lowercased email>`)

| # | Purpose | Query |
|---|---|---|
| A23 | does the account exist (never revealed in the response) | `SELECT id FROM users WHERE email = @email AND deleted = 0 LIMIT 1` |
| A24 | one active code at a time | `DELETE FROM password_resets WHERE user_id = @uid` |
| A25 | store bcrypt of the 6-digit code (15 min TTL) | `INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (@uid, @hash, @expires)` |

### POST /auth/reset-password

| # | Purpose | Query |
|---|---|---|
| A26 | locate account | `SELECT id FROM users WHERE email = @email AND deleted = 0 LIMIT 1` |
| A27 | latest unused code | `SELECT id, code_hash, expires_at FROM password_resets WHERE user_id = @uid AND used_at IS NULL ORDER BY created_at DESC LIMIT 1` |
| A28 | store new hash (only after bcrypt-compare + non-expired) | `UPDATE users SET password_hash = @hash WHERE id = @uid` |
| A29 | purge codes | `DELETE FROM password_resets WHERE user_id = @uid` |

## 6. `/admin/*` (`src/admin.php`)

**Middleware incl. resolveCaller — every /admin route**

| # | Purpose | Query |
|---|---|---|
| M1 | caller + admin gate | `SELECT id, role, department FROM users WHERE id = @uid AND deleted = 0 LIMIT 1` (non-admin → 403 FORBIDDEN) |

### GET /admin/users

| # | Purpose | Query |
|---|---|---|
| M2 | super_admin: everybody | `SELECT id,email,display_name,role,department,created_at FROM users WHERE deleted = 0 ORDER BY created_at DESC LIMIT 200` |
| M3 | dept admin with department: their dept + self | `SELECT id,email,display_name,role,department,created_at FROM users WHERE deleted = 0 AND (department = @dept OR id = @uid) ORDER BY created_at DESC LIMIT 200` |
| M4 | dept admin without department: only self | `SELECT id,email,display_name,role,department,created_at FROM users WHERE deleted = 0 AND id = @uid ORDER BY created_at DESC LIMIT 200` |

`created_at` is returned as a **raw** `DATETIME(3)` string, sqlite-mysql2
`dateStrings` parity (see design doc rule 3).

### PATCH /admin/users/:id/role (super admin only)

| # | Purpose | Query |
|---|---|---|
| M5 | promote/demote ('user' | 'admin' | 'super_admin') | `UPDATE users SET role = @role WHERE id = @target AND deleted = 0` |

### PATCH /admin/users/:id/department (super admin only)

| # | Purpose | Query |
|---|---|---|
| M6 | assign / clear department | `UPDATE users SET department = @dept WHERE id = @target AND deleted = 0` |

### GET /admin/office-statuses (auto-seeds missing offices, then re-lists)

| # | Purpose | Query |
|---|---|---|
| M7 | list school-wide offices | `SELECT id,office_name,status,custom_message,user_id,updated_at FROM office_statuses WHERE deleted = 0 AND department IS NULL ORDER BY office_name` |
| M8 | seed missing office (one per gap; caller = seeder) | `INSERT INTO office_statuses (user_id, office_name, department, status) VALUES (@uid, @office, NULL, 'open')` |
| M9 | fresh list = M7 again | (repeat of M7) |

### PATCH /admin/office-statuses/:office (upsert)

| # | Purpose | Query |
|---|---|---|
| M10 | existing school-wide row? | `SELECT id FROM office_statuses WHERE office_name = @office AND department IS NULL AND deleted = 0 LIMIT 1` |
| M11 | update | `UPDATE office_statuses SET status = @status, custom_message = @msg, user_id = @uid WHERE id = @id` |
| M12 | or create | `INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (@uid, @office, NULL, @status, @msg)` |

## 7. No-SQL endpoints

- `GET /health` — no SQL (app never calls it; kept for ops/tunnel checks).
- JWT sign/verify — no SQL (HS256 HMAC, secret from config).
- CORS / 404 / 422 / 500 handling — no SQL.

## 8. Totals & rules

- **66 runtime statements** (with parameter slots expanded): 3 rate-limit +
  16 /sync/push + 6 /sync/pull + 29 /auth + 12 /admin. One-time schema:
  7 tables + 3 views + 1 new table. Many endpoints share repeated statements
  by design (e.g. A3/A10 read-back, M7/M9 relist) — the PHP port keeps them
  as separate calls exactly like the Node service does.
- Every statement is **prepared + parameterized**; the only dynamic SQL is
  `PATCH /auth/me`'s SET builder (column names are code-owned literals).
- `ON DUPLICATE KEY UPDATE` appears exactly twice (both sync cursors) —
  supported by MariaDB identically.
- `department <=> @dept` (null-safe compare) is one statement (S7) and is
  supported by MariaDB.
- Explicit `updated_at` SETs win over the `ON UPDATE CURRENT_TIMESTAMP(3)`
  clause — that's what makes the server echo client timestamps verbatim in
  push responses (parity detail).
