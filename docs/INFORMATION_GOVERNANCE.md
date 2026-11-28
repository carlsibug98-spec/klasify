# Information governance

This document is the published data contract for Klasify. It records what the
app keeps, where a value came from, what is rejected, and how the information
is recovered. The implementation decisions are in
`docs/superpowers/specs/2026-11-28-information-governance.md`.

## Retention and disposition

- **Auto-backups** live in the app support directory under `auto_backups/`,
  one main file and up to six dated copies per account scope.
- Dated copies older than **120 days** (one academic semester) are removed on
  startup by `AutoBackupService.pruneExpiredBackups()`. The always-current
  file is never pruned, and manual exports are never deleted automatically.
- Deleting an account removes that scope's backup files via
  `deleteScopeBackups()`; other scopes' files are untouched.

## Provenance

Every record carries enough information to say where it came from:

| Source | Evidence |
|---|---|
| `manual` | Created in the app; `updated_at` from `lib/data/db_timestamps.dart` |
| `ocr` | Import review flags (`ocrReviewNeeded`, room and conflict notes) in `lib/features/schedule_import/utils/import_review_analysis.dart` |
| `sync` | `server_id` plus server `updated_at`, mapped by `lib/features/sync/data/sync_wire_mapper.dart` |
| `restored` | A backup payload decoded by `lib/utils/schedule_backup_codec.dart` (format marker, version, `exportedAt`) |

The values are a documentation standard, not a new column: no schema change
was needed to recover them.

## Conflict policy

`docs/sync_api_contract.md` defines last-write-wins per row on `updated_at`,
with the server winning ties. A strictly newer local edit is kept and
re-pushed. `PullSync` now counts those discarded server rows and
`SyncConflictNotice` shows a one-time, dismissible notice. LWW behaviour is
unchanged; only the user-visible part is new.

## Validation contract

Enforced before a row reaches SQLite; the database triggers repeat the same
rules:

- **Class** (`lib/data/validation/class_rules.dart`): subject ≥ 2 characters;
  room required; professor ≥ 2 characters; day 1–7; start in `[0, 1440)`; end
  after start and ≤ 1440; no overlapping classes in one batch
  (`validateNoOverlaps`).
- **Event** (`lib/data/validation/event_rules.dart`): title ≥ 2 characters;
  date must round-trip through `dateKey` (so `2026-02-30` is rejected); start
  in `[0, 1440)`; lead time in `eventLeadChoices`.
- **Import review** (`import_review_analysis.dart`) flags rows for confirmation
  instead of silently accepting them: unknown rooms, OCR uncertainty, and
  conflicts with saved classes.

## Admin accountability

Every successful `/admin/*` mutation writes one append-only row to
`admin_audit_log` (`actor_id`, `action`, `target`, `created_at`). The generic
`app_log()` in `php-backend/src/common.php` is diagnostics, not an
accountability record. The audit table is part of both the fresh schema
(`docs/mysql_schema.sql`) and the normalization migration
(`php-backend/migrations/2026-11-18-normalize.sql`), so migrated installs match
fresh ones.

## Migration and recovery

Schema migrations are forward-only and tested
(`test/app_database_v13_test.dart`, `test/class_status_migration_test.dart`,
`php-backend/tests/migration_test.php`). There is no schema downgrade. The
recovery path for a bad upgrade is a validated JSON backup restore, not a
rollback of the schema version.

## Consent and scope decisions

- Crash reporting is compiled in only when a Sentry DSN is supplied at build
  time; without it the SDK never initializes. There is no in-app toggle.
- App-level lock and SQLCipher encryption are out of scope: the app relies on
  Android's file-based encryption and the OS screen lock.
- ICS/CSV export is out of scope; JSON export/import is the portability path.
