# Klasify Sync API — Contract

Base URL: `https://api.klasify.app` (configurable; local dev against the Node API: `http://localhost:8080`).

All endpoints except `/auth/*` require `Authorization: Bearer <jwt>`.

## Authentication

### POST /auth/register
```json
// Request
{ "email": "user@example.com", "password": "min8chars",
  "display_name": "Juan", "department": "IT" }

// Response 201
{ "user": { "id": 1, "email": "user@example.com", "display_name": "Juan",
             "role": "user", "department": "IT" },
  "token": "<jwt>", "expires_at": "2026-12-06T10:00:00Z" }
```

`department` is optional on the wire but the app requires it at sign-up
(`IT`, `AIS`, `BA`, `EDUC`).

### POST /auth/login
```json
// Request
{ "email": "user@example.com", "password": "..." }

// Response 200
{ "user": { "id": 1, "email": "...", "display_name": "...",
             "role": "user", "department": null },
  "token": "<jwt>", "expires_at": "..." }
```

### POST /auth/google
Verifies a Google ID token (audience = the configured web client id) and
returns a session. `mode` decides what happens when the verified Google
identity has no Klasify account:

- `"signin"` (default) — **never** creates an account. Responds 404
  `ACCOUNT_NOT_FOUND` so the sign-in screen can point at Create account.
- `"signup"` — creates the account from the create-account screen. Uses the
  user-typed `display_name` and `department` from the request, not the Google
  profile name.

```json
// Request (create account)
{ "id_token": "<google-id-token>", "mode": "signup",
  "display_name": "Juan", "department": "IT" }

// Response 200 (existing account or newly created)
{ "user": { "id": 1, "email": "juan@gmail.com", "display_name": "Juan",
             "role": "user", "department": "IT" },
  "token": "<jwt>", "expires_at": "..." }
```

| Code | HTTP | Meaning |
|---|---|---|
| INVALID_GOOGLE_TOKEN | 401 | Bad signature, wrong audience, or unverified email |
| ACCOUNT_NOT_FOUND | 404 | Google identity has no account and mode was `signin` |
| RATE_LIMITED | 429 | More than 30 attempts per minute (per instance) |

If a password account already uses the Google email, the token is accepted,
`google_sub` is backfilled, and the existing account (with its role) is
returned — the merge path.

### POST /auth/refresh
```
Authorization: Bearer <expired_jwt>
// Response 200
{ "token": "<new_jwt>", "expires_at": "...",
  "user": { "id": 1, "email": "...", "display_name": "...",
             "role": "admin", "department": "IT" } }
```

`role` is `user` / `admin` / `super_admin`; `department` is non-null only for
department-scoped admins. Refresh re-reads both from the DB, so promotions
land without a new sign-in.

### PATCH /auth/me
Partial profile edit. Send `display_name` and/or `email`.

```json
// Request (Authorization required)
{ "display_name": "Clarisse", "email": "clarisse.sync@test.com" }

// Response 200
{ "user": { "id": 1, "email": "clarisse.sync@test.com", "display_name": "Clarisse",
             "role": "user", "department": null } }
```

| Code | HTTP | Meaning |
|---|---|---|
| EMAIL_EXISTS | 409 | Another account already uses the email |
| VALIDATION_ERROR | 422 | Empty name, bad email, or empty body |

### POST /auth/change-password
```json
// Request (Authorization required)
{ "current_password": "...", "new_password": "min8chars" }

// Response 204
```

Wrong current password: 401 `INVALID_CREDENTIALS`. Short new password: 422 `VALIDATION_ERROR`.

### POST /auth/forgot-password
Always responds `200 { "ok": true }` — never reveals whether the email is registered.
Creates a 6-digit code that lives 15 minutes (one active code per account).

```json
// Request
{ "email": "user@example.com" }

// Response 200
{ "ok": true }
```

Max 5 requests per email per hour, then 429 `RATE_LIMITED`. Email delivery requires SMTP in
production; while no mailer is configured the code is written to the server log
(`docker logs klasify-api`) so the flow stays testable in development.

### POST /auth/reset-password
```json
// Request
{ "email": "user@example.com", "code": "123456", "new_password": "min8chars" }

// Response 204
```

The code is single-use. Invalid code, unknown email, expired code, or short password:
422 `VALIDATION_ERROR` ("The reset code is invalid or expired" / validation message).
Sign in normally with the new password afterwards.

### DELETE /auth/account
Deletes the user and all their data (cascade). Returns 204.

## Sync

### POST /sync/push
Pushes local changes to the server. The client sends only rows changed since the last push.

```json
// Request
{
  "device_id": "abc123",
  "last_push_at": "2026-11-06T09:00:00.000Z",   // null on first push
  "classes": [
    { "local_id": 5, "subject": "Math", "room": "302", "professor": "Prof. X",
      "day": 1, "start_minutes": 600, "end_minutes": 690,
      "updated_at": "2026-11-06T09:30:00.000Z", "deleted": false }
  ],
  "events": [
    { "local_id": 3, "title": "Exam", "venue": "Gym", "event_date": "2026-11-10",
      "start_minutes": 540, "category": "school", "department": null,
      "broadcast": false, "reminder_enabled": true,
      "lead_minutes": 30, "updated_at": "2026-11-06T09:30:00.000Z", "deleted": false }
  ],
  "class_statuses": [
    { "local_id": 1, "local_class_id": 5, "status": "finished",
      "start_date": "2026-11-06", "end_date": null,
      "updated_at": "2026-11-06T09:30:00.000Z", "deleted": false }
  ]
}

// Response 200
{
  "server_time": "2026-11-06T09:31:00.000Z",
  "classes": [
    { "local_id": 5, "server_id": 42, "updated_at": "2026-11-06T09:31:00.000Z" }
  ],
  "events": [
    { "local_id": 3, "server_id": 7, "updated_at": "2026-11-06T09:31:00.000Z" }
  ],
  "class_statuses": [
    { "local_id": 1, "server_id": 12, "updated_at": "2026-11-06T09:31:00.000Z" }
  ]
}
```

The client stores `server_id` in a local `sync_map` table (local_id → server_id) for future updates.

### GET /sync/pull?since=<iso_timestamp>
Pulls all rows changed on the server since `since`.

```json
// Response 200
{
  "server_time": "2026-11-06T09:31:00.000Z",
  "classes": [ { "id": 42, "subject": "Math", ..., "updated_at": "...", "deleted": false } ],
  "events": [ { "id": 7, "title": "Exam", ..., "department": null,
                "broadcast": false, "updated_at": "...", "deleted": false } ],
  "class_statuses": [ { "id": 12, "class_id": 42, "status": "finished", ..., "updated_at": "...", "deleted": false } ],
  "office_statuses": [ { "office_name": "guidance", "status": "break",
                         "custom_message": "Back at 2pm", "updated_at": "..." } ]
}
```

The client applies these to local SQLite (upsert by server_id mapping, or insert if new).
Pulled events include the caller's own rows plus broadcast rows scoped to the
caller (`department IS NULL` or `department = <caller.department>`); a broadcast
row has `user_id = NULL` on the server and never matches a viewer's local id.

### Admin endpoints

All require a signed-in `admin` or `super_admin`; role/department changes are
`super_admin` only.

| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/admin/users` | — | super admins see everyone; dept admins see their department (limit 200) |
| PATCH | `/admin/users/:id/role` | `{ "role": "admin" }` | self-demotion rejected with 422 |
| PATCH | `/admin/users/:id/department` | `{ "department": "IT" }` or `null` | |
| GET | `/admin/office-statuses` | — | seeds any missing office as `open` |
| PATCH | `/admin/office-statuses/:office` | `{ "status": "break", "custom_message": "Back at 2pm" }` | school-wide |

Broadcast scope is decided server-side from the caller's stored role and
department, never from the push payload: a dept admin always posts to their own
department (and cannot broadcast without one); a super admin may post
school-wide (`department: null`) or to a department.

## Conflict resolution
- **Last-write-wins** per row, based on `updated_at` (client timestamp vs server timestamp).
- The server always wins on conflicts (server timestamp is authoritative).
- Soft-deleted rows are included in pull responses so clients can delete locally.

## Sync flow (client side)
1. On sign-in: push then pull, so every device starts consistent
2. While signed in: a 5-minute background timer pulls/pushes; failures retry
   with backoff (30s → 5min) and surface in Settings & privacy
3. Manual "Sync now" row in Settings & privacy (signed-in only)
4. On app resume: pull since last_pull_at

## Error responses
All errors return JSON: `{ "error": "message", "code": "ERROR_CODE" }`

| Code | HTTP | Meaning |
|---|---|---|
| INVALID_CREDENTIALS | 401 | Wrong email/password |
| TOKEN_EXPIRED | 401 | JWT expired, call /auth/refresh |
| EMAIL_EXISTS | 409 | Registration with existing email |
| VALIDATION_ERROR | 422 | Missing/invalid fields |
| RATE_LIMITED | 429 | Too many requests |
| SERVER_ERROR | 500 | Internal error |
