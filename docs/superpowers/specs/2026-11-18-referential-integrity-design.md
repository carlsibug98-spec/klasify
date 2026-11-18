# Referential integrity for class marks (P2)

Date: 2026-11-18
Status: accepted

## Problem

`class_status.class_id` is a plain integer. SQLite never enforced that it points
at a real `classes.id`, and the app never turned foreign keys on. Every write
path happens to keep them together today, but the schema permits a mark whose
class is gone. The purge path (`SyncRepository.purgeDeleted`) hard-deletes
classes and marks independently, so one future ordering mistake produces rows
the UI cannot show, the sync push cannot resolve, and the server will reject.

Schema v10 fixed the other half of the same problem (one local row per server
row). This spec closes the local-referential half.

## Decision

1. **Turn enforcement on**: `onConfigure` runs `PRAGMA foreign_keys = ON` for
   every connection. sqflite opens one connection per database, so this covers
   the app and the test factory.
2. **Declare the relation**: `class_status.class_id REFERENCES classes(id)
   ON DELETE CASCADE`. Cascade matches the MySQL schema, where
   `class_statuses.class_id` already cascades on class delete.
3. **Soft delete stays authoritative**. The FK only fires on a hard delete, so
   the normal user flow is unchanged: deleting a class tombstones the class and
   its marks, sync pushes the tombstones, and `purgeDeleted` removes them only
   after the server acknowledges. Cascade then simply removes the marks that
   belong to the purged class.
4. **Schema v11 migrates existing files**. SQLite cannot add a foreign key with
   `ALTER TABLE`, so the table is rebuilt:
   - delete marks whose `class_id` has no `classes` row (they can never be
     shown or pushed; the server's cascade already removed their counterparts);
   - create the new table with the FK, copy every column including `id`,
     `server_id`, `deleted`, and `updated_at`;
   - drop the old table, rename, and recreate both indexes
     (`idx_class_status_class`, `idx_class_status_server_id`) because dropping a
     table drops its indexes.
5. **Fresh installs** get the FK in the original `CREATE TABLE`, and the v4→v5
   rebuild keeps it too, so a new file never passes through an unenforced state.

## Why cascade, not restrict

`RESTRICT` would make a legitimate purge fail and force every caller to clean
marks first — the same manual ordering that caused this bug. There is no case
where a mark outliving its class is useful: the UI keys marks by class id, the
push resolves a server class per mark, and the server cascades too. Cascade
makes the invalid state unrepresentable.

## Non-goals

- P3 (overlapping ranges per class) is a semantic invariant, not a referential
  one; it needs its own design.
- `events` and `office_statuses` have no local parent, so they get no FK.
- No change to sync payloads, backup format, or the UI.

## Verification

- Fresh database: `PRAGMA foreign_keys` is 1; inserting a mark for a missing
  class throws.
- Purge path: deleting a class, acknowledging the tombstones, and purging
  removes the class and its marks.
- v10→v11: live marks and tombstones survive with every field intact, orphaned
  marks are removed, both indexes exist, and the FK is enforced afterwards.
- Full suite and `flutter analyze --no-fatal-infos` stay green.
