# Referential integrity for class marks — implementation plan

Spec: `docs/superpowers/specs/2026-11-18-referential-integrity-design.md`

## Steps

1. **RED** — add `test/foreign_key_integrity_test.dart` with three real-SQLite
   tests: fresh enforcement, purge cascade, v10→v11 migration. Run it and
   confirm it fails for the intended reasons (pragma 0, no FK, version 10).
2. **GREEN** — in `lib/data/app_database.dart`:
   - bump the schema to 11;
   - add `onConfigure` with `PRAGMA foreign_keys = ON`;
   - add the FK to `_classStatusSchema`;
   - add `_migrateClassStatusForeignKey`, called for `oldVersion < 11`;
   - recreate the class-status indexes after the rebuild.
3. Run the new file, then the database/status/sync test group.
4. Run the full suite and the analyzer.
5. Update `docs/APP_WALKTHROUGH.md` (schema v11, FK/delete policy, test counts)
   and the roadmap note.
6. Commit with explicit paths; do not stage untracked mockups.

## Verification commands

```powershell
flutter test test\foreign_key_integrity_test.dart --reporter expanded
flutter test test\database_crud_test.dart test\database_validation_test.dart `
  test\class_status_db_test.dart test\class_status_migration_test.dart `
  test\sync_mapping_integrity_test.dart test\events_db_test.dart --reporter compact
flutter test --reporter compact
flutter analyze --no-fatal-infos
```
