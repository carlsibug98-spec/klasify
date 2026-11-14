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
| `debug_reset_codes` | off | dev only: writes plaintext reset codes to `app.log` (`KLASIFY_DEBUG_RESET_CODES=1`) |

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

No email server is configured yet. Plaintext reset codes are written to
`storage/logs/app.log` **only** when the API process has
`KLASIFY_DEBUG_RESET_CODES=1` (or `debug_reset_codes` is `'1'` in
`config.php`). Leave it off in production and wire an SMTP mailer; otherwise
the forgot-password flow creates a code that nobody can receive. If you enable
it for a local demo, clear `app.log` afterwards and keep the file out of
backups.

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
