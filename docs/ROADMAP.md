# Klasify Roadmap — requested feature backlog (DO NOT DROP)

> Logged 2026-11-07 at the user's explicit request: "do not forget about this, place it where you can't forget about this."
> Every progress update in this project must reference this file's status table going forward.

## The verbatim feature request

- Add school event reminders
- Availability status for guidance, clinic, and registrar (open / closed / break)
- Navigator for rooms, clinic, guidance, registrar, emergency exits for buildings, and navigation for the school
- Add mini map as optional
- Live status of the room — if it's occupied (because of an event or mock defense), other classes for other programs will be notified
- Putting SQLite into MySQL
- Admin who can change the availability status of the guidance, registrar, clinic, and the status of the rooms
- What will the app look like when the admin uses it

## Status (updated 2026-11-10)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 0 | SQLite → MySQL | Done (Phase 1 + auth complete) | Offline SQLite stays the local store; opt-in sync mirrors to MySQL via the PHP/XAMPP API. Sign-up/login/restore-session verified on the TECNO LJ6 on 2026-11-08. Auth is now complete: profile edit (PATCH /auth/me), change-password, forgot/reset flow (never reveals account existence), account deletion (API + Personal details screen), and Google Sign-In (POST /auth/google, JWKS verify with aud check, merge-by-email with google_sub backfill, per-instance rate limit) — verified on device 2026-11-08 including the merge path and password-login/forgot-password still working after merge. Google sign-in now refuses unknown Gmails (404 ACCOUNT_NOT_FOUND) instead of provisioning; Create account captures the name and department (IT / AIS / BA / EDUC) and requires them for both password and Google sign-up. |
| 1 | School event reminders | Done | Events carry category = school + per-event reminders (lead_minutes). Reminder service applies a school-aware rule: school events post a distinct "School event starting soon" notification with a "School event: ..." body, separate from personal events. The eventsEnabled master gate + per-event switch still apply. |
| 2 | Office availability (guidance / clinic / registrar) | Done (v1) | `office_statuses` is school-wide (one row per office) in MySQL and cached in SQLite (`office_statuses`, DB version 9). Admin edits land both in Settings → Admin and inline on Today (the pencil on each strip tile opens the same sheet); every pull refreshes it, and Today shows the last-known state offline with the last update time. Custom notes ("Back at 2pm") ride the same row. |
| 3 | Admin role | Done | `users.role` = `user` / `admin` / `super_admin` plus `users.department` for department-scoped admins. First admin is seeded (no public claim endpoint); super admins promote/demote and assign departments in the app. JWT refresh carries role + department so changes land without a fresh sign-in. |
| 4 | Admin app view | Done | Settings & privacy gains an ADMIN group only for admins: office availability editor (open / on break / closed + note) and, for super admins, the user list with role + department editing. Department admins post events to their own department; super admins post school-wide or to a department; students see broadcast events read-only. |
| 5 | Live room occupancy | Later phase | Derived from events scheduled in that room (event + mock defense) + admin manual override; "notify other classes" needs a decision on in-app vs push (open decision). |
| 6 | Navigator (rooms / offices / emergency exits / campus) | Data collection started | Phase A: searchable directory (room to building, floor, nearest exit). Phase B: routing over a floor-plan graph. IT Building evacuation plans received 2026-11-09 (Ground = 1st floor, 2nd, 3rd, 4th; transcribed in docs/campus/it-building.md) — remaining sheets are per-room copies, other buildings still needed. |
| 7 | Mini map (optional) | Later phase | Static campus map image with markers first; interactive overlay later. Toggleable in Settings. |

## Known gaps (re-checked 2026-11-09)

- **Sync trigger**: improved - SyncService.syncNow() runs after an in-session sign-in/sign-up and sessions restore on cold start. A manual 'Sync now' row exists in Settings & privacy (signed-in only) with a success/failure toast. A background timer now runs every 5 minutes while signed in, with exponential-backoff retry (30s -> 5min) after a failed sync.
- **Manual backup**: the exported file now carries classes AND events (codec encode/decode extended; restore replaces both atomically). Older backups without an events field still restore (empty event list).
- **Release API URL**: documented in docs/DEPLOYMENT.md - put the backend behind an HTTPS reverse proxy (Caddy/nginx/cloud LB) and build with --dart-define=KLASIFY_API_URL=https://.... Release manifests are HTTPS-only by design; debug/profile keep cleartext for local dev.

Closed since 2026-11-08: ACCOUNT row dead end (Profile hero + Personal details + Password & security screens exist), delete-account has a screen (Personal details -> Delete account), events now survive backup/restore, background sync timer + auto-retry, release deployment documented (docs/DEPLOYMENT.md).

## Sequencing decision (answered 2026-11-07, Phase 1 closed 2026-11-08)

**"Finish sync + device test first, decide after."** — Phase 1 is complete and verified on the TECNO LJ6 (push, pull, sign-up, class + school event, cursors). Auth, Google Sign-In, events-in-backup, Profile reorg, and a school-aware reminder rule have shipped since. Next: pick the next feature chunk from the backlog above; the open decisions below are answered as each phase begins.

## Open decisions (ask the user before building)

1. ~~Priority order after the sync phase ships~~ -> answered above: device verification first, then decide.
2. ~~Admin provisioning~~ -> answered 2026-11-08: seeded first admin only (SQL `UPDATE users SET role = 'super_admin' WHERE email = ...`), then in-app promotion/demotion by super admins. No invite codes and no public "claim admin" flow.
3. Notifications for "room occupied": in-app banner only, or push notification even when the app is closed (needs FCM/server-side push infrastructure)?
4. Navigation depth: searchable directory first vs. true turn-by-turn indoor navigation from day one? Who supplies floor plans / campus layout data?
5. Which offices beyond guidance / clinic / registrar? (any others per building?)
6. ~~Terminology check~~ -> answered and shipped as "Admin": Settings & privacy gains an **ADMIN** group with an "Admin panel" row for accounts with `role` = `admin` or `super_admin`.
