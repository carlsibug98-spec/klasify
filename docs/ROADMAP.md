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

## Status (updated 2026-11-08, post-build)

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 0 | SQLite → MySQL | Done (Phase 1 + auth complete) | Offline SQLite stays the local store; opt-in sync mirrors to MySQL via the Node/Express API (Docker). Sign-up/login/restore-session verified on the TECNO LJ6 on 2026-11-08. Auth is now complete: profile edit (PATCH /auth/me), change-password, forgot/reset flow (never reveals account existence), account deletion (API + Personal details screen), and Google Sign-In (POST /auth/google, JWKS verify with aud check, merge-by-email with google_sub backfill, per-instance rate limit) — verified on device 2026-11-08 including the merge path and password-login/forgot-password still working after merge. |
| 1 | School event reminders | Done | Events carry category = school + per-event reminders (lead_minutes). Reminder service applies a school-aware rule: school events post a distinct "School event starting soon" notification with a "School event: ..." body, separate from personal events. The eventsEnabled master gate + per-event switch still apply. |
| 2 | Office availability (guidance / clinic / registrar) | Planned | New office_status data (open / closed / break / custom) in both stores; admin-editable; offline shows last-known value + freshness. |
| 3 | Admin role | Planned | users.role = 'user' | 'admin'; admin provisioning TBD (see open decisions). |
| 4 | Admin app view | Planned | Role-gated section: edit office statuses, override room occupancy. Same app, surfaced only for admins. |
| 5 | Live room occupancy | Later phase | Derived from events scheduled in that room (event + mock defense) + admin manual override; "notify other classes" needs a decision on in-app vs push (open decision). |
| 6 | Navigator (rooms / offices / emergency exits / campus) | Heaviest item | Phase A: searchable directory (room to building, floor, nearest exit). Phase B: routing over a floor-plan graph. Needs campus data from the user. |
| 7 | Mini map (optional) | Later phase | Static campus map image with markers first; interactive overlay later. Toggleable in Settings. |

## Known gaps (re-checked 2026-11-08)

- **Sync trigger**: improved - SyncService.syncNow() runs after an in-session sign-in/sign-up and sessions restore on cold start. A manual "Sync now" row now exists in Settings & privacy (signed-in only) with a success/failure toast. Still no background timer and no auto-retry after a failed sync.
- **Manual backup**: the exported file now carries classes AND events (codec encode/decode extended; restore replaces both atomically). Older backups without an events field still restore (empty event list).
- **Release API URL**: release builds default to http://localhost:3000/v1 unless built with --dart-define=KLASIFY_API_URL=https://... . Cleartext HTTP is enabled only in debug/profile manifests; release builds are HTTPS-only by design, so a real deployment needs an HTTPS endpoint.

Closed since 2026-11-08: ACCOUNT row dead end (Profile hero + Personal details + Password & security screens exist), delete-account has a screen (Personal details -> Delete account), events now survive backup/restore.

## Sequencing decision (answered 2026-11-07, Phase 1 closed 2026-11-08)

**"Finish sync + device test first, decide after."** — Phase 1 is complete and verified on the TECNO LJ6 (push, pull, sign-up, class + school event, cursors). Auth, Google Sign-In, events-in-backup, Profile reorg, and a school-aware reminder rule have shipped since. Next: pick the next feature chunk from the backlog above; the open decisions below are answered as each phase begins.

## Open decisions (ask the user before building)

1. ~~Priority order after the sync phase ships~~ -> answered above: device verification first, then decide.
2. Admin provisioning: who creates the first admin (seeded account by you vs. invite codes vs. any signup can claim admin — the last one is unsafe)?
3. Notifications for "room occupied": in-app banner only, or push notification even when the app is closed (needs FCM/server-side push infrastructure)?
4. Navigation depth: searchable directory first vs. true turn-by-turn indoor navigation from day one? Who supplies floor plans / campus layout data?
5. Which offices beyond guidance / clinic / registrar? (any others per building?)
6. Terminology check (asked): "admin" is the right term for the role; suggest labeling the section "Admin" with the person managing statuses seeing an "Admin" area in Settings.