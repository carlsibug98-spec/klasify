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
- APK build (verified 2026-10-27): the sandbox has no root, JRE-only system java, and a 9.9 GB rootfs — use this exact recipe:
  ```bash
  cd android && JAVA_HOME=/home/z/jdk-21 ANDROID_HOME=/home/z/android-sdk \
    ./gradlew assembleRelease -Ptarget-platform=android-arm64 \
    -Dorg.gradle.internal.instrumentation.agent=NONE
  ```
  - NEVER mix `flutter build apk` and direct `./gradlew` in the same session: flutter-spawned daemons run with the instrumentation agent ON, creating a second full set of transform-cache entries (~3 GB) that fills the disk.
  - Always run `./gradlew --stop` + `pkill -9 -f gradle` when switching invocation style.
  - Android SDK: local pieces at `/home/z/android-sdk` (build-tools, platforms, platform-tools, licenses); the NDK lives on PolarFS at `/tmp/my-project/android-sdk/ndk` (symlinked from the SDK dir; PolarFS rejects symlinks created ON it, and is too slow for Gradle caches — never point GRADLE_USER_HOME there).
  - JDK 21 (Temurin, includes javac) at `/home/z/jdk-21`; debug keystore generated at `~/.android/debug.keystore`.
  - Release APK is unsigned by design (project leaves signing to the developer's key); `app-release.apk` ≈ 94 MB arm64.
