# Design: PHP/XAMPP backend migration

Date: 2026-11-09
Status: AMENDED 2026-11-09 (evening) — adopted-base decision recorded; awaiting user approval to execute
Supersedes (eventually): the Node.js/Docker backend (`backend/`)

## Amendment: adopted PHP base (replaces "build Phases A–D from scratch")

A complete PHP/XAMPP port of the current backend arrived as
`klasify-backend-php.zip` (provenance to be recorded with the user). It was
audited file-by-file against this doc and the query inventory:

- **Verdict: adopt as the runtime base**, copied into the repo as
  `php-backend/`. Contract-faithful (all 17 endpoints, identical error
  strings, JWT claims `user_id`/`email`/`iat`/`exp` HS256 7-day, bcrypt cost
  12, Node-token and race password-hash compatibility, UTC DATETIME(3) with
  verbatim `updated_at` echo, broadcast matrix, `<=>` matching, cursor
  upserts, office seeding/upsert with raw-DATETIME passthrough).
- It is strictly better than this doc's runtime spec in three spots: CORS
  adds `PATCH`; the rate-limit table (`rate_limit_hits`) self-migrates at
  first use; logs go to `storage/logs/app.log` with the reset-screen hint
  text already updated to match (2-line Flutter change to apply at cutover).
- **Audit patches required before adoption:**
  1. `ctype_digit` guard on `/admin/users/{id}` and
     `/admin/office-statuses/{office}` path params (currently `(int)"abc"`
     would silently succeed).
  2. Add the `rate_limit_hits` DDL to `docs/mysql_schema.sql`
     (documentation parity; the table also self-creates in code).
  3. `.htaccess` gains the CGI/FastCGI authorization passthrough rule
     (`SetEnvIf Authorization ...`) so the Bearer header survives non-mod_php
     hosting; XAMPP's mod_php works today.
- **Google verification upgrade (provenance-independent):** replace the
  zip's per-login `oauth2.googleapis.com/tokeninfo` cURL call with a local
  RS256 JWKS verifier (~100 lines, fetched once and cached in temp,
  injectable JWKS source for tests). Config switch `google_verify =
  jwt_jwks (default) | tokeninfo (fallback)`. Rationale: offline-testable in
  the parity harness, no per-sign-in internet dependency beyond the cached
  key window, and matches google-auth-library's verification semantics.
- **Phases A–D are replaced by:** adopt + patches + JWKS verifier + the
  zero-Composer parity harness (`tests/run.php` still has the full contract
  test list from this doc — the zip ships no tests). Phase E (data dump,
  XAMPP deploy, device checklist) and Phase F (retire Node, docs) stand.

## Why

The user wants Klasify to run on **XAMPP (Apache + PHP + MariaDB)** instead of
Node.js in Docker, and confirmed **full replacement**: once the PHP backend is
verified, the Node/Docker stack is retired.

Precedent: the Node backend was itself written as a port *from* a PHP
implementation (`backend/src/sync.js`: "Ports routes/sync.php exactly";
`backend/src/auth.js`: "response shapes the PHP implementation served").
The old PHP files are **gone** (user confirmed), so this is a fresh rewrite
against the same frozen contract, not a recovery.

The Flutter app talks only to `AuthService.baseUrl`
(`--dart-define=KLASIFY_API_URL=...`). **No Dart changes are needed** — only a
rebuild with the new base URL. The contract
(`docs/sync_api_contract.md`) — routes, methods, status codes, error codes,
JSON shapes — is frozen and every PHP response must match it exactly.

## Frozen parity rules (the whole point of a "migration", not a rewrite)

Byte-for-batch semantic parity with the Node service, verified route by route
on the device before Node is removed:

1. **Routes (relative to the base URL):** `GET /health`; `POST /sync/push`,
   `GET /sync/pull`; `POST /auth/register|login|google|refresh`
   `change-password|forgot-password|reset-password`, `DELETE /auth/account`,
   `PATCH /auth/me`; `GET /admin/users|office-statuses`,
   `PATCH /admin/users/:id/role|department`,
   `PATCH /admin/office-statuses/:office`.
2. **Status/error codes:** `200/201/204/401/403/404/409/422/429/500` and
   `UNAUTHORIZED, TOKEN_EXPIRED, INVALID_CREDENTIALS, INVALID_GOOGLE_TOKEN,
   ACCOUNT_NOT_FOUND, EMAIL_EXISTS, VALIDATION_ERROR, RATE_LIMITED,
   FORBIDDEN, NOT_FOUND, SERVER_ERROR` — identical numbers and strings.
3. **Timestamps (two dialects, per endpoint — recheck result 2026-11-09):**
   - ISO-8601 millis + `Z` (`2026-11-09T12:34:56.789Z`): `expires_at`,
     `server_time`, and **all `updated_at` values in `/sync/push` responses
     and `/sync/pull` deltas** — the port of `toMysqlTimestamp` /
     `fromMysqlTimestampToIso` (always stored in **UTC** in `DATETIME(3)`).
   - Raw `DATETIME(3)` passthrough (`2026-11-09 12:34:56.789`, space
     separator, no timezone suffix, as mysql2's `dateStrings: true` returned
     them): `created_at` in `GET /admin/users` and `updated_at` in
     `GET /admin/office-statuses`. The app parses both dialects with
     `DateTime.tryParse`, so PHP must emit each endpoint's dialect exactly.
   - Push echoes the client's per-row `updated_at` back verbatim.
4. **JSON types:** booleans explode booleans (`deleted: !!Number(...)`)
   become real PHP booleans, IDs are real ints (PDO must not stringify
   BIGINTs).
5. **CORS** headers identical (`*`, `GET, POST, PUT, DELETE, OPTIONS`,
   `Content-Type, Authorization`) and `OPTIONS` → `204` empty; unmatched
   route → `404 {"error":"Not found","code":"NOT_FOUND"}`; malformed JSON →
   `422 VALIDATION_ERROR` ("Malformed JSON body"); uncaught error →
   `500 {"error":"Internal server error","code":"SERVER_ERROR"}` with
   internals only in the PHP error log.
6. **DB-level uniqueness (recheck):** `users.email` and `users.google_sub`
   are `UNIQUE` **across all rows including soft-deleted ones**. Every PHP
   create-path (`register`, google signup) and `PATCH /auth/me` must
   pre-check duplicates exactly as Node does so the API answers
   `409 EMAIL_EXISTS`, never a duplicate-key 500.
7. **Accepted divergence (documented):** an oversized JSON body returns
   `413` from Express but would surface as `422 VALIDATION_ERROR` under PHP
   (empty body → malformed). Sync payloads are far below both limits, so
   this is unreachable in practice; `post_max_size=8M` default is fine.

## Architecture

Single deployable folder, no Composer, no framework:

```
php-backend/
  index.php            # front controller: CORS, JSON in/out, 404/500 shapes
  .htaccess            # mod_rewrite: everything -> index.php (XAMPP ships it)
  src/
    .htaccess          # "Require all denied" — never web-reachable
    config.php         # DB creds, JWT secret, GOOGLE_CLIENT_ID; env override
    db.php             # PDO + native ints + session time_zone='+00:00'
    jwt.php            # HS256 sign/verify (hash_hmac) + Bearer middleware
    rate_limit.php     # DB-backed sliding window (replaces in-memory Maps)
    google_idtoken.php # pure-PHP RS256 verify against Google's JWKS
    auth.php           # 9 /auth handlers
    admin.php          # 5 /admin handlers
    sync.php           # /sync/push + /sync/pull
    user_ctx.php       # caller resolution, requireAuth, resolveCaller
  tests/
    run.php + *.php    # zero-dependency harness; route fns called directly
```

**Route logic is pure:** each handler is a PHP function
`fn(array $db, array $body, array $query, UserContext $caller): [int $status, array|null $body]`.
`index.php` is thin glue (read input, call handler, emit). This makes TDD
possible without Composer: `php tests/run.php` asserts status codes and body
shapes against a scratch `klasify_test` database.

**Database:** XAMPP MariaDB 10.4.x. `docs/mysql_schema.sql` imports as-is
(only standard constructs: `BIGINT AUTO_INCREMENT`, `DATETIME(3)` +
`CURRENT_TIMESTAMP(3) ON UPDATE`, `ENUM`, `CHECK`, FKs, the debugging
views). One **addition** (same file, versioned):

```sql
CREATE TABLE rate_limit_entries (
  id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  bucket       VARCHAR(190) NOT NULL,          -- e.g. 'email:foo@x.com', 'google'
  requested_at DATETIME(3)    NOT NULL,
  KEY idx_rate (bucket, requested_at)
) ENGINE=InnoDB;
```

The Node builds used in-memory Maps for throttles; Apache worker processes
don't share memory, so throttles move to this table:
- forgot-password: **max 5 per email per hour** (same numbers).
- /auth/google: **max 30 per minute globally**.

Its three queries (full inventory lives in
`docs/superpowers/specs/2026-11-09-php-xampp-sql-queries.md`):

```sql
-- count recent hits within the window
SELECT COUNT(*) AS n FROM rate_limit_entries
  WHERE bucket = ? AND requested_at > ?;
-- record the hit
INSERT INTO rate_limit_entries (bucket, requested_at) VALUES (?, ?);
-- opportunistic sweep inside the same bucket
DELETE FROM rate_limit_entries WHERE bucket = ? AND requested_at <= ?;
```

Old rows are deleted opportunistically on each check.

**Google Sign-In verification** (the only dependency-heavy piece) is
implemented in pure PHP using cURL: fetch Google's public key set
(`https://www.googleapis.com/oauth2/v3/certs`, cached 1h in
`sys_get_temp_dir()`), pick the key by `kid`, verify RS256 with
`openssl_verify`, then check claims `exp`, `iss`, `aud = GOOGLE_CLIENT_ID`,
`email_verified === true`, and read `sub`, `email`, `name`. The JWKS source is
injectable so the test harness can verify the whole path offline. Behaviour
parity to port: google_sub lookup first, then email (with
google_sub backfill); `mode: signin` → `404 ACCOUNT_NOT_FOUND` (never
provisions); `mode: signup` name preference is the **typed name** (100-char
cap) over the profile name; soft-deleted email/sub → `409 EMAIL_EXISTS`;
Google client id missing → `500` with today's message.

**JWT:** identical HS256 `{ user_id, email }` claims, `KLASIFY_JWT_SECRET`,
7-day TTL, `expires_at` in auth responses. Existing Node-issued tokens keep
verifying after the switch (same secret, same algorithm), so users are not
logged out. `refresh` ignores expiration exactly like today; missing header →
`401 UNAUTHORIZED` "Missing token", bad/expired → `401 TOKEN_EXPIRED`.

**bcrypt:** cost 12 (`password_hash(..., PASSWORD_BCRYPT, ['cost' => 12])`).
Node's `bcryptjs` hashes (`$2a$`/`$2b$`) are verified fine by PHP's
`password_verify` — **existing users keep their passwords**.

## Data migration

1. `docker exec klasify-mysql mysqldump -uroot -pklasify_dev --databases klasify_sync > klasify_dump.sql`
2. Import the dump into XAMPP's MariaDB after running the (updated)
   `docs/mysql_schema.sql` (dump may carry full schema; pick one path in the
   implementation — plan: import dump, then add `rate_limit_entries`).
3. All live test users, classes, events (ids 3–5), office statuses, cursors
   carry over — including bcrypt password hashes.

## XAMPP setup (documented in the rewrite of docs/DEPLOYMENT.md)

- Source of truth stays in the repo (`php-backend/`). Deployment = copy the
  folder to `C:\xampp\htdocs\klasify\` → base URL `http://<PC-IP>/klasify`
  (or `http://<PC-IP>:80` if placed at `htdocs` root instead — decide at
  build time, one dart-define either way).
- `.htaccess` rewrite rules are inside the folder, so htdocs copy "just
  works"; no vhost needed.
- PHP runtime hardening inside `index.php` (`ini_set('display_errors','0')`
  + shutdown handler → contract 500 shape).
- MariaDB session must run in UTC (`SET time_zone = '+00:00'` after
  connecting) to match mysql2's `timezone: 'Z'` behaviour.
- Windows firewall: allow inbound :80 for the TECNO on the same Wi-Fi
  (192.168.1.67 today).
- PHP extensions required (all ship enabled in XAMPP by default): `pdo_mysql`
  (DB), `openssl` (Google RS256 verify), `curl` (JWKS fetch).
- `GET /health` is reached by ops/monitoring only — the Flutter app never
  calls it (recheck confirmed) — but it is kept verbatim for tunnel and
  status checks.
- Cloudflare tunnel story from the deferred deployment work still applies —
  the tunnel then points at Apache instead of the Node container.
- Reset codes: with no SMTP, the code is written to the PHP error log
  (`C:\xampp\php\logs\php_error_log` where configured) — document where the
  dev finds it (replaces "docker logs klasify-api").

## Testing strategy (TDD per phase, matching the superpowers flow)

`php tests/run.php` (no Composer) drives handler functions in-process against
a disposable `klasify_test` DB that is dropped/re-created per run. Test files
mirror route groups; cases include, minimally — these are the behaviours we
empirically verified on the Node stack and must re-verify on PHP:

- register: 201 shape; 422 bad email / short password; 409 EMAIL_EXISTS.
- login: 200 with `user` incl. role/department; 401 INVALID_CREDENTIALS;
  soft-deleted account not loginable; **legacy Node bcrypt hash verifies**.
- google: missing token 422; bad token 401 INVALID_GOOGLE_TOKEN (mock JWKS);
  signin-unknown → 404 ACCOUNT_NOT_FOUND; signup creates with typed name +
  department; signup onto soft-deleted email → 409 EMAIL_EXISTS; google_sub
  backfill on email match; rate limit 429 after 30/min.
- refresh: reuses expired token (7-day grace not required beyond signature);
  returns fresh `user` (role/department edits present without re-login).
- me/change-password/forgot/reset: status + code parity incl. wrong-code 422,
  always-200 forgot response, one-active-code rule, throttle 429 (table-based).
- account delete: 204 + soft-delete cascade.
- admin: non-admin 403; dept admin scoped list (self row included when dept
  empty); role transitions super-only; cannot-demote-yourself 422; department
  PATCH super-only; office auto-seed on GET; PATCH upsert + custom_message
  null clearing.
- sync push/pull: upsert by server_id → local_id; response echo shapes;
  invalid rows skipped without breaking the request; foreign-event skip;
  broadcast permission matrix (super-admin any dept / dept admin own dept /
  non-admin broadcast ignored); pull visibility filter incl. school-wide and
  own-dept broadcasts; tombstones included; class-status class_id resolution
  skip; cursor upsert with device_id; timestamps round-trip with millis.
- health + 404 + malformed JSON + CORS/OPTIONS parity (HTTP-level, via
  `php -S localhost:8099 -t .` in the test script and curl).

Definition of "verified" (gates Node retirement):
`php tests/run.php` all green **and** manual end-to-end device run from the
TECNO against the PHP URL covering: password login, google sign-in
(ACCOUNT_NOT_FOUND), department sign-up, promote/demote with dept assignment,
office edit + propagation, dept-admin broadcast visibility/read-only,
class/event sync round-trip, forgot+reset code flow. Only then: stop Docker,
remove `backend/` with its whole inventory —
`src/ (auth.js admin.js sync.js db.js jwt.js server.js)`, `Dockerfile`,
`docker-compose.yml`, `package.json` + `package-lock.json`, `node_modules/`,
`README.md` — rewrite DEPLOYMENT.md for XAMPP, note the new base URL in
ROADMAP, and add the PHP hosting note to `docs/sync_api_contract.md`
(`docs/ADMIN.md` stays valid: it documents the contract, not the runtime).

## Phase plan (implemented after this doc's approval, via writing-plans)

- **A. Skeleton + harness + health:** config/db/jwt/db helpers, `index.php`
  glue, CORS/404/422/500 parity, `php tests/run.php` harness, schema
  `rate_limit_entries`, health test green.
- **B. /auth (9 routes):** register, login, refresh, me, account, password
  flows, rate-limit table wiring; google_idtoken with injectable JWKS +
  google route; contract tests.
- **C. /admin (5 routes):** caller resolution rules + office seed/upsert +
  user role/department; contract tests.
- **D. /sync (2 routes + cursor upserts):** the largest port; contract tests
  for every row-matching/broadcast/tombstone rule.
- **E. Migration + XAMPP:** dump/import, folder copy or vhost, firewall,
  Flutter rebuild with new base URL, device verification checklist above.
- **F. Retire Node:** stop containers, delete `backend/`,
  DEPLOYMENT/ROADMAP/contract-doc updates, final `flutter analyze` + test run.

Phases A–D stay inside the repo and never touch Flutter; phase E is the
cutover; F is the retirement. Any phase can stop cleanly: the Node stack
remains the live backend until E completes.

## Non-goals

- No Composer, no framework, no ORM, no Redis, no SMTP (unchanged from Node).
- No new endpoints/features during the migration (parity only). Navigator
  (#6) and real-time-location work resumes after cutover.
- No HTTPS termination on Apache (the tunnel still handles TLS).

## Risks

| Risk | Mitigation |
|---|---|
| MariaDB ≠ MySQL 8 differences inline объем (`<=>` operator etc.) | All schema constructs verified standard; `<=>` supported by MariaDB; device-level sync test before cutover |
| Timezone drift (PHP `date.default_timezone`, MariaDB session tz) | Forced `'UTC'` in code + `SET time_zone '+00:00'`; millis format tests |
| PDO returns BIGINT/DECIMAL as strings → wrong JSON types | `PDO::ATTR_EMULATE_PREPARES=false`, `ATTR_STRINGIFY_FETCHES=false`, explicit casts in handlers; type tests |
| Apache rewrites / .htaccess friction on XAMPP | Ship `.htaccess` in-folder; fallback documented (AllowOverride); test URL parity first |
| Port 80 occupied on Windows (IIS/other) | Detect + document service disable step |
| Google verification without google-auth-library | Injectably-tested JWKS verifier + real-device Google sign-in run before cutover |
| Two backends drifting mid-migration | Frozen contract; only migration-phase bugfix parity changes; Node deleted immediately after device verification |
| Forgot reset code visibility for users | Documented log location (php_error_log) in DEPLOYMENT.md |

## Open items (resolved during implementation, minor)

- Exact placement in htdocs (`htdocs/klasify/` vs `htdocs/api/` → base URL
  string) — implementation detail, one dart-define either way.
- Whether the final dump-import keeps Docker's `klasify_sync` name (yes, to
  keep config identical).
