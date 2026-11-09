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
- Pending (TDD, admin suite): `src/admin.php` `ctype_digit` guard on admin
  path ids — will be appended here with its date when it lands.
- Pending (TDD, Google suite): `google_verify` config switch + local JWKS
  RS256 verifier in `src/google_jwks.php` replacing the per-login tokeninfo
  cURL call; tokeninfo kept as fallback via `KLASIFY_GOOGLE_VERIFY=tokeninfo`.
