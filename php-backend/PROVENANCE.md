# Provenance & adoption record

- Source: `klasify-backend-php.zip` (downloaded to `C:\Users\clarisse sibug\Downloads\`)
- SHA-256: `A5F0E8A444741D9B4535759B6082893CD37D0B164510950DB18A34C46879D20B`
- Provenance (user-provided, 2026-11-09): built by **another AI tool** as a
  PHP/XAMPP port of the same `docs/sync_api_contract.md`; the user reviewed
  and chose it as the migration base.
- Audited against: the frozen contract (`docs/sync_api_contract.md`) and the
  SQL query inventory (`docs/superpowers/specs/2026-11-09-php-xampp-sql-queries.md`),
  file by file, 2026-11-09. Audit verdict: contract-faithful; JWT claims
  (`user_id`, `email`, `iat`, `exp`, HS256, 7-day TTL) and bcrypt cost 12 are
  compatible with the Node-era data. No eval/exec/shell calls; cURL only to
  Google's tokeninfo endpoint; writes confined to `storage/logs/`.

## Patch log (deviations from the adopted zip, dated)

- 2026-11-09 (adoption commit): `.htaccess` gains the
  `SetEnvIf Authorization` passthrough so Bearer headers survive CGI/FastCGI
  hosting (mod_php under XAMPP doesn't need it, hosts do).
- 2026-11-09 (adoption commit): `rate_limit_hits` DDL added to
  `docs/mysql_schema.sql` for documentation parity (the code still
  self-creates the table on first use).
- 2026-11-09 (test harness commit): single test seam in
  `src/common.php:read_json_body()` — CLI harness injects request bodies via
  `$GLOBALS['KLASIFY_TEST_BODY']`; production behavior unchanged.
- 2026-11-09 (admin suite, Task 5): `src/admin.php` gained a `ctype_digit`
  guard on `admin_set_role` and `admin_set_department` path ids — a non-numeric
  id now answers 404 / USER_NOT_FOUND instead of the old `{ok:true}` (Node's
  `(int)"abc"` cast made this unreachable through the app). Numeric-but-missing
  ids keep the Node-parity `{ok:true}` (documented, not "fixed").
- 2026-11-09 (Google suite, Task 6): `src/google_jwks.php` added — local RS256
  JWKS verification (`google_verify_jwks`, `jwks_pem` + DER helpers) with a 24h
  on-disk cache at `storage/cache/google_jwks.json`, single re-fetch on an
  unknown `kid`, and stale-cache fallback on a failed fetch. `config.php`
  gained `google_verify` (`KLASIFY_GOOGLE_VERIFY`, default `jwt_jwks`); `auth.php`
  dispatches on it, keeping `verify_google_id_token` as the `tokeninfo` fallback.
