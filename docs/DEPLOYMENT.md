# Klasify backend deployment (XAMPP / PHP)

The sync and auth backend is PHP + MySQL on XAMPP. No Docker, no Node.js.

## Requirements

- **XAMPP** with PHP 8.0+ (XAMPP 8.x is fine) — `C:\xampp`
- The **curl** extension enabled (on by default in XAMPP)
- A MySQL/MariaDB instance (XAMPP's, on 127.0.0.1:3306)

## Local dev setup

1. Start Apache and MySQL in the XAMPP Control Panel.
2. Create the database: `mysql -u root < docs/mysql_schema.sql` (creates `klasify_sync`).
3. Copy `php-backend/` into `C:\xampp\htdocs\klasify-api\` (exclude `tests/`).
4. Verify: `http://localhost/klasify-api/health` → `{"status":"ok","version":"1.0.0"}`.
5. Allow port 80 through the Windows firewall for LAN access:
   `netsh advfirewall firewall add rule name="Klasify API 80" dir=in action=allow protocol=TCP localport=80`

## Settings

Edit `config.php` (or set env vars):

| Setting | Default | Notes |
|---|---|---|
| `db_host` / `db_port` | `127.0.0.1` / `3306` | XAMPP's MySQL |
| `db_name` | `klasify_sync` | created by the schema file |
| `db_user` / `db_pass` | `root` / *(empty)* | XAMPP's defaults |
| `jwt_secret` | placeholder | **change it** to a long random string before real use; changing it signs out every existing session |
| `google_client_id` | project's web client id | used to verify Google sign-in |
| `google_verify` | `jwt_jwks` | `jwt_jwks` (local RS256) or `tokeninfo` (fallback) |
| `mail_transport` | `smtp` | `smtp` sends real reset email; `mail` uses PHP `mail()`; `log` is dev only |
| `smtp_host` / `smtp_port` | *(empty)* / `587` | SMTP server for reset email |
| `smtp_secure` | `tls` | `tls` (STARTTLS, 587), `ssl` (implicit TLS, 465), `none` (local test only) |
| `smtp_user` / `smtp_pass` | *(empty)* | SMTP credentials; use a provider app password |
| `mail_from` / `mail_from_name` | `no-reply@klasify.local` / `Klasify` | sender the provider allows |
| `debug_reset_codes` | off | dev only: logs plaintext codes and defaults the transport to `log` |

Generate a strong secret (96 hex characters) without committing it:

```powershell
$b = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
($b | ForEach-Object { $_.ToString('x2') }) -join ''
```

Put it in `config.php` as `jwt_secret`, or set `KLASIFY_JWT_SECRET`. Never
reuse the repository placeholder: it is public, so anyone could forge admin
tokens.

## Database migration (existing installs)

Fresh installs get every column from `docs/mysql_schema.sql`. Upgrading an
existing `klasify_sync` database needs the revocable-session column:

```
mysql -u root klasify_sync < docs/migrations/2026-11-14_token_version.sql
```

Existing users default to `token_version = 0`, so current sessions keep
working after the ALTER. Password changes, resets, and account deletion bump
the version and revoke older tokens.

Verify with `SHOW COLUMNS FROM users LIKE 'token_version';`.

Then apply the 2026-11-18 normalization migration. It drops columns, so stop
the API first and take a backup:

```
mysqldump -u root --databases klasify_sync > klasify_sync_backup.sql
mysql -u root klasify_sync < php-backend/migrations/2026-11-18-normalize.sql
```

It moves departments into their own table, keys offices on
`(office_name, department_id)`, stores device-local ids per device, keeps one
live password-reset code per account, and splits rate-limit counters into
`(scope, subject)`. DDL commits implicitly in MySQL, so the script is not
re-runnable: it either finishes or you restore the backup. A fresh install from
`docs/mysql_schema.sql` already has this shape; to confirm the result, dump the
structure of the migrated database and of a freshly created one and compare:

```
mysqldump -u root --no-data --skip-comments klasify_sync > migrated.sql
mysqldump -u root --no-data --skip-comments klasify_fresh   > fresh.sql
```

AUTO_INCREMENT values and view DEFINERs differ; every table definition should
otherwise match.

## Migrating from the old Node/Docker backend

1. Dump the live data: `docker exec klasify-mysql sh -c 'exec mysqldump -uroot -pklasify_dev klasify_sync' > klasify_sync_dump.sql`
2. Stop Docker: `docker compose -f backend/docker-compose.yml down`
3. Start XAMPP MySQL, import schema + dump:
   `mysql -u root < docs/mysql_schema.sql`
   `mysql -u root klasify_sync < klasify_sync_dump.sql`
4. Copy `php-backend/` → `C:\xampp\htdocs\klasify-api\` (exclude `tests/`).
5. Smoke test: `/health` 200, login `test@test.com`/`password123` 200 (Node bcrypt interop), `/admin/office-statuses` 200.

Existing accounts keep working: Node-issued `$2b$` bcrypt hashes verify under PHP, and the HS256 JWT secret is unchanged.

## Running the Flutter app against it

Use your PC's LAN IP (e.g. `192.168.1.67`), never `localhost`:

```
flutter run --dart-define=KLASIFY_API_URL=http://192.168.1.67/klasify-api \
            --dart-define=GOOGLE_WEB_CLIENT_ID=359657054360-0v7f3rlt56caci4h78v6kc0me91v2s4m.apps.googleusercontent.com
```

Release builds enforce HTTPS: `KLASIFY_API_URL` must be an absolute
`https://` URL or the app throws before sending any request. Debug/profile
builds keep the LAN HTTP default for the demo. Put production behind a TLS
reverse proxy (or an HTTPS virtual host) -- do not ship a release APK with an
`http://` URL.

## MySQL exposure

XAMPP's MySQL uses `root` with an empty password, so it must never listen on
the LAN. Keep `C:\xampp\mysql\bin\my.ini` under `[mysqld]` set to:

```ini
bind-address="127.0.0.1"
port=3306
```

Restart MySQL and verify with `SELECT @@bind_address, @@port;` (expect
`127.0.0.1`, `3306`) and `Get-NetTCPConnection -LocalPort 3306 -State Listen`
(`127.0.0.1`, never `0.0.0.0` or `::`). The API connects over loopback, so no
inbound firewall rule for `mysqld` is needed; remove or disable any
`mysqld`/MySQL inbound allow rules created by Windows Firewall prompts.

## Password reset codes

The forgot-password flow sends a 6-digit code over SMTP. Set `smtp_host`,
`smtp_user`, `smtp_pass`, and `mail_from` in `config.php`, or the matching
`KLASIFY_SMTP_*` / `KLASIFY_MAIL_FROM` environment variables. Use port 587 with
`smtp_secure = tls` (STARTTLS) or port 465 with `ssl` (implicit TLS); certificate
verification stays on. Gmail and most providers require an app password rather
than the account password, and they only accept a sender address you control.

Codes expire after 15 minutes and are single-use. Delivery failures are logged
to `storage/logs/app.log`; the endpoint still returns `200 {"ok":true}` so it
never reveals whether an address is registered. For a local demo without SMTP,
set `KLASIFY_DEBUG_RESET_CODES=1` to use the `log` transport, then read the code
from `app.log`. Clear that log afterwards and keep it out of backups.

## Google sign-in troubleshooting

Google sign-in verifies the ID token locally against Google's published JWKS (RS256), cached 24h in `storage/cache/google_jwks.json`. Set `KLASIFY_GOOGLE_VERIFY=tokeninfo` to fall back to Google's tokeninfo endpoint.

If Google sign-in always answers `INVALID_GOOGLE_TOKEN`, PHP probably can't verify Google's HTTPS certificate. Open `php.ini`, set `curl.cainfo` to the `cacert.pem` that ships with XAMPP, restart Apache.

## Folder layout

```
index.php        Router: CORS, route table, error handling
config.php       Settings (not served to browsers)
.htaccess        Sends all requests to index.php
src/common.php   Database, JSON, JWT, timestamps, rate limiting, logging
src/auth.php     /auth/* routes
src/sync.php     /sync/push and /sync/pull
src/admin.php    /admin/* routes
src/google_jwks.php  Local RS256 verification of Google ID tokens
storage/logs/    app.log (reset codes, skipped sync rows, server errors)
storage/cache/   google_jwks.json (auto-created, gitignored)
```
