# PHP/XAMPP Migration (adopted-base) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt the audited PHP port as the Klasify backend, prove it contract-identical with an offline test harness, deploy it on the user's XAMPP with all existing data, verify on the TECNO device, then retire the Node/Docker stack.

**Architecture:** `php-backend/` (front controller + PDO/MariaDB, no Composer) adopted from `klasify-backend-php.zip`, hardened by audit patches, upgraded from per-login Google `tokeninfo` cURL to a local JWKS RS256 verifier with a config switch, and gated by a zero-Composer parity harness (`tests/run.php` against a disposable `klasify_test` DB). Node stays live until the full device checklist passes; then it is deleted and the docs cut over.

**Tech Stack:** PHP 8.2.12 (`C:\xampp\php\php.exe`, not on PATH), Apache + MariaDB 10.4 (XAMPP at `C:\xampp`), PDO MySQL, openssl/curl extensions (XAMPP defaults). Docker MySQL currently holds the live `klasify_sync` data.

**Spec:** `docs/superpowers/specs/2026-11-09-php-xampp-migration-design.md` (incl. the adopted-base amendment) and its query inventory `docs/superpowers/specs/2026-11-09-php-xampp-sql-queries.md`. The frozen wire contract: `docs/sync_api_contract.md`.

## Global Constraints

- PHP must produce exactly the status codes, error codes/messages, and JSON shapes of `docs/sync_api_contract.md` — it is frozen; never "improve" it as part of migration.
- Zero-Composer: no `composer.json`, no `vendor/`, no external PHP dependencies anywhere.
- The zip's provenance must be recorded before Task 1's adoption commit; Task 1 waits for the user's answer.
- Existing users keep tokens and passwords: same HS256 `jwt_secret`, bcrypt cost 12, Node-issued `$2b$` hashes verified by `password_verify`.
- Timestamp dialects are per-endpoint (design doc rule 3): auth/sync emit ISO-millis `Z` (`2026-11-09T12:34:56.789Z`); `GET /admin/users` `created_at` and `GET /admin/office-statuses` `updated_at` emit raw `DATETIME(3)` strings (`2026-11-09 12:34:56.789`).
- `users.email` / `users.google_sub` are UNIQUE including soft-deleted rows; every create path pre-checks and returns `409 EMAIL_EXISTS`.
- Accepted divergence (documented only): oversized body `413` → `422 VALIDATION_ERROR` under PHP.
- The Flutter app has zero code changes except the 2-line reset-screen copy change, applied only in the cutover commit (Task 10).
- Never commit the untracked mockups: `.taste-skill/`, all `mockup_*.html`, `profile_mockup.html`. Never use `git add -A`/`git add .` — stage explicit paths.
- Windows shell: run PHP as `& "C:\xampp\php\php.exe" ...`; PowerShell has no `<` redirect — use `cmd /c`.
- The Docker stack (`backend/`, containers `klasify-api` :8080, `klasify-mysql`, db `klasify_sync`, root/klasify_dev) stays live until the device checklist (Task 9) passes; only Task 8's data-dump step briefly stops it.
- The test-only seam allowed in production code is exactly one: `read_json_body()` checks `$GLOBALS['KLASIFY_TEST_BODY']` first (added in Task 2). No other production seams.
- PC LAN IP `192.168.1.67`; app rebuild flag `--dart-define=KLASIFY_API_URL=http://192.168.1.67/klasify-api`.

## Review Focus

The five failure modes the spec implies but no task's tests fully exercise, and where their pinning tests live:

1. **Timestamp dialect mismatch** — the app parses both dialects with `DateTime.tryParse`, so a PHP regression from ISO-`Z` to raw DATETIME (or vice-versa) silently corrupts cursor arithmetic. Pinned: regex assertions in Task 3 (`expires_at`/`server_time`), Task 4 (push echo/delta `updated_at`), Task 5 (admin raw `created_at`/`updated_at`).
2. **Node-era bcrypt interop** — the harness cannot fabricate a `$2b$` hash authored by the Node bcrypt crate, so true interop is pinned only by the live-data smoke login (Task 8, user `test@test.com` / `password123`) and device item 1 (Task 9). STOP on failure.
3. **Verbatim `updated_at` echo** — sync push must return the client's ISO string unchanged or cursor logic breaks. Pinned: Task 4 exact-echo test.
4. **Soft-delete uniqueness** — register/google signup/PATCH-me over soft-deleted rows must 409, never duplicate-key 500. Pinned: Task 3.
5. **JWKS rotation + offline resilience** — unknown `kid` forces one re-fetch; a fetch failure with a valid cached JWKS must still verify (school-PC internet blips). Pinned: Task 6.

---

### Task 1: Adopt the zip as `php-backend/` + provenance + config-level patches

**Files:**
- Create: `php-backend/**` (from `C:\Users\clarisse sibug\AppData\Local\Temp\opencode\klasify-backend-php\klasify-main\backend\`; re-extract from `C:\Users\clarisse sibug\Downloads\klasify-backend-php.zip` if temp is gone)
- Create: `php-backend/PROVENANCE.md`
- Modify: `docs/mysql_schema.sql` (append `rate_limit_hits` DDL after the `sync_cursors` table, before the debug views)
- Modify: `php-backend/.htaccess` (Authorization passthrough)

**Interfaces:**
- Consumes: the zip tree with handlers `auth_register/auth_login/auth_google/auth_refresh/auth_update_me/auth_change_password/auth_forgot_password/auth_reset_password/auth_delete_account/sync_push/sync_pull/admin_list_users/admin_set_role/admin_set_department/admin_list_offices/admin_update_office` and helpers as read in `src/*.php` (route table in `index.php`, config keys `db_host/db_port/db_name/db_user/db_pass/jwt_secret/google_client_id`).
- Produces: the file layout all later tasks edit; `PROVENANCE.md` documents every patch as it lands.

Locks (already verified in the audit — do NOT re-derive): zip schema byte-identical to repo's; contract copies differ only in 2 hosting-note lines; `rate_limit_hits` self-creates via `rate_limit_allow()`; buckets `forgot:<lowercased email>` (5 / 3600 s) and `google` (30 / 60 s); log sink `php-backend/storage/logs/app.log` via `app_log()`.

- [ ] **Step 1: Record provenance.** Run `Get-FileHash -Algorithm SHA256 "C:\Users\clarisse sibug\Downloads\klasify-backend-php.zip"`. Write `php-backend/PROVENANCE.md`:

```markdown
# Provenance & adoption record

- Source: klasify-backend-php.zip (C:\Users\clarisse sibug\Downloads)
- SHA-256: <hash>
- Audited against: docs/sync_api_contract.md (frozen) + the SQL query inventory, 2026-11-09
- Provenance (user-provided): <USER ANSWER — do not commit without it>
- Adopted as php-backend/ with configs patched; code-level patches from
  Tasks 5 (`ctype_digit` guard) and 6 (JWKS verifier) are appended below
  as they land.
- Patch log: .htaccess SetEnvIf passthrough (task 1), rate_limit_hits DDL
  into docs/mysql_schema.sql (task 1).
```

- [ ] **Step 2: Copy the zip's `backend/` directory into the repo as `php-backend/`** — every file under that directory (`config.php`, `index.php`, `src/{common,auth,sync,admin}.php`, `.htaccess`, `src/.htaccess`, `storage/.htaccess`, empty `storage/logs/` dir + its `.htaccess`, `README.md`, `.gitignore` — read the `.gitignore` and keep it). Exclude the zip's `docs/` and `lib/` siblings (repo owns both; the 2-line Flutter copy change from the zip's `lib` lands at cutover, Task 10).
- [ ] **Step 3: Patch `php-backend/.htaccess`** — append after the `RewriteRule ^ index.php [QSA,L]` line:

```apache
# CGI/FastCGI hosts drop the Authorization header; pass it through.
# mod_php under XAMPP works without this, but hosts don't always.
SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1
```

- [ ] **Step 4: Patch `docs/mysql_schema.sql`** — right after the `sync_cursors` CREATE TABLE block (before the debug views):

```sql
-- Rate limiting (added 2026-11-09 with the PHP port). The port also
-- self-creates this table at first use; the DDL is here for documentation.
CREATE TABLE IF NOT EXISTS rate_limit_hits (
  id     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  bucket VARCHAR(300) NOT NULL,          -- 'forgot:<email>' | 'google'
  hit_at DATETIME(3)  NOT NULL,
  KEY idx_rl_bucket_time (bucket, hit_at)
) ENGINE=InnoDB;
```

- [ ] **Step 5: Verify the adoption.** `& "C:\xampp\php\php.exe" -l` every `.php` under `php-backend/` (5 files: config, index, src/admin, src/auth, src/common, src/sync = 6). Expected: `No syntax errors detected` for all. Diff each copied file against the temp extraction; expected identical except `php-backend/.htaccess` (Step 3).
- [ ] **Step 6: Commit.**

```bash
git add php-backend docs/mysql_schema.sql
git commit -m "feat(backend): adopt PHP/XAMPP port as php-backend/ with audit patches"
```

(Verify with `git status` that no mockup files were staged and `php-backend/storage/logs/.htaccess` landed.)

### Task 2: Zero-Composer parity harness skeleton

**Files:**
- Create: `php-backend/tests/run.php`, `php-backend/tests/bootstrap.php`, `php-backend/tests/auth_test.php` (starts as the 1-test placeholder below)
- Modify: `php-backend/src/common.php` — the single test seam

**Interfaces:**

- `run.php`: `putenv('KLASIFY_DB_NAME=klasify_test')` → require `bootstrap.php` → require `auth_test.php`, `sync_test.php`, `admin_test.php`, `google_jwks_test.php` (skip files that don't exist yet) → `exit($T->finish())`.
- `bootstrap.php` requires `src/common.php`, `src/auth.php`, `src/sync.php`, `src/admin.php` (mirroring `index.php`'s requires; `date_default_timezone_set('UTC')` is inside common.php already). Exported:
  - `T` — a minimal runner object with: `T->test(string $name, callable $fn): void` (runs immediately, catches Throwable, records result), `T->eq(mixed $expected, mixed $actual, string $label = ''): void` (strict `===` for scalars; array walk with `===` leaves), `T->truthy(bool $cond, string $label): void`, `T->fail(string $label)` (throws), `T->finish(): int` (prints `[ok]`/`[FAIL] <name> — <label>`, one line `passed N, failed M`, returns M).
  - `db_rebuild(): void` — one-time-per-run schema reset: connect WITHOUT dbname to root@127.0.0.1 (XAMPP defaults), `DROP DATABASE IF EXISTS klasify_test; CREATE DATABASE klasify_test ...`, then execute `docs/mysql_schema.sql` contents with `klasify_sync` string-replaced to `klasify_test`. Parse method: filter out lines beginning with `--` (removes comments incl. the comment-only UPDATE examples), then split on `;` and run each statement. This exercises Task 1's DDL directly and must be idempotent.
  - `db_reset(): void` — `SET FOREIGN_KEY_CHECKS=0`, `TRUNCATE` `users, classes, events, office_statuses, class_statuses, password_resets, sync_cursors, rate_limit_hits`, `SET FOREIGN_KEY_CHECKS=1` (TRUNCATE resets AUTO_INCREMENT → deterministic ids 1,2,3…).
  - `seed_user(array $f): int` — insert into `users` with defaults: `password` → `password123` (hashed `PASSWORD_BCRYPT, cost 12`), `role` → `'user'`, `department`/`google_sub` → null, `deleted` → 0; keys `email`, `display_name`, `password_hash` may be given explicitly. Returns id.
  - `act_as(int $userId): void` — `$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . jwt_sign_token($id, <email from DB>)`; `act_as(0)` unsets the header.
  - `set_body(array $body): void` / `set_body(null)` — sets/unsets `$GLOBALS['KLASIFY_TEST_BODY']`.
  - `run_handler(callable $h, mixed ...$args): array{status:int, body:mixed, raw:string}` — reset `http_response_code(200)`, `ob_start()`, invoke `$h(...$args)` inside a try/catch that mirrors `index.php` exactly: `ApiError` → `send_json($e->status, ['error'=>$e->getMessage(), 'code'=>$e->errorCode])`; `Throwable` → `app_log` + `send_json(500, ['error'=>'Internal server error','code'=>'SERVER_ERROR'])`. Decodes captured output as JSON; `raw` for 204 is `''`; `body` is the decoded array.
  - `rs256_no_token(string $name)` — no, skip: rate-limit tests per Task 3 instead.
  - `make_rs256_fixture(array $claims, string $kid = 'test-kid-1'): array{token, jwks, priv}` — 2048-bit RSA keypair via `openssl_pkey_new`, `openssl_pkey_get_details()['rsa']` → `n`/`e` binary → base64url without padding → JWKS JSON `{"keys":[{"kty":"RSA","kid":KID,"use":"sig","alg":"RS256","n":...,"e":...}]}`; token = `b64url(json {alg:RS256,kid:KID}) . '.' . b64url(json claims)`, signed `openssl_sign(..., OPENSSL_ALGO_SHA256)`.
  - `last_log_code(): string` — tail `php-backend/storage/logs/app.log`, return the last 6-digit run (`/(\d{6})/`), used by the forgot/reset test.

**Logic decisions:**

- Tests target `klasify_test` on the XAMPP MySQL via the bootstrap env set BEFORE any `cfg()` call (its settings array is cached on first call — ordering matters).
- `run.php` calls `db_rebuild()` once per suite run; each `T->test` begins with `db_reset()` inside its `$fn` (first statement), so tests are order-independent.

**Code:** the single production seam, at the very top of `read_json_body()` in `php-backend/src/common.php`, before the `static` cache:

```php
    // Test seam (adoption, 2026-11-09): the parity harness injects request
    // bodies from CLI (php://input is not writable there). Production never
    // sets this key, so behavior below is unchanged.
    if (isset($GLOBALS['KLASIFY_TEST_BODY'])) {
        return $GLOBALS['KLASIFY_TEST_BODY'];
    }
```

- [ ] **Step 1: Write `run.php`, `bootstrap.php`, and a placeholder `auth_test.php` containing exactly one test**: seed nothing, `set_body(['email'=>'new@test.com','password'=>'min12345','display_name'=>'Juan Dela Cruz','department'=>'IT'])`, `run_handler('auth_register')` → expect status 201 and body keys exactly `['user','token','expires_at']`.
- [ ] **Step 2: Run the harness.**

Run: `& "C:\xampp\php\php.exe" php-backend\tests\run.php`
Expected: `passed 1, failed 0`, exit 0. (This run implicitly proves `db_rebuild()` parsed the real schema file + the seam works.)

- [ ] **Step 3: Commit.**

```bash
git add php-backend/tests php-backend/src/common.php
git commit -m "test(php-backend): zero-Composer parity harness skeleton"
```

### Task 3: Auth contract tests (`/auth/*`)

**Files:**
- Test: `php-backend/tests/auth_test.php` (extend the placeholder)

**Interfaces:**
- Consumes: bootstrap helpers; handlers `auth_register/auth_login/auth_google/auth_refresh/auth_update_me/auth_change_password/auth_forgot_password/auth_reset_password/auth_delete_account`.
- Produces: fix list for `php-backend/src/*.php` if any test exposes a real bug (harness green or "Fixes found:" in commit message).

Test list (each one `T->test`, each begins with `db_reset()`):

1. `register contract shape + tokens` — `{email:'new@test.com', password:'min12345', display_name:'Juan Dela Cruz', department:'IT'}` → 201; `user.role==='user'`, `user.department==='IT'`; `expires_at` matches `/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/` (Review Focus 1); decode JWT payload: `user_id` equals registered id, `exp - iat === 604800`.
2. `register duplicate 409` — seed `dup@test.com`, register again → 409 code `EMAIL_EXISTS`.
3. `register over soft-deleted 409` — seed `gone@test.com, deleted` → 409 `EMAIL_EXISTS` (Review Focus 4).
4. `register validation 422` — bad email / short password → 422 code `VALIDATION_ERROR` (assert code, not message).
5. `login ok / wrong password 401 / unknown 401 / soft-deleted 401` — status+code asserts (`code UNAUTHORIZED` for unknown/bad-password family). Additionally seed `password_hash` = `password_hash('oldpass', PASSWORD_BCRYPT, ['cost'=>12])` and login as that — proves PHP-generated hashes verify (true Nodebcrypt interop lands at Task 8 on real data).
6. `refresh reissues with fresh role` — seed user, `UPDATE users SET role='admin'`, call `auth_refresh()` with an EXPIRED token (build by `jwt_sign_token` then manually editing claim exp? No — sign a token with `exp = time()-10` via the harness (mirror of `jwt_sign_token` with backdated claims)) → 200, `user.role === 'admin'`.
7. `refresh harsh cases` — garbage token → 401 code `TOKEN_EXPIRED`; soft-deleted user → 401 `'User not found'` (exact, verbatim).
8. `me partial edits` — own `display_name` OK; email dup → 409 `EMAIL_EXISTS`; `{}` body → 422 `'Nothing to update'` (exact).
9. `change-password cycle` — wrong current → non-204 failure; correct → 204; login with NEW password → 200.
10. `account deletion cascades` — seed user + one class + one event + one status + one reset code row (fixtures via `query()` INSERTs from the SQL inventory), `auth_delete_account` → 204 raw `''`; re-login → 401; DB asserts all `deleted=1` + `password_resets` 0 rows.
11. `forgot+reset round trip` — forgot → 200 (exists-not-revealed shape); `last_log_code()` picks up the emitted 6-digit code; reset with `{email, code, new_password}` → 200-ish success; login with the NEW password → 200; stale-code second reset → non-2xx.
12. `forgot for unknown email` — same 200 shape; no user existence leak (identical body shape).
13. `forgot rate limit 429` — 6 posts for one email → 6th = 429 code `RATE_LIMITED` (bucket `forgot:<lowercase>` 5/3600).
14. `google rate limit 429` — 31 posts to `/auth/google` with `id_token:'x'` → calls 1–30 give 401 (INVALID_GOOGLE_TOKEN; limit fires POST-verification), 31st gives 429. (Verifies bucket `google` 30/60.)

- [ ] **Step 1: Write the 14 tests.**
- [ ] **Step 2: Run → expect failed 0. Any failure = treat as a real bug; fix php-backend and list under "Fixes found:" in the commit.**

Run: `& "C:\xampp\php\php.exe" php-backend\tests\run.php`

- [ ] **Step 3: Commit.**

```bash
git add php-backend/tests php-backend/src
git commit -m "test(php-backend): auth contract parity suite"
```

### Task 4: Sync contract tests (`/sync/*`)

**Files:**
- Test: `php-backend/tests/sync_test.php`

**Interfaces:**
- Consumes: bootstrap; handlers `sync_push`, `sync_pull`.
- Produces: fixes (if any) to `php-backend/src/sync.php`.

Test list (every test begins `db_reset()`):

1. `push inserts class and echoes client timestamp verbatim` — POST `{device_id:'dev1', classes:[{local_id:1, subject:'IT 101', room:'L201', professor:'Sir A', day:1, start_minutes:480, end_minutes:540, deleted:false, updated_at:'2026-11-01T08:00:00.123Z'}], events:[], class_statuses:[]}` → 200 with `classes[0] === {local_id:1, server_id:1, updated_at:'2026-11-01T08:00:00.123Z'}` — byte-exact echo (Review Focus 3); DB row `updated_at = '2026-11-01 08:00:00.123'`.
2. `push updates row by server_id then local_id` — push same local twice (2nd carries server_id from the 1st response) → same server_id returned; subject updated in DB; rowcount 1.
3. `push tombstone` — `deleted:true` → echoed; DB row `deleted=1`.
4. `push events personal vs broadcast` — non-admin `broadcast:true, department:'IT'` silently demoted to personal (DB `user_id` != null, `broadcast` falsy); `super_admin` broadcast persists (`user_id` null). `lead_minutes` accepted only from `[5,10,15,30]`; `lead_minutes:99` → row skipped (no response entry).
5. `push foreign broadcast event skipped` — seed broadcast row (user_id NULL, department `'EDUC'`, local_id 9); caller with department `'IT'` pushes an event with `server_id=<that row's id>` → 200 but no `events[]` entry for it.
6. `push status row skip when class unknown` — `class_statuses` entry whose `local_class_id` has no server class → 200, no echo entry, DB 0 rows; second push after inserting the class succeeds with server_id echo.
7. `push cursor upsert` — after 2 pushes `sync_cursors` has 1 row for the user with moving `last_push_at`; `device_id` from body; default `'unknown'` when absent (verified: sync.php:336).
8. `pull on empty DB` — `GET /sync/pull?since=2026-11-01T00:00:00.000Z` → 200 `{server_time, classes:[], events:[], class_statuses:[], office_statuses:[]}`; `server_time` ISO-Z regex (Review Focus 1).
9. `pull inclusive since + deleted visible` — seed 2 classes one `deleted=1`; pull `since=1970-01-01T00:00:00.000Z` → both present incl. tombstone; pull `since=<row2.updated_at iso>` → only row2. All delta `updated_at` values ISO-Z regex.
10. `pull office row scope` — seed 3 office rows (NULL-dept school-wide, OWN-dept, foreign-dept) → returns first two only.
11. `pull broadcast by dept` — `'IT'` caller sees the IT-broadcast event; `'EDUC'` caller does not.
12. `unauthenticated syncs 401` — push and pull without token → 401 code `UNAUTHORIZED`.

- [ ] **Step 1: Write the 12 tests.**
- [ ] **Step 2: Run → expect failed 0 (fixes noted in commit).**
- [ ] **Step 3: Commit.**

```bash
git add php-backend/tests/sync_test.php php-backend/src/sync.php
git commit -m "test(php-backend): sync contract parity suite"
```

### Task 5: Admin contract tests + `ctype_digit` hardening patch (TDD)

**Files:**
- Test: `php-backend/tests/admin_test.php` (tests FIRST)
- Modify: `php-backend/src/admin.php` (patch follows failing test)

**Interfaces:**
- Consumes: bootstrap; handlers `admin_list_users/admin_set_role/admin_set_department/admin_list_offices/admin_update_office`.
- Produces: hardened `admin_set_role(string $id)` / `admin_set_department(string $id)` with a new first guard (after `admin_caller()`):

```php
    if (!ctype_digit((string)$id)) {
        throw new ApiError(404, 'User not found', 'USER_NOT_FOUND');
    }
```

(Deliberate, documented improvement, unreachable through the app: Node's `(int)"abc" → 0`; the old port silently answered `{ok:true}`. Numeric-but-missing ids KEEP the Node behavior (`{ok:true}`) — do not "fix" that side out of scope.)

Test list:

1. `non-admin caller 403` — GET `/admin/users` as `role='user'` → 403 `FORBIDDEN`.
2. `unknown-token caller 401` — fresh table, token id 999 → 401 `UNAUTHORIZED`.
3. `super admin list — raw created_at passthrough` — seed 3 users → GET list → 200, `users` length 3, each `created_at` matches `/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$/` (Review Focus 1/5 — NO `Z`).
4. `dept admin sees dept + self; deptless self-only` — seed: id1 super(dept null), id2 admin('IT'), id3 user('IT'), id4 user(null dept), id5 user('EDUC') → as id2: users = {id2, id3} (department='IT' OR self); as id1 (super): all; as a dept admin with NULL department: only self.
5. `role change happy path + boundaries` — as id1: PATCH role of id3 `'admin'` → 200 `{ok:true}`; invalid role `'boss'` → 422 `VALIDATION_ERROR`; self-demotion (id1→id1 `'admin'`) → 422 `'Cannot demote yourself'` (exact); as id2 (dept admin) PATCH role → 403 `'Super admin required'` (exact).
6. **`role change with non-numeric id 404` (TDD driver)** — PATCH `/admin/users/abc/role` → EXPECT 404 `USER_NOT_FOUND`. First run: fails (`{ok:true}` from `(int)"abc"→0`). Then Step 2 implement, re-run green. Same assertion for `/department`.
7. `department assignment` — as id1: PATCH `{department:'AIS'}` → 200; `{department:null}` → clears (DB null). Numeric-but-missing id → `{ok:true}` (Node parity, documented).
8. `office list auto-seeds + raw updated_at` — as id1: GET → 200 `{offices:[...]}` exactly 3 rows (`guidance`,`clinic`,`registrar`), each `status='open'`, `user_id` non-null, `updated_at` matches the raw-DATETIME regex (Review Focus 5).
9. `office upsert update` — PATCH guidance `{status:'break', custom_message:'Back at 2pm'}` → 200; list shows it echoed.
10. `office upsert create branch` — hard-delete guidance row, PATCH guidance → 200, re-list shows 3 again.
11. `office boundaries` — unknown office name → 422 `'Unknown office'`; invalid status → 422 `'Invalid status'`; non-admin → 403.
12. `no rate limiting on admin routes` — 40 rapid GETs OK (no 429; admin has no bucket by design).

- [ ] **Step 1: Write all 12 tests (test 6 = driver).**
- [ ] **Step 2: Run → expect exactly test 6 failing.**

Run: `& "C:\xampp\php\php.exe" php-backend\tests\run.php`
Expected: `failed 1` (test 6), others pass.

- [ ] **Step 3: Apply the guard patch to BOTH handlers.**
- [ ] **Step 4: Re-run → `failed 0`**; `& "C:\xampp\php\php.exe" -l php-backend\src\admin.php` → clean.
- [ ] **Step 5: Update `php-backend/PROVENANCE.md` patch log** (append the ctype_digit entry + date).
- [ ] **Step 6: Commit.**

```bash
git add php-backend/tests/admin_test.php php-backend/src/admin.php php-backend/PROVENANCE.md
git commit -m "test(php-backend): admin suite + ctype_digit guard on admin path ids"
```

### Task 6: JWKS verifier replaces per-login tokeninfo (TDD, offline)

**Files:**
- Create: `php-backend/src/google_jwks.php`
- Create: `php-backend/tests/google_jwks_test.php` (tests FIRST, no network)
- Modify: `php-backend/src/auth.php` (dispatch switch), `php-backend/config.php` (new key)

**Interfaces:**

- New: `google_verify_jwks(string $idToken, string $clientId, ?callable $fetch = null): ?array` — claims array on success (`sub`, `email`, `email_verified`, `name`, `aud`, `iss` are the consumed keys), `null` on ANY failure. Same `?array` contract as `verify_google_id_token` (kept verbatim as the tokeninfo fallback).
- Default `$fetch` closure: GET `https://www.googleapis.com/oauth2/v3/certs` via cURL (10 s timeout, SSL verify) — parse `{"keys":[...]}`.
- Cache file: `php-backend/storage/cache/google_jwks.json` as `{"fetched_at":"<iso>","keys":[...]}`. Rules: cache valid if `fetched_at` < 24 h old; fetch failure + parseable cache → use the cache (offline resilience, Review Focus 5); cache read mismatch of `kid` → force one immediate re-fetch; unknown kid after refresh → null.
- PEM builder: `jwks_pem(string $n, string $e): string` — JWK base64url n/e → DER RSAPublicKey SEQUENCE (INTEGER n with 0x00 pad when high bit set, INTEGER e) → DER SubjectPublicKeyInfo (OID 1.2.840.113549.1.1.1 + BIT STRING) → `-----BEGIN PUBLIC KEY-----` PEM. Verify via `openssl_verify($input, $sig, $pem, OPENSSL_ALGO_SHA256) === 1`.
- Behavior parity with the tokeninfo path (pinned, auth.php:101-161): header `alg` must be exactly `'RS256'` (rejects `none` and HS256-confusion); `kid` required; `aud === $clientId`; `iss` ∈ `['accounts.google.com','https://accounts.google.com']`; `exp` (int) > `time()`.

Config addition to `php-backend/config.php`:

```php
    'google_verify'     => getenv('KLASIFY_GOOGLE_VERIFY') ?: 'jwt_jwks',
```

Auth dispatch (single edit replacing the call at auth.php:149):

```php
    $claims = cfg('google_verify') === 'tokeninfo'
        ? verify_google_id_token($idToken, $clientId)
        : google_verify_jwks($idToken, $clientId);
```

Test list (all offline — verification with the injected `$fetch` from `make_rs256_fixture`; the storage/cache file is scaffolded/cleaned by the tests directly):

1. `valid RS256 token verifies` → claims returned verbatim (sub/email/name/aud/iss).
2. `tampered signature → null` (flip one sig byte).
3. `wrong aud → null`; 4. `wrong iss → null`; 5. `expired exp → null`.
6. `alg confusion → null` — token header `alg: HS256`/`none` signed RS-ly → null; JWKS key with wrong `alg` → null.
7. `kid rotation forces one re-fetch` — first JWKS (kid 'test-kid-1'), token with kid 'test-kid-2': closure counts invocations: call 1 → missing kid → re-fetch (call 2) serving JWKS-2 → verify OK; a THIRD call would be a failure (assert invoke count ≤ 2).
8. `cached fallback when fetch fails` — scaffold `storage/cache/google_jwks.json` with `fetched_at = now-5 min` and keys = fixture JWKS-1; fetcher returns `false` → verify test-kid-1 token → SUCCESS via cache (resilience pin).
9. `stale cache with dead network → null` — same scaffold but `fetched_at = now-30 h`, fetcher false → null.
10. `tokeninfo fallback still present` — `function_exists('verify_google_id_token')` truthy (config escape hatch undamaged).

- [ ] **Step 1: Write the 10 tests.**
- [ ] **Step 2: Run → expected failure: `Call to undefined function google_verify_jwks()`.**
- [ ] **Step 3: Implement `src/google_jwks.php`, the config key, and the dispatch switch.**

Run: `& "C:\xampp\php\php.exe" php-backend\tests\run.php`
Expected: `failed 0` across ALL suites (3+4+12+12+10).
Run: `& "C:\xampp\php\php.exe" -l` on `src/google_jwks.php`, `src/auth.php`, `config.php` → clean.

- [ ] **Step 4: Update `php-backend/PROVENANCE.md`** patch log (JWKS verifier entry + `KLASIFY_GOOGLE_VERIFY` note).
- [ ] **Step 5: Commit.**

```bash
git add php-backend/src/google_jwks.php php-backend/src/auth.php php-backend/config.php php-backend/tests/google_jwks_test.php php-backend/PROVENANCE.md
git commit -m "feat(google): local JWKS RS256 verification; tokeninfo kept as config fallback"
```

### Task 7: Pre-deploy gate — full suite + ignore cache dir

**Files:**
- Modify: `php-backend/.gitignore` — ignore `storage/logs/*` (keep `.htaccess`) and `storage/cache/`.
- Modify: `php-backend/README.md` — add 2 lines: JWKS cache lives in `storage/cache/` (auto-created), override Google path with `KLASIFY_GOOGLE_VERIFY=tokeninfo`.

- [ ] **Step 1: Full suite green** — `& "C:\xampp\php\php.exe" php-backend\tests\run.php` → `failed 0`.
- [ ] **Step 2: Apply the ignore + README lines.**
- [ ] **Step 3: Commit.**

```bash
git add php-backend/.gitignore php-backend/README.md
git commit -m "docs(php-backend): JWKS cache + ops notes pre-deploy"
```

### Task 8: Deploy to XAMPP with the live dataset

No unit tests here — every step is a command with explicit expected output. This task briefly stops the Docker containers (port room, NOT retirement; rollback = `docker compose up -d`, listed in Step 8). The XAMPP MySQL must be admin-console-free: `C:\xampp\mysql_start.bat`.

- [ ] **Step 1: Dump live data FROM Docker.**

```powershell
docker exec klasify-mysql sh -c 'exec mysqldump -uroot -pklasify_dev klasify_sync' > "$env:TEMP\opencode\klasify_sync_dump.sql"
```
Expected: `Select-String 'CREATE TABLE' "$env:TEMP\opencode\klasify_sync_dump.sql"` shows ≥7 tables (users, classes, events, office_statuses, class_statuses, password_resets, sync_cursors) and `Select-String 'test@test.com'` finds the admin user row.

- [ ] **Step 2: Stop Docker containers** — `docker compose -f backend/docker-compose.yml down` (frees :3306; rollback exists in Step 8).
- [ ] **Step 3: Start XAMPP MySQL** — `C:\xampp\mysql_start.bat`; sanity: `cmd /c "C:\xampp\mysql\bin\mysql.exe -u root -e \"SELECT 1\""` → `1`.

- [ ] **Step 4: Schema + data import.**

```powershell
cmd /c "C:\xampp\mysql\bin\mysql.exe -u root < docs\mysql_schema.sql"
cmd /c "C:\xampp\mysql\bin\mysql.exe -u root klasify_sync < $env:TEMP\opencode\klasify_sync_dump.sql"
```
(First: installs the schema incl. `rate_limit_hits` DDL from Task 1. Second: re-imports existing data — Node-era schema matches, inserts are plain.)
Expected: `cmd /c "C:\xampp\mysql\bin\mysql.exe -u root klasify_sync -e \"SELECT id,email,role FROM users WHERE email IN ('test@test.com','clarisse.sync@test.com')\""` → both rows present; `SELECT COUNT(*) FROM users` ≥ 5.

- [ ] **Step 5: Copy `php-backend` into the webroot — deterministic, excludes tests:** `robocopy php-backend C:\xampp\htdocs\klasify-api /E /XD tests /NFL /NDL /NJH /NP` (robocopy exit 0–3 = success; ≥4 = real failure).

- [ ] **Step 6: Apache smoke — 8 curl checks, ALL must pass before proceeding.**

```powershell
# token for checks C–H from step B
$t = (curl.exe -s -X POST http://127.0.0.1/klasify-api/auth/login -H "Content-Type: application/json" -d '{\"email\":\"test@test.com\",\"password\":\"password123\"}' | ConvertFrom-Json).token
# A. health
curl.exe -s http://127.0.0.1/klasify-api/health                          # → {"status":"ok","version":"1.0.0"}
# B. login with a Node-era account (bcrypt interop — Review Focus 2; STOP on failure) → 200 with user id 1
# C. register fresh → 201
curl.exe -s -X POST http://127.0.0.1/klasify-api/auth/register -H "Content-Type: application/json" -d '{\"email\":\"smoke.norm@example.com\",\"password\":\"smoke1234\",\"display_name\":\"Smoke Norm\",\"department\":\"AIS\"}'
# D. office list → 200 {"offices":[...]}
# E. office upsert → 200 {"ok":true}
curl.exe -s -X PATCH http://127.0.0.1/klasify-api/admin/office-statuses/guidance -H "Authorization: Bearer $t" -H "Content-Type: application/json" -d '{\"status\":\"closed\"}'
# F. restore open (same shape)
# G. sync pull → 200 {"server_time":...,"classes":[...]}
curl.exe -s "http://127.0.0.1/klasify-api/sync/pull?since=2026-01-01T00:00:00.000Z&device_id=smoke" -H "Authorization: Bearer $t"
# H. error shapes (frozen contract):
curl.exe -s -i http://127.0.0.1/klasify-api/bogus                        # → 404 {"error":"Not found","code":"NOT_FOUND"}
curl.exe -s -i -X PATCH http://127.0.0.1/klasify-api/auth/me -H "Content-Type: application/json" -H "Authorization: Bearer $t" -d '{ Not JSON '   # → 422 {"error":"Malformed JSON body","code":"VALIDATION_ERROR"}
```

- [ ] **Step 7: Firewall for TECNO** (admin shell): `netsh advfirewall firewall add rule name="Klasify API 80" dir=in action=allow protocol=TCP localport=80`. Verify from another host: `curl http://192.168.1.67/klasify-api/health` → 200.

- [ ] **Step 8: Rollback plan (documented; execute only if Steps 3–7 fail irrecoverably):** `docker compose -f backend/docker-compose.yml up -d` → Node is back on :8080 with its data; `C:\xampp\mysql\mysql.stop.bat`; delete `C:\xampp\htdocs\klasify-api`.

### Task 9: TECNO device checklist (manual — the retirement gate)

User-driven; record outcomes inline. Any FAIL → report + re-run after fix; do NOT proceed to Task 10 on any failure. Rollback per Task 8 Step 8.

- [ ] **Step 1: Rebuild + install the debug/release run** — `flutter run --release --dart-define=KLASIFY_API_URL=http://192.168.1.67/klasify-api` (or `flutter build apk --release --dart-define=...` then install).
- [ ] **Checklist item 1: password login** `test@test.com` / `password123` (live-data user; doubles as Node-token/age hash interop proof).
- [ ] **Checklist item 2: Google sign-in Both branches** — unknown account → `ACCOUNT_NOT_FOUND` (404) with the canonical message; registered account succeeds.
- [ ] **Checklist item 3: department signup flow** (IT / AIS / BA / EDUC enforced).
- [ ] **Checklist item 4: superadmin promote/demote + dept assignment** from the in-app admin screen.
- [ ] **Checklist item 5: office edit + propagation** — set guidance closed from another login; Today strip reflects it on the device.
- [ ] **Checklist item 6: dept-admin broadcast visibility only** (item 4's branch).
- [ ] **Checklist item 7: class/event sync round-trip** — offline add class+event → back online → ids accepted; then re-pull shows them on a second login.
- [ ] **Checklist item 8: forgot+reset flow** — the reset code shows up in `C:\xampp\htdocs\klasify-api\storage\logs\app.log`.
- [ ] **Gate:** all 8 → proceed to Task 10; any fail → STOP, fix, re-run the failed item only.

### Task 10: Cutover — retire Node, cut docs, verify, push

**Files:**
- Modify: `lib/screens/profile/reset_password_screens.dart` (the zip's 2-line copy change)
- Delete: `backend/**` (Node: `src/{auth,admin,sync,db,jwt,server}.js`, `server.js`, `Dockerfile`, `docker-compose.yml`, `package.json`, `package-lock.json`, `node_modules/`, `README.md`)
- Modify: `docs/DEPLOYMENT.md` (rewrite for XAMPP), `docs/ROADMAP.md` (runtime switch + new dev base URL), `docs/sync_api_contract.md` (exactly the 2 hosting-note lines that differed in the zip)

- [ ] **Step 1: Apply the reset-screen copy change** — replace the "docker logs klasify-api" line with "storage/logs/app.log on the API server" exactly as in the zip (4-line diff seen earlier).
- [ ] **Step 2: Delete `backend/`** — `git rm -r backend` (tracks removal of tracked files), then `Remove-Item -Recurse -Force backend` for leftovers (untracked `node_modules/` if gitignored).
- [ ] **Step 3: Rewrite `docs/DEPLOYMENT.md`** for XAMPP — requirements (PHP 8.2.12 / XAMPP), schema import, data note (`klasify_sync_dump` step from Task 8 coined), htdocs copy, app rebuild with `--dart-define`, firewall note, `storage/logs/app.log` as the reset-code sink (replaces "docker logs klasify-api"), no rollback route (Docker is gone).
- [ ] **Step 4: Update `docs/ROADMAP.md`** — base-URL note: dev backend now `http://<PC-IP>/klasify-api` on XAMPP/PHP.
- [ ] **Step 5: Update the contract's 2 hosting-note lines** (matches the zip exactly: Base-URL line → XAMPP dev URL; reset-code location line → `storage/logs/app.log`).
- [ ] **Step 6: Update `php-backend/PROVENANCE.md`** — close the patch log (nothing left open from Tasks 3–6).
- [ ] **Step 7: Flutter verification.**

Run: `flutter test` → expected: same as the known baseline — 484 pass; `bench6_accuracy_test.dart` (16 fixtures) may fail with "did not complete" as a known environment flake (re-run once; treat pass as pass).
Run: `flutter analyze` → clean.

- [ ] **Step 8: Commit + push (explicit paths only).**

```bash
git add lib/screens/profile/reset_password_screens.dart docs/DEPLOYMENT.md docs/ROADMAP.md docs/sync_api_contract.md php-backend/PROVENANCE.md
git rm -r backend
git commit -m "feat!: retire Node/Docker backend; XAMPP PHP deployment is canonical"
git push
```

- [ ] **Step 9: Final post-cutover smoke (3 checks)** — `/health` 200; login test user 200; office list 200.

---

## Self-review notes

- Spec coverage: every design-doc phase maps to a task (adopt → 1; harness → 2; auth → 3; sync → 4; admin+patch → 5; JWKS → 6; pre-deploy → 7; deploy → 8; device → 9; cutover → 10). Provenance threads 1, 5, 6, 10.
- Interfaces were read off the adopted source, not guessed (handler list and line references pinned in Tasks 2–6).
- Review Focus lines each pin to owning tasks: 1 → 3/4/5; 2 → 8/9; 3 → 4; 4 → 3; 5 → 6.
- No `git add -A` anywhere; mockup files cannot be staged.
- `klasify_test` DB reconnects each suite run from the real `docs/mysql_schema.sql` (single source of truth — no schema drift between doc and harness).
