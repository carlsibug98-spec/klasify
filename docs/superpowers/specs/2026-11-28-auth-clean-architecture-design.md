# Auth Clean Architecture Slice — Design

Status: approved for implementation
Date: 2026-11-28
Pilot precedent: `2026-11-28-sync-clean-architecture-design.md`

## Problem

`lib/services/auth_service.dart` is the public auth facade, but it also owns
three pieces of application logic that are only testable through HTTP and
secure storage:

1. Sign-in ordering: switch the local account scope before saving the session.
2. Refresh ordering: discard a response whose token was replaced mid-flight.
3. Account deletion ordering: delete on the server, clear the session, notify,
   then detach the local schedule.

`AuthApi` (462 lines), `SessionStore` (116), and `AdminApi` (82) already
separate transport, storage, and admin envelopes, but they sit flat in
`lib/features/auth/` and depend on each other through concrete classes.

## Goal

Apply the same feature-first slice used for `sync`:

```
lib/features/auth/
  domain/
    entities/auth_types.dart      AuthApiException, AuthResponse,
                                  RefreshOutcome, RefreshResult
    entities/auth_policy.dart     shouldRefreshSession
    repositories/auth_ports.dart  AuthGateway, SessionStorage, AccountScope
  application/
    sign_in.dart                  register/login/google/sign-up completion
    refresh_session.dart          silent refresh with the token race guard
    delete_account.dart           server delete + local detach
    update_profile.dart           PATCH /auth/me + persist
    change_password.dart          POST + clear the revoked session
  data/
    auth_api.dart                 HTTP + 401 refresh-and-retry (implements port)
    admin_api.dart                admin envelopes
    session_store.dart            secure storage (implements port)
    local_account_scope.dart      adapter over LocalScopeService
```

`lib/services/auth_service.dart` stays in place as the singleton facade and
composition root. Its public API, `ChangeNotifier` behaviour, static test
hooks (`testClient`, `baseUrlOverride`, `isSecureApiUrl`), and
`AuthApiException` export do not change. Screens and tests keep their imports.

## Non-goals

- No screen, widget, or copy edits.
- No change to HTTP endpoints, JSON shapes, or `php-backend/`.
- No Riverpod, Bloc, get_it, or code generation.
- No change to `LocalScopeService`, `SyncService`, or the sync slice.
- No APK rebuild in this task.

## Invariants to preserve

### Sign-in (`register`, `login`, `signInWithGoogle`, `signUpWithGoogle`)

1. Call the gateway.
2. Read `user['id']`; a non-`int` throws
   `AuthApiException(code: 'LOCAL_SCOPE_FAILED')` with the existing message,
   before any local write.
3. `AccountScope.ensureForUser(id)` runs **before** `SessionStorage.save`.
   A scope failure logs the original error and throws the same
   `LOCAL_SCOPE_FAILED`; nothing is saved.
4. Save token, user, and expiry, then notify once.
5. Return the user map.

### Refresh (`refreshSession`)

1. Read the stored token; no token returns false.
2. Call the gateway with that token.
3. Re-read the token. If it changed (logout or new sign-in), return false and
   apply nothing.
4. `unreachable` keeps the session and returns false.
5. `rejected` clears the session, notifies, returns false.
6. `refreshed` applies token/expiry/user; a storage failure keeps the existing
   session and returns false; success notifies and returns true.

### Account deletion (`deleteAccount`)

1. Capture `currentUser['id']`.
2. `DELETE /auth/account` first; a failure throws before any local change and
   keeps the session.
3. Clear the session and notify.
4. If the id is an `int`, `detachAccount(id)` runs after the notification.
   A detach failure is logged, not thrown.

### Token freshness (`ensureFreshToken`)

`shouldRefreshSession(expiresAt, now)` is true when the expiry is missing or
strictly before `now + 10 minutes`. Exactly ten minutes away is not refreshed,
matching the current `isBefore` check.

## Dependency rule

- `domain` imports only `dart:` and its own files.
- `application` imports only `dart:`, `domain/`, and `application/`.
- `data` may import `domain/`, `application/`, packages, and app services.
- `lib/services/auth_service.dart` (presentation/facade) imports all three but
  is the only composition root.

Enforced by a source-reading test, like the sync guard.

## Compatibility notes

- `AuthApiException`, `AuthResponse`, `RefreshOutcome`, and `RefreshResult`
  move to `domain/entities/auth_types.dart`. `auth_api.dart` imports them, and
  `auth_service.dart` re-exports `AuthApiException`, so existing imports keep
  compiling.
- `AuthApi` and `SessionStore` implement the new ports directly; no wrapper
  classes are added.
- `LocalAccountScope` is a small adapter so `LocalScopeService` does not depend
  on a feature folder.
- `AuthApi` keeps its 401 `TOKEN_EXPIRED` refresh-and-retry behaviour; the
  application layer never sees that retry.
