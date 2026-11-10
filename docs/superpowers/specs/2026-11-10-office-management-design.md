# Office management (super admin) — design

Date: 2026-11-10 · Status: awaiting approval
Mockups (untracked, never committed): `mockup_office_manage.html` (Settings),
`mockup_office_strip_scroll.html` v17 (Today pager + blur).

## Why

Campus offices are hardcoded server-side: `const OFFICES = ['guidance', 'clinic', 'registrar']`
(`php-backend/src/admin.php:9`) seeds them, gates availability PATCHes, and no API can create a
fourth. Campuses differ — a school without a clinic would still show "Clinic: Open", which is a
lie. The super admin should manage the office list itself, in the app.

## Decisions (all made with the user)

1. **Who**: super admin manages offices (add / rename / retire). Department admins keep
   availability-only.
2. **Where (UI)**: "Add office" is a row at the end of OFFICE AVAILABILITY on the Admin screen;
   Rename / Retire live inside the shared availability editor sheet under a "Manage office"
   section — so they appear everywhere the sheet opens (Admin screen *and* Today's ✎ chip).
3. **Retire = soft delete, permanent in-app.** Students lose the office at their next sync; no
   restore button, no retired list (user: "gone for good"). The row stays on the server
   (`deleted = 1`), preserving its record.
4. **Rename keeps status + note.** Implemented server-side as *tombstone old row + create new
   row* so the change rides the existing sync machinery (pull already delivers `deleted: true`
   rows; clients already purge on tombstones for classes/events).
5. **Offices stay school-wide.** The `department` column stays unused for offices.
6. **Today strip**: ≤3 offices exactly as approved v12. 4+ offices become a swipe **pager**:
   one office per swipe (page-snapping physics, rubber-band ends), columns at 2/7 width so half
   the next office peeks past a **soft edge blur** (BackdropFilter + gradient mask, ~52px
   sliver). No arrow chips.

## Approaches considered

| Approach | Verdict |
|---|---|
| Move `OFFICES` to `config.php` | Rejected — not in-app management; the user chose CRUD. |
| Separate `offices` table | Rejected — schema churn and a new sync payload for no gain; `office_statuses` already has `deleted` + `department`. |
| CRUD on `office_statuses` rows with tombstones | **Chosen.** Trade-offs accepted: rename changes the row's `id` and `updated_at` (office rows have no history dependencies); no seeding anymore (fresh installs start with zero offices — the "No offices yet" empty states already exist). |

## Contract changes (deliberate update to `docs/sync_api_contract.md`)

All new routes are `super_admin` only (403 `FORBIDDEN` for dept admins). Errors follow the
existing `{ error, code }` shape.

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/admin/offices` | `{ "name": "Library" }` | 201 `{ office: {...} }`. Name: trim, 1–40 chars, unique case-insensitive among active school-wide offices. Creates row `status='open'`, `custom_message=NULL`, `department=NULL`. |
| PATCH | `/admin/offices/:office` | `{ "name": "New name" }` | Rename. 404 `OFFICE_NOT_FOUND` if unknown. Same name validation; 409 `OFFICE_EXISTS` on duplicate. Tombstones the old row (`deleted=1`, `updated_at=now`) and inserts a new row carrying status + note. |
| DELETE | `/admin/offices/:office` | — | Retire (soft delete). 404 `OFFICE_NOT_FOUND` if unknown. |

Changed semantics on existing routes:

- `GET /admin/office-statuses` — **no longer seeds**. Returns active school-wide offices
  ordered by `office_name`; an empty list is valid. Existing installs keep their rows.
- `PATCH /admin/office-statuses/:office` — validation switches from the `OFFICES` const to
  name rules; the route now **requires an existing active row** (404 `OFFICE_NOT_FOUND`
  otherwise). Create-on-PATCH is gone — offices are created only via POST.
- Pull (`GET /sync/pull`) is unchanged on the wire: `office_statuses` rows already carry
  `deleted`. Clients must now *honor* it (below).

## Server (`php-backend/src/admin.php` + route table)

- Remove `const OFFICES` and the seeding loop in `admin_list_offices()`.
- Add handlers for the three new routes + shared validation helper
  (`office_name_or_422`, uniqueness check, `office_row_or_404`).
- Availability PATCH loses its insert branch.
- Register routes where admin routes are mapped today.

## Client (Flutter)

- `AuthService`: `adminAddOffice(name)`, `adminRenameOffice(key, newName)`,
  `adminRetireOffice(key)` (existing `adminSetOfficeStatus` unchanged).
- `DatabaseHelper.upsertOfficeStatusFromServer`: if `data['deleted'] == true`, **delete** the
  local row by `office_name` instead of upserting (local table has no deleted column and
  tombstones would otherwise render forever). No schema change needed.
- New shared `office_name_sheet.dart` (add + rename): name field, inline duplicate error
  (pre-checked client-side against the loaded list; server re-checks authoritatively), spinner
  CTA, Cancel — same failure contract as the availability sheet (spinner "Saving…",
  non-dismissible mid-save, error toast + stay open on failure).
- `office_status_editor_sheet.dart`: optional `onRename` / `onRetire` callbacks render the
  "Manage office" section; absent for dept admins.
- `admin_screen.dart`: Add-office row (super only) at the end of OFFICE AVAILABILITY; wires
  the sheets + retire confirm dialog ("Students will no longer see it on Today. Its record
  stays on file."); success toasts via `showAppNotification`
  ("X added. Students see it on Today after the next sync." / rename / retire).
- `home_screen.dart`: passes manage callbacks into the editor sheet when `isSuperAdmin`
  (Today's ✎ path gains manage powers for free).
- `office_status_strip.dart`: ≤3 offices keep the current row; 4+ offices render a `PageView`
  (page physics = one per swipe) with 2/7-width columns (half-card peek) and edge blur
  (`BackdropFilter` inside `ShaderMask`, multi-stop gradient, soft by default).

## Tests

PHP (`php-backend/tests/run.php`, currently 51 cases):

- **Update existing cases that assert OFFICES seeding** — seeding is gone; fresh DB now yields
  an empty list.
- New: create → 201 + row (`open`); duplicate (case-insensitive) → 409; empty/41-char name →
  422; rename keeps status + note and tombstones old key (verify via list *and* pull
  `deleted:true`); rename to existing → 409; rename/retire unknown → 404; availability PATCH on
  retired office → 404; all three routes → 403 for dept admin.

Flutter (widget tests, red → green):

- Editor sheet: manage section visible iff callbacks provided.
- Name sheet: empty CTA disabled; duplicate shows inline error without a network call; server
  failure keeps sheet open + error toast.
- Retire dialog copy + confirm/cancel flows.
- Strip: 3 offices → current layout, no pager; 4 offices → pager + 2/7 columns + blur widgets;
  drag advances exactly one page; tap (no drag) opens the sheet.
- Golden recapture under `--update-goldens` (TZ=Asia/Manila daytime window) after the strip
  change.

## Deployment / bookkeeping

- Robocopy `php-backend/src` → `C:\xampp\htdocs\klasify-api` (exclude tests); device verify.
- Append `php-backend/PROVENANCE.md` patch-log entry describing the contract update.
- `docs/ROADMAP.md`: strike the office-CRUD backlog entry.

## Non-goals / anti-goals

- No restore UI, no retired list, no per-department offices, no reorder, no per-office icons,
  no edit history.
- Anti-goals: fabricated offline offices (client-side seeding stays dead); silent contract
  drift (the contract doc updates in the same commit as the server).
