# Plan: information governance fixes

Spec: `docs/superpowers/specs/2026-11-28-information-governance.md`

## Step 1 — Backup retention (TDD)

1. Add failing tests to `test/auto_backup_test.dart`: a backup older than 120
   days is pruned, a recent one survives, and manual exports are never touched.
2. Add a prune step to `lib/services/auto_backup_service.dart`, called once at
   startup. Keep it non-fatal and scope-safe.
3. Re-run `test/auto_backup_test.dart` and `test/auto_backup_scope_test.dart`.

## Step 2 — Conflict notice (TDD)

1. Define the conflict signal in `lib/features/sync/domain/` and have
   `lib/features/sync/application/pull_sync.dart` populate it when an incoming
   row replaces a strictly older local edit.
2. Expose it through `SyncService` and add a one-time dismissible notice in
   `lib/screens/profile/settings_privacy_screen.dart` (or the Profile hub if
   that reads better).
3. Add tests for the detection rule and the notice. Keep LWW behaviour unchanged.

## Step 3 — Admin audit trail (TDD)

1. Add the audit table to the PHP schema and a helper in `php-backend/src/`.
2. Write one row per successful mutation in `php-backend/src/admin.php`, inside
   the existing transaction.
3. Extend `php-backend/tests/` with an audit assertion and run
   `php-backend/tests/run.php`.

## Step 4 — Documentation

1. Write the provenance, validation-contract and migration-recovery sections
   described in the spec, pointing at the exact code files that implement them.
2. Update `README.md` only if a documented behaviour changes.

## Step 5 — Verification

- `flutter analyze --no-fatal-infos`
- Affected Dart test files plus the full non-benchmark suite in batches.
- `php-backend/tests/run.php`
- Commit explicit paths only; never stage `.rnd`, `.taste-skill/` or mockups.
