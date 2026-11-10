# Klasify Sync API (PHP + MySQL on XAMPP)

The sync and auth backend for the Klasify app, written in PHP. It runs on
XAMPP's Apache and MySQL, so no Docker and no Node.js are needed.

```
Flutter app (phone or PC)  --HTTP-->  Apache + PHP (XAMPP)  --SQL-->  MySQL / MariaDB (XAMPP)
                                                                         ^
                                                                    HeidiSQL (browse data)
```

Every endpoint, status code, error code, and response shape matches
`docs/sync_api_contract.md`, so the Flutter app needs only a new base URL.
Admin rules (roles, provisioning, office availability) live in
`docs/ADMIN.md`.

## Requirements

- **XAMPP** with PHP **8.0 or newer** (XAMPP 8.x is fine)
- The **curl** extension enabled (on by default in XAMPP)
- **HeidiSQL** (optional, to browse the data)

## Setup

1. **Start Apache and MySQL** in the XAMPP Control Panel. Both must be green.

2. **Create the database.** Open phpMyAdmin at `http://localhost/phpmyadmin`,
   go to **Import**, and choose `docs/mysql_schema.sql` from the project. This
   creates the `klasify_sync` database and all its tables. (HeidiSQL can also
   run the file.)

3. **Copy this folder into XAMPP** and name it `klasify-api`:
   - Windows: `C:\xampp\htdocs\klasify-api\`
   - Mac: `/Applications/XAMPP/htdocs/klasify-api/`

4. **Check that it works.** Open `http://localhost/klasify-api/health`. You
   should see:
   ```json
   {"status":"ok","version":"1.0.0"}
   ```

## Settings

Edit `config.php` (or set the matching environment variables):

| Setting | Default | Notes |
|---|---|---|
| `db_host` / `db_port` | `127.0.0.1` / `3306` | XAMPP's MySQL |
| `db_name` | `klasify_sync` | created by the schema file |
| `db_user` / `db_pass` | `root` / *(empty)* | XAMPP's defaults |
| `jwt_secret` | placeholder | **change it** to a long random string before real use |
| `google_verify` | `jwt_jwks` | `jwt_jwks` (default) verifies Google ID tokens locally against the JWKS; `tokeninfo` falls back to Google's endpoint |

## Running the Flutter app against it

Use your PC's LAN IP (for example `192.168.1.5`), never `localhost`, because
a phone reaches the API over Wi-Fi:

```
flutter run --dart-define=KLASIFY_API_URL=http://192.168.1.5/klasify-api
```

Notes:
- Allow Apache through the Windows firewall, and make sure your phone and PC
  are on the same Wi-Fi.
- If Apache won't start because port 80 is taken (Skype, IIS, or another
  server often do this), change Apache's port in the XAMPP config. Then the
  URL becomes `http://192.168.1.5:8081/klasify-api`.
- Release builds of the app require HTTPS. For a real release, put the API
  behind an HTTPS reverse proxy as described in `docs/DEPLOYMENT.md`.

## Password reset codes

No email server is configured yet. Reset codes are written to
`storage/logs/app.log`. Open that file to read the 6-digit code during testing.

## Google sign-in troubleshooting

If Google sign-in always answers `INVALID_GOOGLE_TOKEN`, PHP probably can't
verify Google's HTTPS certificate. Open `php.ini` (XAMPP Control Panel, then
**Config** next to Apache, then **PHP (php.ini)**), set `curl.cainfo` to the
`cacert.pem` file that ships with XAMPP, restart Apache, and try again.

## Folder layout

```
index.php        Router: CORS, route table, error handling
config.php       Settings (not served to browsers)
.htaccess        Sends all requests to index.php
src/common.php   Database, JSON, JWT, timestamps, rate limiting, logging
src/auth.php     /auth/* routes
src/sync.php     /sync/push and /sync/pull
src/admin.php    /admin/* routes (user roles, departments, office statuses)
src/google_jwks.php  Local RS256 verification of Google ID tokens (JWKS, 24h cache)
storage/logs/    app.log (reset codes, skipped sync rows, server errors)
storage/cache/   google_jwks.json (auto-created, gitignored)
```

## Notes on the migration

- **Existing accounts keep working.** Passwords hashed by the Node API are
  bcrypt hashes that PHP verifies directly. If `KLASIFY_JWT_SECRET` stays the
  same, existing sign-in tokens stay valid too.
- **Rate limits are stored in the database** (`rate_limit_hits`, created
  automatically on first use), so they hold across PHP requests.
- **Google sign-in** verifies the ID token locally against Google's published
  JWKS (RS256), cached for 24 hours in `storage/cache/google_jwks.json`. Set
  `KLASIFY_GOOGLE_VERIFY=tokeninfo` to fall back to Google's tokeninfo
  endpoint. No Composer packages are needed.
- **Dates** are stored in UTC and sent as ISO 8601 strings, as before.
