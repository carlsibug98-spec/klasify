# 0003 — Keep `SyncService` as a facade and guard every sync write by scope generation

Date: 2026-11-28
Status: Accepted

## Context

Sync runs while the signed-in account can change. The local database is one
SQLite file per account; `LocalScopeService` swaps the active file and
`AppDatabase` bumps a monotonic generation. A response that arrives after a
switch must not write one account's rows into another account's file.

The current implementation gets this right with two checks: pin the scope
before reading, capture the generation, then before every write check the
generation, await the database gate, and check again.

Screens and tests depend on `SyncService.instance` and its `bool` return
values. A clean-architecture extraction must not break that API or weaken the
guard.

## Decision

1. `SyncService` remains the public singleton and the only composition root for
   sync. It forwards to a `SyncController` and keeps the existing methods,
   getters, static test hooks, and `buildStatusPushRow` export.
2. The scope guard becomes a `SyncSession.writeIfCurrent(generation, write)`
   port. Its adapter preserves the exact ordering: generation check, database
   gate, generation check, write.
3. `PushSync` and `PullSync` capture the generation after pinning and route
   every post-response write through that port. A moved scope aborts the
   operation and writes nothing.
4. The session user is checked again after pinning; a mismatch sends no
   request.
5. Push still runs before pull, and a failed push still skips the pull.

## Consequences

Positive:

- The data-loss guard is explicit and testable with a fake session.
- Screens and existing tests need no edits.
- The wire contract and the guard each have one owner.

Negative:

- The facade imports both data and application because it is a composition
  root. That keeps the presentation boundary clean, but the facade itself is
  not an example of the dependency rule.
- The guard is split between the port and its adapter, so both need review when
  the scope model changes.

## Alternatives considered

- **Move screens to a new controller API immediately.** Rejected: unnecessary
  churn and a larger rollback.
- **Put the guard in the SQLite adapter.** Rejected: the adapter cannot know
  which request generation a write belongs to.
- **Drop the second generation check.** Rejected: the database gate can open
  after a switch, so the check after awaiting it is what makes the guard safe.
