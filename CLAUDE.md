# Klasify — Agent Instructions

## Mandatory Skills (standing directive from the user)

**Always use these three skills for any work on this project. Load them at the start of every session, before the first action:**

1. **impeccable** — design language for all UI work (`/home/z/my-project/skills/impeccable/`).
   - Run `scripts/impeccable context` once per session before design/editing UI (cwd = project root).
   - Read `reference/craft-floor.md` immediately before ANY UI edit, however small.
   - This is a Flutter app: use the `*.native.md` reference variants (android) where applicable.

2. **emil-design-eng** (Emil Kowalski's design engineering) — animation decisions, interaction polish, review format (Before/After/Why table).

3. **superpowers** (`using-superpowers`) — process discipline: check for and invoke relevant process skills first (brainstorming before building, systematic-debugging before fixing, test-driven-development for features, verification-before-completion before claiming done).

Skill priority: process skills first (they set the approach), then implementation/design skills carry it out. User instructions in this file override skill defaults.

## Project facts

- Local-first Flutter timetable app. Flutter SDK: `/home/z/flutter/bin/flutter`.
- Plans live in `docs/superpowers/plans/`, design specs in `docs/superpowers/specs/` (write a spec + plan there before non-trivial work).
- Shared worklog: `/home/z/my-project/worklog.md` — read before starting, append after finishing (format: Task ID / Agent / Task / Work Log / Stage Summary, section starts with `---`).
- Verification baseline (2026-10-27): `flutter analyze` clean (7 pre-existing infos), full suite 342 pass / 12 skip / 0 fail.
- APK build (when needed): `cd android && ./gradlew assembleDebug -Dorg.gradle.internal.instrumentation.agent=NONE`.
