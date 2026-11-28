# Information governance specification

Date: 2026-11-28
Status: approved for implementation (product decisions recorded below)

## Context

A recheck of the app against information-management and mobile-app lenses found
that the code architecture is in good shape, but several information lifecycle
rules are either undocumented or not visible to the user. This spec fixes the
policy layer without changing the architecture. It does not add a new CA slice
or reorganise folders.

The following were checked directly and are **not** gaps: session tokens use
`FlutterSecureStorage`; the last-write-wins conflict policy is documented in
`docs/sync_api_contract.md`; account scoping is enforced in the data layer;
widget, golden and architecture tests exist; CI is green; notification
permission is requested at runtime in `lib/services/reminder_service.dart`.

## Decisions made with the product owner

- **Retention:** auto-backups are kept for one academic semester. Implemented
  as a rolling **120-day** cap (my call, so it does not depend on a school
  calendar), pruned on startup. Manual exports are never deleted automatically.
- **ICS export:** out of scope. JSON export/import remains the portability path.
- **App lock and SQLCipher:** out of scope. The app relies on Android's
  file-based encryption and the OS screen lock. Revisit only if the data
  classification changes (for example, shared-device use with identifiable
  student records).

## Scope

In scope: retention enforcement, user-visible conflict notice, admin action
audit trail, provenance standard, published validation contract, and a
documented recovery path for schema migrations.

Out of scope: ICS/CSV export, app-level encryption, whole-app Clean Architecture
migration, new device/backend verification (both blocked on external access),
size/startup budgets, tablet/landscape layouts, and localization.

## Requirements

- Behaviour-preserving except for the conflict notice and backup pruning.
- No new dependencies unless a later step proves one is necessary.
- `flutter analyze --no-fatal-infos` stays clean; affected test files stay green.
- PHP harness (`php-backend/tests/run.php`) stays green if the backend changes.
- Spec and plan live under `docs/superpowers/` before implementation.

## Design

### 1. Backup retention

`AutoBackupService` already owns auto-backup writes and has a scope-reader seam
for tests. Add a prune step that runs once per app start: list auto-backup
files, parse their timestamps, delete files older than 120 days, and never
touch manual exports. A failed prune is non-fatal and logged via `debugPrint`.

### 2. Conflict notice

Pull already follows the documented LWW rule: the server wins ties, and only a
strictly newer local edit survives. The gap is visibility, not policy. During
pull, when an incoming row replaces a local edit whose `updated_at` is not
newer, record a conflict summary in sync state. The settings screen shows a
one-time, dismissible notice naming the affected record type and count. No
manual resolution UI is introduced; the stored result stays LWW.

### 3. Admin audit trail

`php-backend/src/admin.php` owns office, role and department mutations. Add an
append-only audit table (`actor_id`, `action`, `target`, `created_at`) and write
one row per successful admin mutation inside the same transaction as the
change. Generic `app_log()` calls stay as they are; they are diagnostics, not
an accountability record. Expose the log only to super admins.

### 4. Provenance standard

Document the fields the app already carries: `updated_at` and `server_id` on
synced rows, and the import review's OCR/room/conflict flags. Define the source
values as `manual`, `ocr`, `sync`, or `restored`. No schema change is proposed
at this stage; the standard is documentation plus a note on where each value
can be recovered.

### 5. Validation contract

Publish the rules implemented by `lib/data/validation/class_rules.dart`,
`event_rules.dart` and `lib/features/schedule_import/utils/import_review_analysis.dart`
as a short data-quality contract: what is rejected, what is flagged for review,
and what is silently accepted.

### 6. Migration recovery

The sync Clean Architecture design already documents a code-level rollback.
Add a separate note for schema migrations: they are forward-only, tested by
`app_database_v13_test.dart` and `class_status_migration_test.dart`, and the
recovery path for a bad upgrade is a validated JSON backup restore, not a
schema downgrade.

## Acceptance

- Auto-backups older than 120 days are removed on startup; recent ones and
  manual exports survive.
- A pull that discards a local edit surfaces a dismissible notice.
- Every successful admin mutation writes one audit row.
- Provenance, validation and migration-recovery documents exist and match code.
- Full non-benchmark suite and PHP harness remain green.
