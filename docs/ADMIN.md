# Admin roles and office availability

Who can do what, and how the first admin is created. The API enforces every
rule below; the app only hides surfaces that would be rejected anyway.

## Roles

| `users.role` | In-app label | Scope |
|---|---|---|
| `user` (default) | Student | Own schedule and events only |
| `admin` | Department admin | Events broadcast to `users.department` only |
| `super_admin` | Super admin | Whole school: roles, departments, school-wide events |

`users.department` is free text (`IT`, `AIS`, `BA`, `EDUC`, ...). Students
choose theirs at sign-up; admins get theirs from a super admin. It matters
twice:

- A department admin's broadcasts reach only users with the same
  `department` (and admins with no department cannot broadcast; in the admin
  user list, they see only themselves).
- Every user's pull includes broadcast events scoped to their own
  department, so students who pick the wrong department miss those events.

## Provisioning

There is no public "claim admin" endpoint. Promote an existing account with
SQL against the live database (sign the account up first):

```sql
-- First admin: school-wide
UPDATE users SET role = 'super_admin' WHERE email = 'you@school.edu';

-- Department admin
UPDATE users SET role = 'admin', department = 'IT' WHERE email = 'dept@school.edu';
```

After promotion the user signs out/in, or waits for the next `/auth/refresh`
(the app refreshes restored legacy sessions in the background once), so the
new role reaches the client.

From then on super admins manage everyone else in-app:
**Settings & privacy → Admin → User roles** (role + department editor).
The API refuses self-demotion, so a school always keeps at least the acting
super admin.

## Office availability

`office_statuses` is school-wide: one row per office (`guidance`, `clinic`,
`registrar`) with `department IS NULL`.

- Admins edit in **two places**: inline on **Today** (the pencil on each
  office tile opens the same editor sheet) or **Settings & privacy → Admin →
  Office availability** — open / on break / closed + an optional note like
  "Back at 2pm". Both write through the same API, so students get the change
  at the next sync.
- `GET /admin/office-statuses` seeds any missing office as `open` on first
  read, so a fresh install always shows all three.
- The app caches the rows locally (`office_statuses` SQLite table, DB v9) and
  refreshes them on every sync pull, so Today shows the last-known value and
  its update time while offline.

## Events: personal vs broadcast

- Regular users create personal events (`user_id` = owner).
- Admin-created events default to personal ("Just me") with a "Share with"
  row in the event sheet:
  - department admin → **My department** (`department` = caller's dept)
  - super admin → **Whole school** (`department` = NULL) or a department
- Broadcast rows are stored with `events.user_id = NULL` and
  `events.broadcast = 1`; scope is taken from the caller's server-side role
  and department, never from the client payload.
- Students see broadcast events read-only (no edit sheet, no swipe delete).
- Admins may only edit broadcast rows inside their scope; the API returns
  the unchanged row instead of letting a foreign edit through.

## API summary

| Method | Path | Who |
|---|---|---|
| `GET` | `/admin/users` | admin/super admin (scoped list) |
| `PATCH` | `/admin/users/:id/role` | super admin |
| `PATCH` | `/admin/users/:id/department` | super admin |
| `GET` | `/admin/office-statuses` | admin/super admin |
| `PATCH` | `/admin/office-statuses/:office` | admin/super admin |

## Verified behavior (HTTP, 2026-11-09)

- School-wide broadcast visible to every account; `IT` broadcast visible only
  to accounts with `department = 'IT'`.
- A student pushing a delete/rename of a broadcast row is ignored.
- Office `PATCH` bumps `updated_at`, and the next pull returns all three
  offices.
