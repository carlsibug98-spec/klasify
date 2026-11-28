# 0001 — Feature-first Clean Architecture with an enforced dependency rule

Date: 2026-11-28
Status: Accepted

## Context

Klasify is organized mostly by technical type (`screens/`, `services/`,
`data/`, `models/`), with two feature folders (`features/auth`,
`features/schedule_import`). The app is well tested (609 tests), but boundaries
are implicit. `SyncService` alone owns HTTP, JSON, SQLite, account-scope
pinning, timers, and UI notification. Nothing stops the next feature from
copying that shape.

A full rewrite into feature packages would touch nearly every file, churn the
test suite, and deliver no user-visible change.

## Decision

Adopt a pragmatic, feature-first Clean Architecture and migrate one feature at
a time. Each migrated feature uses:

```
domain/         pure Dart entities and ports
application/    use cases; depends only on domain
data/           adapters that implement the ports
presentation/   controllers and widgets; never imports data
```

Dependencies point inward. `domain` imports only `dart:` core libraries. The
composition root is the only place that knows the concrete adapters.

The first pilot is `sync`. Auth and import move only if the pilot makes them
easier to test and reason about.

Boundaries are enforced by a source-reading test, not by convention. The test
fails if `domain` imports Flutter or infrastructure packages, or if
`presentation` imports `data`.

## Consequences

Positive:

- Sync rules can be tested with in-memory fakes and no database or HTTP.
- The wire contract and the scope guard have one named owner each.
- The migration is reversible feature by feature.
- Existing screens and tests keep working through the facade.

Negative:

- More files and one mapping layer between models and domain entities.
- Two structures coexist during the migration.
- The architecture test is a custom check, not a compiler rule.

## Alternatives considered

- **Big-bang Clean Architecture.** Rejected: high risk, no user value, churns
  the test suite.
- **Feature packages with path dependencies.** Rejected: build and versioning
  overhead with no second consumer.
- **Do nothing.** Rejected: sync is the highest-risk feature and the hardest to
  test in isolation.
