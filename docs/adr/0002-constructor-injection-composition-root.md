# 0002 — Constructor injection and one composition root; no DI package yet

Date: 2026-11-28
Status: Accepted

## Context

The app uses singletons and direct construction: screens call
`SyncService.instance`, services call `AuthService.instance` and
`DatabaseHelper.instance`. Tests replace behavior through static hooks
(`AuthService.testClient`, `baseUrlOverride`, `autoStartEnabled`) and real
SQLite/HTTP servers.

Adding `get_it`, Riverpod, or Bloc now would introduce a second way to obtain
dependencies before the first feature has a proven seam.

## Decision

Use constructor injection for the sync feature:

- use cases receive `SyncLocalStore`, `SyncRemoteGateway`, and `SyncSession`;
- adapters receive their collaborators (or a call-time provider for the base
  URL);
- `services/sync_service.dart` is the single composition root that constructs
  the concrete adapters and use cases.

No service locator. No state-management package. The existing static test
hooks stay on the facade until the feature no longer needs them.

## Consequences

Positive:

- Dependencies are explicit and visible in constructors.
- Tests use plain fakes with no package setup.
- One place wires production objects, so swapping an adapter is local.

Negative:

- The composition root grows with each migrated feature.
- Singletons still exist behind the adapters during the migration.
- A future shared-state decision is deferred, not answered.

## Alternatives considered

- **get_it.** Rejected for now: hides dependencies and makes tests easier to
  write badly.
- **Riverpod.** Rejected for now: it is a state-management choice as much as a
  DI choice, and the pilot does not need either.
- **Bloc.** Rejected for now: the sync controller is a timer plus three
  operations, not a state machine that needs events.
