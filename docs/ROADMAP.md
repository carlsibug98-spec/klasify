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
| 0 | SQLite → MySQL | ✅ Done (Phase 1 + auth complete) | Offline SQLite stays the local store; opt-in sync mirrors to MySQL via the Node/Express API (Docker). Sign-up/login/restore-session verified on the TECNO LJ6 on 2026-11-08. Auth is now complete: profile edit (`PATCH /auth/me`), change-password, forgot/reset flow (never reveals account existence), account deletion (API + Personal details screen), and Google Sign-In (`POST /auth/google`, JWKS verify with `aud` check, merge-by-email with `google_sub` backfill, per-instance rate limit) — verified on device 2026-11-08 including the merge path and password-login/forgot-password still working after merge. |
| 1 | School event reminders | 🔶 Partial | Per-event reminders exist with their own `eventsEnabled` gate (frame-7 reminders screen). Events carry `category = school`, but there is **no school-aware rule** yet (e.g. no content-specific rule) — the generic event gate covers it. |
| 2 | Office availability (guidance / clinic / registrar) | 🔜 Planned | No `office_status` data yet in either store. |
| 3 | Admin role | 🔜 Planned | No `users.role` column yet. |
| 4 | Admin app view | 🔜 Planned | Not built. |
| 5 | Live room occupancy | 🔜 Later phase | Not built. |
| 6 | Navigator (rooms / offices / emergency exits / campus) | 🔮 Heaviest item | Not built; needs campus data from the user. |
| 7 | Mini map (optional) | 🔮 Later phase | Not built. |

## Known gaps (re-checked 2026-11-08)

- **Sync trigger**: improved — `SyncService.syncNow()` runs after an in-session
  sign-in/sign-up and sessions restore on cold start. Still no manual "Sync now"
  row, no background timer, and no auto-retry after a failed sync.
- **Manual backup**: the exported file still carries **classes only**; events
  are not included and must be re-created by hand (codec `encode(List<ClassItem>)`).
- **Release API URL**: release builds default to `http://localhost:3000/v1`
  unless built with `--dart-define=KLASIFY_API_URL=https://…`. Cleartext HTTP
  is enabled only in debug/profile manifests; release builds are HTTPS-only by
  design, so a real deployment needs an HTTPS endpoint.

Closed since 2026-11-08: ACCOUNT-row dead end (Profile hero + Personal
details + Password & security screens exist), delete-account has a screen
(Personal details → Delete account).

## Sequencing decision (answered 2026-11-07, Phase 1 closed 2026-11-08)

**"Finish sync + device test first, decide after."** — Phase 1 is complete and
verified on the TECNO LJ6 (push, pull, sign-up, class + school event, cursors).
Next: pick the next feature chunk from the backlog above; the open decisions
below are answered as each phase begins.

## Open decisions (ask the user before building)

1. ~~Priority order after the sync phase ships~~ → **answered above**: device verification first, then decide.
2. Admin provisioning: who creates the first admin (seeded account by you vs. invite codes vs. any signup can claim admin — the last one is unsafe)?
3. Notifications for "room occupied": in-app banner only, or push notification even when the app is closed (needs FCM/server-side push infrastructure)?
4. Navigation depth: searchable directory first vs. true turn-by-turn indoor navigation from day one? Who supplies floor plans / campus layout data?
5. Which offices beyond guidance / clinic / registrar? (any others per building?)
6. Terminology check (asked): "admin" is the right term for the role; suggest labeling the section "Admin" with the person managing statuses seeing an "Admin" area in Settings.
