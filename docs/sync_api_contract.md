# Klasify Sync API — Contract

Base URL: `https://api.klasify.app/v1` (configurable; local dev: `http://localhost:3000/v1`)

All endpoints except `/auth/*` require `Authorization: Bearer <jwt>`.

## Authentication

### POST /auth/register
```json
// Request
{ "email": "user@example.com", "password": "min8chars", "display_name": "Juan" }

// Response 201
{ "user": { "id": 1, "email": "user@example.com", "display_name": "Juan" },
  "token": "<jwt>", "expires_at": "2026-12-06T10:00:00Z" }
```

### POST /auth/login
```json
// Request
{ "email": "user@example.com", "password": "..." }

// Response 200
{ "user": { "id": 1, "email": "...", "display_name": "..." },
  "token": "<jwt>", "expires_at": "..." }
```

### POST /auth/refresh
```
Authorization: Bearer <expired_jwt>
// Response 200
{ "token": "<new_jwt>", "expires_at": "..." }
```

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
      "start_minutes": 540, "category": "school", "reminder_enabled": true,
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
  "events": [ { "id": 7, "title": "Exam", ..., "updated_at": "...", "deleted": false } ],
  "class_statuses": [ { "id": 12, "class_id": 42, "status": "finished", ..., "updated_at": "...", "deleted": false } ]
}
```

The client applies these to local SQLite (upsert by server_id mapping, or insert if new).

## Conflict resolution
- **Last-write-wins** per row, based on `updated_at` (client timestamp vs server timestamp).
- The server always wins on conflicts (server timestamp is authoritative).
- Soft-deleted rows are included in pull responses so clients can delete locally.

## Sync flow (client side)
1. On app start (if sync enabled): pull since last_pull_at
2. After any local write: schedule a debounced push (5s delay)
3. On "Sync now" button: push then pull immediately
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
