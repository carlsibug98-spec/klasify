# Sync and status integrity fixes

Date: 2026-11-28
Status: implemented (audit findings 1–8)

## Context

A whole-app audit confirmed eight defects in the sync/status and settings
path. Each one leaves the app, the server, or the user's understanding of the
current state out of step.

### 1. Range edits never delete the server row they replace (High)

`StatusRepository.setStatus` and `clearStatus` delete every live row for the
class and re-insert the resulting ranges. `replaceStatusRange` deliberately
gives split segments fresh ids (to avoid primary-key collisions), so a row that
already has a `server_id` disappears locally without a tombstone. The server
keeps the original wide range.

Consequences:

- Another phone whose pull cursor predates the original row still receives the
  un-narrowed range.
- A fresh pull (new scope, restored identity, reinstall) returns the original
  row next to the split rows. `activeStatusEntry` takes the first match by
  `start_date, id`, so a stale row can override the user's newer edit.
- `restore` has the same hole: it deletes live rows added after the snapshot
  without tombstoning the ones the server already knows.

### 2. Undo revives tombstones the delete did not create (Low)

`ClassRepository.restoreDeleted` revives *every* tombstoned status for the
class. `deleteClassWithUndo` only re-applies the pre-delete marks when the
snapshot is non-empty, so a class with no live marks but an unpushed cleared
mark comes back with the cleared mark live again. The delete stamps the class
and its live statuses with one timestamp; the fix revives only rows carrying
that stamp.

### 3. Auto backup can store one account's schedule under another's name (Medium)

`AutoBackupService.backupNow` captures `LocalScopeService.current` before the
reads. A scope switch between the capture and the reads writes the new
account's classes into the old account's backup file. Account-scoped storage
exists to prevent exactly this.

### 4. Hardcoded status pills (Low)

`Settings & privacy → Sync & devices` always reads `On`, and
`Password & security → This phone` always reads `Active`, regardless of the
sync controller's last error or the session state.

### 5. Reminder permission revocation is invisible (Medium)

`ReminderService.isEnabled` reads the stored preference only. Revoking
notifications in Android settings leaves the Reminders screen claiming the
feature is on while `sync()` schedules alarms the system will never show.

### 6. No way back to system theme (Low)

The Dark mode switch maps the tri-state preference onto two states. Once a
user picks light or dark, nothing in the UI restores `system`, so an explicit
choice becomes permanent without a reinstall.

### 7. Per-event "Remind me" gives no feedback when the master gate is off (Low)

`EventSheet` saves `remindMe` even when `ReminderService.eventsEnabled` is
false. The switch looks effective but no alarm will fire.

### 8. Dead "Sync & devices" row (Low)

The row showed a status pill but had no `onTap`, so it looked like a settings
destination that went nowhere.

## Requirements

- Behaviour-preserving for every user-visible flow except the corrected states.
- Real implementations only; no placeholder UI or dead toggles.
- New tests reproduce each defect before the fix and pass after.
- `flutter analyze` stays clean; the non-benchmark suite stays green.

## Design

### Status tombstones

A private helper builds tombstone maps for live rows that the new state drops
**and** that have a `server_id`. Rows that never reached the server are simply
deleted: pushing a tombstone with no server id would insert a deleted row on
the server.

The tombstone keeps the row's `id` and `server_id`, so the existing push path
(`buildStatusPushRow` → `server_id`) updates the server row to `deleted = 1`.
`purgeDeleted` removes it locally after the push is acknowledged. Undo still
works: `restore` re-inserts the snapshot row with the same id and skips the
duplicate tombstone.

### Undo scope

`restoreDeleted` reads the class row's `updated_at` before restoring it (that
is the stamp `delete` wrote) and revives only `deleted = 1` statuses carrying
that exact stamp. Older tombstones stay deleted and keep propagating.

### Backup scope

`backupNow` re-reads `LocalScopeService.current` after the reads and aborts
without writing when it changed. The new scope's own debounce/launch backup
writes the correct file. No file is written from mixed data.

### Pills

The Sync row listens to `SyncService` and shows `On` only after a successful
sync in the current session, `Syncing` while a sync runs, and `Off` after a
failure. The security hub row shows `Active` only while the session is live.

### Reminder permission

The Reminders screen asks the platform whether notifications are enabled when
it loads and when the app resumes. When the stored preference is on but the
system permission is gone, it shows a text warning naming the Android settings
path. No settings-opener dependency exists in the app, so the warning tells the
user where to go instead of offering a button that cannot work.

### Theme, event gate and settings row

A quiet footer link appears under the Dark mode switch only while an explicit
theme is in force, and restores `system` mode. The event sheet reads the
effective event gate and shows an inline warning next to "Remind me" while the
master gate would silence the alarm. The "Sync & devices" row now opens
Password & security, where the signed-in phones live, with a chevron beside its
status pill so the destination is visible.

## Out of scope

- Server-side unique constraints for status ranges.
- Auth smoke tests against the live backend (need real credentials).
- On-device Week cold-start check while the test phone is in another app.
