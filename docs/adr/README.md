# Architecture Decision Records

Short, numbered records of decisions that shape the codebase. Add a new file
for each decision; do not rewrite an accepted record. Supersede it with a new
one instead.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-feature-first-clean-architecture.md) | Feature-first Clean Architecture with an enforced dependency rule | Accepted |
| [0002](0002-constructor-injection-composition-root.md) | Constructor injection and one composition root; no DI package yet | Accepted |
| [0003](0003-sync-facade-and-scope-guard.md) | Keep `SyncService` as a facade and guard every sync write by scope generation | Accepted |
