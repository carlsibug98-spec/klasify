# Auth Clean Architecture Slice — Implementation Plan

Spec: `docs/superpowers/specs/2026-11-28-auth-clean-architecture-design.md`

Goal: extract auth application logic behind the existing `AuthService` facade
with no public API or behavior change.

Baseline: 635 tests green at `d80d07c`; `flutter analyze --no-fatal-infos`
clean.

## Task 1 — Domain types, policy, and ports

Files:

- `lib/features/auth/domain/entities/auth_types.dart`
- `lib/features/auth/domain/entities/auth_policy.dart`
- `lib/features/auth/domain/repositories/auth_ports.dart`

Steps:

1. Move `AuthApiException`, `AuthResponse`, `RefreshOutcome`, and
   `RefreshResult` out of `auth_api.dart` unchanged.
2. Add `shouldRefreshSession(DateTime? expiresAt, DateTime now)`.
3. Declare `AuthGateway`, `SessionStorage`, and `AccountScope` as
   `abstract interface class`.
4. Test `shouldRefreshSession` at the boundaries: null, past, 9:59, exactly
   10:00, and beyond.

Acceptance: `dart analyze lib/features/auth/domain` clean; policy tests pass.

## Task 2 — Application use cases (TDD)

Files:

- `lib/features/auth/application/sign_in.dart`
- `lib/features/auth/application/refresh_session.dart`
- `lib/features/auth/application/delete_account.dart`
- `lib/features/auth/application/update_profile.dart`
- `lib/features/auth/application/change_password.dart`
- `test/features/auth/auth_test_fakes.dart`
- `test/features/auth/sign_in_test.dart`
- `test/features/auth/refresh_session_test.dart`
- `test/features/auth/delete_account_test.dart`
- `test/features/auth/update_profile_test.dart`
- `test/features/auth/change_password_test.dart`

Steps:

1. Write fakes that record call order and can fail on demand.
2. Write failing tests for each invariant in the spec.
3. Implement the use cases until green.
4. `SignIn` throws `AuthScopeException(error, stack)` on a scope failure; the
   facade logs it and converts it to `LOCAL_SCOPE_FAILED`.
5. `RefreshSession` returns a status enum so the facade knows when to notify:
   `refreshed`, `rejected`, `unreachable`, `superseded`, `storageFailed`.
6. `DeleteAccount` exposes `deleteServerAccount()` and `detach(userId)` so the
   facade keeps the notify-before-detach ordering.

Acceptance: new tests pass; no Flutter or package imports in `application/`.

## Task 3 — Move the data adapters and rewire the facade

Steps:

1. Move `auth_api.dart`, `admin_api.dart`, and `session_store.dart` under
   `lib/features/auth/data/`.
2. Make `AuthApi implements AuthGateway` and
   `SessionStore implements SessionStorage`.
3. Add `LocalAccountScope implements AccountScope` over
   `LocalScopeService.instance`.
4. Rewire `lib/services/auth_service.dart` to construct the use cases and
   delegate to them. Keep every public member, signature, and doc comment.
5. Keep the `AuthApiException` export working.

Acceptance: `flutter analyze --no-fatal-infos` clean; the five existing auth
suites pass unchanged:
`auth_http_test.dart`, `auth_service_url_test.dart`,
`account_delete_scope_test.dart`, `scope_lifecycle_test.dart`,
`sync_scope_test.dart`.

## Task 4 — Architecture guard

File: `test/features/auth/auth_architecture_test.dart`

Steps:

1. Domain imports only `dart:` and `domain/`.
2. Application imports only `dart:`, `application/`, and `domain/`; no
   packages.
3. Assert all three layers exist.

Acceptance: the guard fails when a deliberate `../data/` import is added, then
passes when removed.

## Task 5 — Verification

1. `flutter analyze --no-fatal-infos`.
2. All auth-related tests, including the new ones.
3. Non-benchmark suite at `--concurrency=2`.
4. Benchmarks are untouched by this change; CI runs the full suite. If time
   allows, run them at `--concurrency=1` for local parity.
5. Confirm `git diff` contains only intended files and no mockups.

## Task 6 — Commit and push

1. Commit explicit paths with
   `refactor(auth): extract clean architecture slice behind AuthService`.
2. Push and verify `HEAD == origin/main`.
3. Watch the CI run for the pushed SHA.

## Status

- [x] Task 1 — domain
- [x] Task 2 — application
- [x] Task 3 — data + facade
- [x] Task 4 — architecture guard
- [x] Task 5 — verification
- [ ] Task 6 — commit, push, CI
