# Klasify Sync Backend (Node.js + MySQL, in Docker)

Zero-install backend: the REST API and MySQL both run as Docker containers.
Your machine only needs **Docker Desktop** (+ **HeidiSQL** to browse data).

```
Flutter app (phone)  ──HTTP──>  Node.js API (Docker :8080)  ──SQL──>  MySQL 8 (Docker :3306)  <──HeidiSQL
```

## Endpoints (docs/sync_api_contract.md)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | — | `{"status":"ok","version":"1.0.0"}` |
| POST | `/auth/register` | — | 201 + JWT |
| POST | `/auth/login` | — | 200 + JWT |
| POST | `/auth/refresh` | Bearer | reissues a token (grace for expired) |
| DELETE | `/auth/account` | Bearer | soft-deletes user + data, 204 |
| POST | `/sync/push` | Bearer | upserts by `local_id`, returns `{local_id → server_id}` |
| GET | `/sync/pull?since=<iso>` | Bearer | rows changed since, tombstones included |

Errors always `{ "error": "...", "code": "ERROR_CODE" }` —
`INVALID_CREDENTIALS`, `TOKEN_EXPIRED`, `EMAIL_EXISTS`, `VALIDATION_ERROR`, `SERVER_ERROR`, `NOT_FOUND`.

## Quick start

```bash
cd backend
docker compose up -d

# verify
curl http://localhost:8080/health
# → {"status":"ok","version":"1.0.0"}
```

## HeidiSQL

1. Open **HeidiSQL** → **New** session
2. Network type: **MySQL (TCP/IP)** — Hostname `127.0.0.1` — Port `3306`
3. User `root`, Password `klasify_dev`, Database `klasify_sync`
4. **Open** — you'll see `users`, `classes`, `events`, `class_statuses`,
   `sync_cursors` plus the three `active_*` views.

The schema (docs/mysql_schema.sql) is auto-created on the *first* start.
`docker compose down -v` wipes data; a fresh `up` re-runs the schema.

## Flutter build (test on a real phone)

```
flutter build apk --dart-define=KLASIFY_API_URL=http://<YOUR_PC_LAN_IP>:8080
```

Use the PC's LAN IP (e.g. `192.168.1.5`), never `localhost` — the phone
talks to the API over Wi-Fi.
