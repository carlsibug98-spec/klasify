# Klasify — The Complete Walkthrough

> A teaching guide to every layer of the app: what each file does, how the UI runs,
> where data lives on the phone, and how it travels to MySQL and back.
> Written for the mock defense — read Parts 1–4 for the story, Parts 5–10 for the
> mechanics, and Part 12 for the questions you are likely to be asked.

---

## 0. How to use this guide

There are three ways to read it:

| If you have… | Read this |
|---|---|
| 10 minutes | Part 1 + Part 12.1 (the 60-second pitch) |
| 1 hour | Parts 1–4, then the flow you plan to demo in Part 8 |
| A full study session | Everything, in order |

The one sentence to memorize:

> **Klasify is a local-first Flutter class timetable. The phone's SQLite database is
> the source of truth for the UI; the PHP/MySQL backend is an optional sync and
> school-admin layer, not a dependency for using the app.**

Everything else in this document is evidence for that sentence.

---

## Contents

- [Part 1 — What the app is](#part-1--what-the-app-is)
- [Part 2 — The big picture](#part-2--the-big-picture)
- [Part 3 — Cold start: what runs before the first pixel](#part-3--cold-start-what-runs-before-the-first-pixel)
- [Part 4 — Navigation and the screen map](#part-4--navigation-and-the-screen-map)
- [Part 5 — Data model and SQLite](#part-5--data-model-and-sqlite)
- [Part 6 — Every file, explained](#part-6--every-file-explained)
- [Part 7 — How each major screen works](#part-7--how-each-major-screen-works)
- [Part 8 — The five flows you must be able to narrate](#part-8--the-five-flows-you-must-be-able-to-narrate)
- [Part 9 — The backend, layer by layer](#part-9--the-backend-layer-by-layer)
- [Part 10 — Sync correctness details (the hard questions)](#part-10--sync-correctness-details-the-hard-questions)
- [Part 11 — Testing, CI, and release](#part-11--testing-ci-and-release)
- [Part 12 — Mock defense toolkit](#part-12--mock-defense-toolkit)
- [Appendix A — Schema quick reference](#appendix-a--schema-quick-reference)
- [Appendix B — API quick reference](#appendix-b--api-quick-reference)
- [Appendix C — Commands](#appendix-c--commands)
- [Appendix D — The one-slide summary](#appendix-d--the-one-slide-summary)

---

## Part 1 — What the app is

### 1.1 Product in one page

Klasify is an Android-first Flutter app for students. Its core jobs:

1. **Hold a weekly class schedule** — subject, room, professor, weekday, start/end time.
2. **Show what matters now** — Today highlights the live class or the next one.
3. **Let students mark occurrences** — Finished, Not attending, Cancelled, for one
   class, until a date, or until cleared.
4. **Import a timetable from a photo or PDF** — OCR runs on-device; every row is
   reviewed before saving.
5. **Remind before class** — weekly local notifications, with per-occurrence skipping.
6. **Show school context** — one-off events and an office-availability strip.
7. **Back up and restore** — manual JSON export plus a quiet automatic backup.
8. **Optionally sync and administer** — accounts, cross-device sync, admin roles,
   department broadcasts, office management.

### 1.2 Deliberate constraints

| Constraint | Why it matters in the defense |
|---|---|
| Local-first | The app is fully usable with no account and no network. Sync is additive. |
| SQLite is the UI's source of truth | Screens never wait for HTTP. They read SQLite and listen for changes. |
| Sync is best-effort | Failures do not block edits; the next cycle retries. |
| Server is optional | Signed-out users keep all data; account deletion leaves local data. |
| OCR is on-device | No schedule image leaves the phone. |
| Reminders are local | No push server is involved. |
| Android is the primary target | The home-screen widget and notification channels are Android-native. |

### 1.3 Version and stack

- App version: `1.4.4+15` (`pubspec.yaml`)
- Flutter: `>= 3.44.0`, Dart `>= 3.12.0`
- Local database: SQLite via `sqflite`, schema **version 9**, file `class_schedule.db`
- Backend: PHP 8 + MySQL/MariaDB (XAMPP-compatible), JWT HS256, bcrypt cost 12
- Tests: 67 Dart test files, 526 tests, all passing (verified Nov 11, 2026);
  plus 56 PHP parity tests

---

## Part 2 — The big picture

### 2.1 Layer diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ PRESENTATION                                                        │
│  main.dart → MaterialApp → AppRouter → screens/ + widgets/          │
│  Screens hold short-lived UI state; they read/write through services│
└───────────────────────────────┬─────────────────────────────────────┘
                                │ method calls
┌───────────────────────────────▼─────────────────────────────────────┐
│ DOMAIN / SERVICES                                                   │
│  models/        plain data + validation helpers                     │
│  utils/         pure rules (overlap, next class, backup codec)      │
│  services/      auth, sync, reminders, backups, widget, theme       │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ CRUD + change notifications
┌───────────────────────────────▼─────────────────────────────────────┐
│ LOCAL PERSISTENCE                                                   │
│  data/database_helper.dart  → change-notifying facade               │
│  data/app_database.dart     → SQLite connection, schema, migrations │
│  data/repositories/*.dart   → all SQL, one file per aggregate       │
│  SQLite file: class_schedule.db                                     │
│  SharedPreferences: preferences, cursors, device id, onboarding     │
│  FlutterSecureStorage: JWT + cached user JSON                       │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ HTTPS/HTTP JSON (optional, signed in)
┌───────────────────────────────▼─────────────────────────────────────┐
│ BACKEND (php-backend/)                                              │
│  .htaccess → index.php route table → src/{auth,sync,admin}.php      │
│  MySQL: users, classes, events, class_statuses, office_statuses,    │
│         password_resets, sync_cursors, rate_limit_hits              │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 The dependency rule

```
screens  →  services  →  DatabaseHelper  →  repositories  →  SQLite
   │            │              (facade)          (all SQL)
   └────────────┴────→  models / validation / utils (pure, no I/O)
```

- A **widget** never talks to SQLite directly.
- A **screen** may call `DatabaseHelper` for reads/writes, and services for
  cross-cutting work (sync, reminders, backups).
- A **model** never imports a screen or a service.
- SQL lives only in `lib/data/repositories/`; `DatabaseHelper` is the
  change-notifying facade that preserves the existing public API.
- `AppDatabase` is the only class that opens the connection, creates schema,
  or runs migrations.
- `sync_service.dart` is the only class that calls `/sync/*`.
- Screens call `auth_service.dart`; it is a thin facade over
  `features/auth/auth_api.dart` (every `/auth/*` call) and
  `features/auth/admin_api.dart` (every `/admin/*` call).
- `features/auth/session_store.dart` is the only class that reads or writes
  the secure-storage session keys.

This is why the app is teachable: each layer has one job.

### 2.3 Why the phone is the source of truth

If the network is down, every screen still works:

- Today, Week, Profile read from SQLite.
- Add/edit/delete write to SQLite immediately.
- Reminders, the widget, and auto-backup react to the database change.
- Sync is a background convenience that pushes and pulls later.

The server never sits between a tap and the screen. That is the core design
decision to defend.

---

## Part 3 — Cold start: what runs before the first pixel

`lib/main.dart` is deliberately small. In order:

1. `WidgetsFlutterBinding.ensureInitialized()` — Flutter plugins are ready.
2. `initCrashReporting(...)` — if no Sentry DSN was compiled in (the normal
   case), it simply runs the callback. If a DSN exists, Sentry wraps `runApp`.
3. `AuthService.instance.restoreSession()`:
   - Reads `klasify_auth_token`, `klasify_auth_user`, `klasify_auth_expires_at`
     from **FlutterSecureStorage** (Android Keystore-backed).
   - Puts the token back into the in-memory user map.
   - Fires a silent `refreshSession()` so a role/department change made on
     another device lands without signing out. Offline failures are swallowed;
     only a rejected token clears the session.
4. `SyncService.instance.ensureStarted()` — merely touching the singleton wires
   its auth listener. The constructor calls `_onAuthChanged()`, which starts the
   5-minute timer **only if a session exists**.
5. `AutoBackupService.instance.attach()` — subscribes to database changes and
   schedules a quiet backup after the first change (and on launch).
6. `OnboardingStore.isCompleted()` — chooses the initial route.
7. `ThemeModeService.instance.load()` — restores light/dark/system.
8. `runApp(ScheduleApp(showOnboarding: ...))`.

`ScheduleApp` is a `ListenableBuilder` on `ThemeModeService`, so changing the
theme rebuilds `MaterialApp` without restarting the app.

`onGenerateInitialRoutes` builds **only** the initial route. Without it,
Flutter would stack `/` under `/onboarding`, and finishing onboarding would
reveal a duplicate shell.

### 3.1 Startup sequence diagram

```
Android launch
  │
  ├─ Flutter engine + plugins
  ├─ initCrashReporting (no-op unless DSN)
  ├─ restoreSession ──→ SecureStorage
  ├─ SyncService.ensureStarted
  │     └─ auth listener: signed in? start 5-min timer + syncNow()
  ├─ AutoBackupService.attach (async)
  ├─ OnboardingStore.isCompleted
  ├─ ThemeModeService.load (async)
  └─ runApp
        └─ MaterialApp
              └─ initial route: /onboarding or /
                    └─ MainNavigationScreen (Today | Week | Profile)
```

---

## Part 4 — Navigation and the screen map

### 4.1 One route table

`lib/routes/app_routes.dart` holds string constants. `lib/routes/app_router.dart`
is the **only** file that maps a route to a screen. If you add a screen, you add
a constant and a `case`. There is no scattered `Navigator.push(MaterialPageRoute(...))`
for top-level navigation; screens use `Navigator.pushNamed`.

| Route | Screen | Arguments / behavior |
|---|---|---|
| `/` | `MainNavigationScreen` | The three-tab shell |
| `/schedule` | `ScheduleScreen` | Week agenda (also embedded as a tab) |
| `/class-form` | `EditClassScreen` | `null` = new, `int` = new on weekday, `ClassItem` = edit, `true` = return draft |
| `/import-draft-editor` | `EditClassScreen` | `ClassItem`; `returnDraft: true`, does not save |
| `/onboarding` | `OnboardingScreen` | `true` = replay from Settings |
| `/import-schedule` | `ImportScheduleScreen` | optional file path argument |
| `/backup` | `BackupScreen` | manual export/restore + auto-backup status |
| `/reminders` | `RemindersScreen` | notification permissions and lead time |
| `/edit-class` | `EditClassScreen` | shortcut used by older entry points |
| `/login`, `/signup` | auth screens | return `true` on success |
| `/settings-privacy` | `SettingsPrivacyScreen` | account, preferences, legal, support |
| `/personal-details` | `PersonalDetailsScreen` | name/email, delete account |
| `/password-security` | `SecurityHubScreen` | password, sessions |
| `/change-password` | `ChangePasswordScreen` | current + new password |
| `/reset-password`, `/reset-password-confirm` | reset flow | request code, consume code |
| `/legal-terms`, `/legal-privacy`, `/legal-standards` | legal screens | static copy |
| `/admin` | `AdminScreen` | offices + super-admin user roles |

`AppRouter.routeObserver` lets `MainNavigationScreen` know when a pushed route
(the class editor, the import flow) popped back. This is how a pending coach
tour or a widget refresh is retried at the right moment.

### 4.2 The shell

`MainNavigationScreen` owns:

- **Today** — `HomeScreen` (tab 0)
- **Week** — `ScheduleScreen` (tab 1)
- **Profile** — `ProfileScreen` (tab 2)
- A floating quick-actions button, a coach-tour overlay, and a custom bottom bar.
- The Android widget sync: on init and on every database change, it loads
  classes + statuses and pushes them to `NextClassWidgetService.sync(...)`.

It also exposes static `ValueNotifier`s (`tabRequest`, `weekDayRequest`) so a
child screen can ask the shell to switch tabs or jump to a weekday without
knowing the shell's internals.

---

## Part 5 — Data model and SQLite

### 5.1 Tables at a glance

Database file: `class_schedule.db`, schema version 9.

#### `classes`

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | Local id used by the UI |
| `subject` | TEXT NOT NULL | At least 2 characters |
| `room` | TEXT NOT NULL | Required |
| `professor` | TEXT NOT NULL | At least 2 characters; empty input becomes `Not specified` |
| `day` | INTEGER | 1 = Monday … 7 = Sunday (same as `DateTime.weekday`) |
| `start_minutes` | INTEGER | 0–1439, minutes since midnight |
| `end_minutes` | INTEGER | 1–1440, strictly greater than start |
| `deleted` | INTEGER | 0 live, 1 tombstone |
| `updated_at` | TEXT | UTC ISO-8601, stamped on every local write |
| `server_id` | INTEGER | Server row id after a successful push |

Created with `CHECK` constraints, then `_createValidationTriggers` adds
`BEFORE INSERT` / `BEFORE UPDATE` triggers that repeat the same rules. Why both?
The CHECKs protect fresh installs; the triggers protect old databases that were
created before the constraints existed. **Validation cannot be bypassed by an
old install.**

#### `class_status` (singular)

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | Local id |
| `class_id` | INTEGER | Local class id |
| `status` | TEXT | `finished`, `not_attending`, `cancelled` |
| `start_date` | TEXT | `yyyy-MM-dd`, inclusive |
| `end_date` | TEXT nullable | inclusive; `NULL` = until cleared |
| `deleted` | INTEGER | Tombstone |
| `updated_at` | TEXT | Sync stamp |
| `server_id` | INTEGER | Server id after push |

A status is a **date range**, not a boolean. One class can have several
non-overlapping ranges. The pure functions in `models/class_status.dart`
implement range replacement/splitting; the database just stores rows.

#### `events`

| Column | Type | Meaning |
|---|---|---|
| `id` | INTEGER PK | Local id |
| `title` | TEXT | At least 2 characters |
| `venue` | TEXT | May be empty → "venue to confirm" copy |
| `date` | TEXT | `yyyy-MM-dd` |
| `start_minutes` | INTEGER | 0–1439; events have no end time |
| `reminder_enabled` | INTEGER | Per-event switch |
| `lead_minutes` | INTEGER | 5, 10, 15, or 30 |
| `category` | TEXT | `personal` or `school` |
| `department` | TEXT nullable | `NULL` = school-wide |
| `broadcast` | INTEGER | Admin post, read-only for regular users |
| `deleted` | INTEGER | Tombstone |
| `updated_at` | TEXT | Sync stamp |
| `server_id` | INTEGER | Server id after push |

Events use `CHECK` constraints only; rows have existed only since schema v6, so
there is no legacy data for triggers to police.

#### `office_statuses`

| Column | Type | Meaning |
|---|---|---|
| `office_name` | TEXT PK | Server key, e.g. `guidance` |
| `status` | TEXT | `open`, `closed`, `break` |
| `custom_message` | TEXT nullable | "Back at 2pm" |
| `updated_at` | TEXT | Server timestamp |

This table is a **pure cache of server rows**. It has no `deleted` column. When
a pull says an office is deleted, `upsertOfficeStatusFromServer` removes the row
outright. The app never invents office rows; a fresh offline install shows no
strip until the first successful pull.

### 5.2 Migrations v1 → v9

`onUpgrade` never drops user data. Each step is additive:

| Version | Change |
|---|---|
| 1 | Base `classes` table |
| 2 | Validation triggers for legacy databases |
| 3 | Rename placeholder `unknown room` → `Room to confirm` |
| 4 | `class_status` table |
| 5 | Rebuild `class_status` for `finished` + multiple ranges |
| 6 | `events` table |
| 7 | Sync columns: `deleted`, `updated_at`, `server_id`; `category` on events |
| 8 | Re-run the same idempotent migration to heal a dev-era drift |
| 9 | Department + broadcast on events; `office_statuses` cache |

Two teaching points:

- **Why version 8 repeats version 7:** `openDatabase` skips both `onCreate` and
  `onUpgrade` when the version number matches. A dev-era database claimed v7 but
  lacked some columns. Bumping to v8 forces the additive migration to run again.
  Same-version drift never heals, so you bump.
- **Why legacy rows get a one-time timestamp:** the v7 migration stamps every
  `updated_at IS NULL` row once. Otherwise a null timestamp would match the
  delta query forever, and every sync would re-push the same legacy rows.

### 5.3 DatabaseHelper: the only SQL owner

`DatabaseHelper` is a singleton `ChangeNotifier`:

```dart
DatabaseHelper.instance.addListener(...)
```

Every successful write calls `notifyListeners()`. That is the app's local event
bus. It is how:

- Today/Week reload when a class changes,
- the Android widget refreshes,
- auto-backup schedules a new file,
- the import review notices that saved classes changed while it was open.

Key methods, grouped:

**Read**
- `getAll()` / `getByDay(day)` — live classes only (`deleted = 0`), ordered by day/time.
- `getAllEvents()`, `getOfficeStatuses()`.
- `getClassStatuses()` — groups status rows by class id.
- `getChangedClasses/Events/ClassStatuses(since)` — sync delta, includes tombstones.

**Write**
- `insert` — validates, checks overlaps inside a transaction, stamps `updated_at`.
- `update` — same, excluding the edited row from overlap checks.
- `delete` — tombstones the class and all its statuses.
- `restoreDeleted` — un-tombstones the class and statuses, re-checks overlaps.
- `insertMany` — one transaction for an import; all or nothing.
- `replaceAll` / `replaceAllEvents` — tombstones all live rows then inserts the
  restore set in one transaction.
- `replaceSelected(ids, classes)` — removes selected classes and inserts replacements.
- `setClassServerId` / `setEventServerId` / `setClassStatusServerId` — remember
  the server mapping after a push.

**Status ranges**
- `setClassStatus` — applies a range, splitting existing ranges it overlaps.
- `clearClassStatus(entry, day:)` — removes one day, preserving the rest.
- `restoreClassStatuses(before)` — undo path.
- `deleteStatusesFrom(classId, date)` — used when a class moves weekday; past
  marks stay, future marks are tombstoned.

**Sync**
- `upsertClassFromServer`, `upsertEventFromServer`,
  `upsertClassStatusFromServer`, `upsertOfficeStatusFromServer`.
- `purgeDeleted(pushedBefore)` — hard-deletes tombstones that were already pushed.

### 5.4 Validation

Application-level and database-level validation mirror each other:

- subject ≥ 2 chars
- room non-empty
- professor ≥ 2 chars
- day 1–7
- `0 ≤ start < end ≤ 1440`
- no overlapping classes on the same day
- event title ≥ 2 chars, valid date shape, valid lead time

Overlap rule: `start < existing.end && end > existing.start`. A class ending at
10:00 and another starting at 10:00 do **not** overlap.

Why validate in three places (model/screen, `DatabaseHelper`, SQLite triggers)?
Because data arrives by three doors: form input, backup/import, and sync. The
database is the last line of defense, so no door can corrupt the schedule.

---

## Part 6 — Every file, explained

The repository has 504 tracked files. The sections below cover all source
files; test fixtures and generated assets are grouped at the end.

### 6.1 Root files

| File | Purpose |
|---|---|
| `pubspec.yaml` | App name/version, dependencies, assets |
| `pubspec.lock` | Exact resolved dependency versions |
| `analysis_options.yaml` | Lint rules |
| `.metadata` | Flutter project metadata |
| `.gitignore`, `.gitattributes` | Git hygiene |
| `README.md` | Project overview and run instructions |
| `CLAUDE.md` | Instructions for AI coding agents working in this repo |
| `.github/workflows/ci.yml` | Windows CI: analyze, test, build profile APK, release artifact |
| `plans/` | Small implementation plans (flyoff easing, checkmark scale) |
| `releases/` | Built APK snapshots (1.4.3 and 1.4.4) |
| `tool/` | Benchmark and OCR harnesses, 16 KB page checker |
| `BENCHMARK_ROUND*.md` | OCR accuracy/speed experiment logs |
| `FULL_APP_AUDIT.md`, `DESIGN_*`, `SCANNER_FIX_NOTES.md`, `OCR_VALIDATION_GUIDE.md` | Engineering audit/history |

### 6.2 `lib/` root

| File | Purpose |
|---|---|
| `main.dart` | Boot sequence, theme binding, initial route |

### 6.3 `lib/routes/`

| File | Purpose |
|---|---|
| `app_routes.dart` | Route name constants |
| `app_router.dart` | The only route → screen mapping; unknown-route fallback; route observer |

### 6.4 `lib/models/`

| File | Purpose |
|---|---|
| `class_item.dart` | Class row; day/time formatting; `unspecifiedProfessor` sentinel; `formatRoom` |
| `class_status.dart` | Status enums, date-range math, range splitting, "active on date" rules |
| `event_item.dart` | Event row; reminder fire-time math; upcoming checks; category enum |
| `office_status.dart` | Office cache row; `fromMap`; display name; open/closed helpers |

### 6.5 `lib/data/`

| File | Purpose |
|---|---|
| `database_helper.dart` | `ChangeNotifier` facade: preserves the public API and notification semantics; delegates every call |
| `app_database.dart` | Singleton connection owner: schema v9, migrations, validation triggers, `resetForTesting` |
| `db_timestamps.dart` | `utcStamp()` and `parseInstant()` shared by repositories |
| `validation/class_rules.dart` | `validateClass`, `validateNoOverlaps` |
| `validation/event_rules.dart` | `validateEvent`, `dateKeyForEvent` |
| `repositories/class_repository.dart` | Class CRUD, overlap checks, replace/import, restore, server upsert, class server ids |
| `repositories/event_repository.dart` | Event CRUD, replace, server upsert, event server ids |
| `repositories/status_repository.dart` | Status ranges, undo snapshots, status tombstones, status server upsert/ids |
| `repositories/office_repository.dart` | Office availability cache read + server upsert |
| `repositories/sync_repository.dart` | Purges already-pushed tombstones across classes, events, and statuses |

### 6.6 `lib/services/`

| File | Purpose |
|---|---|
| `auth_service.dart` | `ChangeNotifier` facade: sign-in/out state, role getters, silent refresh orchestration, profile/password, admin forwarders, base URL. Delegates to `features/auth/` |
| `widget_data_actions.dart` | Database callbacks injected into the class delete/undo, Mark class, and event sheets so the widgets stay out of the data layer |
| `sync_service.dart` | Push → pull orchestration, cursors, device id, 5-minute timer, backoff, auth gating |
| `reminder_service.dart` | Local notification channel, permissions, weekly class reminders, event alarms, pruning |
| `auto_backup_service.dart` | Debounced atomic JSON backup to app support dir, rolling copies, status |
| `next_class_widget_service.dart` | Sends classes + marked dates to Android over a MethodChannel |
| `crash_reporting.dart` | Opt-in Sentry wrapper; no DSN = no SDK |
| `onboarding_store.dart` | "Has the user seen onboarding?" flag |
| `theme_mode_service.dart` | Light/dark/system preference, persisted |
| `coach_tour_store.dart` | "Has the coach tour been shown?" flag |
| `first_class_coach_store.dart` | "Has the empty-schedule coach been dismissed?" flag |
| `swipe_hint_store.dart` | "Has the swipe hint been dismissed?" flag |
| `app_info.dart` | App version/build label and release copy |

**Auth implementation (`lib/features/auth/`)**

| File | Purpose |
|---|---|
| `session_store.dart` | Secure-storage keys, restore, token read for authorized calls, save/refresh/clear, in-memory user map, expiry |
| `auth_api.dart` | HTTP for register/login/Google/reset/profile/password, refresh outcome model, `AuthApiException`, base URL + release HTTPS policy, one-shot refresh-and-retry |
| `admin_api.dart` | User, role, department, and office admin endpoints; request shaping and response unwrapping |

### 6.7 `lib/theme/`

| File | Purpose |
|---|---|
| `app_theme.dart` | Light/dark `ThemeData`, spacing, radii, motion constants, page padding |
| `compose_colors.dart` | Palette tokens shared by screens/widgets |

### 6.8 `lib/utils/`

| File | Purpose |
|---|---|
| `next_class.dart` | Finds the live class or next upcoming class, skipping marked occurrences; label/countdown text |
| `schedule_rules.dart` | `findOverlappingClass` for the editor |
| `schedule_backup_codec.dart` | Encode/decode the JSON backup format; limits and validation |
| `class_text_input_rules.dart` | Input formatters/capitalization for class fields |

### 6.9 `lib/screens/` (20 files)

| File | Purpose |
|---|---|
| `main_navigation_screen.dart` | Three-tab shell, quick actions, coach tour, widget sync |
| `home_screen.dart` | Today: hero, queue, events, offices, empty states, first-run coach |
| `schedule_screen.dart` | Week: weekday strip, day agenda, stacks, swipe actions, status sheet |
| `edit_class_screen.dart` | Add/edit form, validation, overlap check, save/delete, draft mode |
| `backup_screen.dart` | Export, restore from file, restore from auto-backup, auto-backup toggle |
| `reminders_screen.dart` | Master switch, lead time, event gate, exact-alarm warning |
| `onboarding_screen.dart` | Three-page first-run flow; replay mode |
| `auth/login_screen.dart` | Email/password + Google sign-in |
| `auth/signup_screen.dart` | Registration, display name, department |
| `auth/legal_sheets.dart` | Signup-time legal consent sheets |
| `profile/profile_screen.dart` | Profile tab: identity, schedule shortcuts, settings, logout |
| `profile/settings_privacy_screen.dart` | Account/preferences/legal/support hub; sync now; admin entry |
| `profile/personal_details_screen.dart` | Edit name/email; delete account |
| `profile/security_hub_screen.dart` | Password and session controls |
| `profile/change_password_screen.dart` | Current + new password |
| `profile/reset_password_screens.dart` | Forgot code request + confirmation |
| `profile/admin_screen.dart` | Office management; super-admin user roles/departments |
| `profile/legal_screens.dart` | Terms, privacy, community standards |
| `profile/profile_shared.dart` | Shared profile rows, groups, pills, title bars |
| `profile/profile_sheets.dart` | Help centre, contact support, sign-out/delete sheets |

### 6.10 `lib/widgets/` (41 files)

| File | Purpose |
|---|---|
| `app_notification.dart` | In-app success/warning/error/info banners |
| `app_state_transition.dart` | Animated loading → content → error transitions |
| `bottom_navigation_item.dart` | Custom bottom-bar item |
| `campus_break_divider.dart` | Coffee/break marker between class stacks |
| `class_card.dart` | Full class card used by week/other surfaces |
| `class_delete_undo.dart` | Delete + undo flow, restores statuses |
| `class_segment_row.dart` | One row in a segmented stack |
| `class_tags.dart` | Subject/room/professor chips |
| `coach_hint.dart` | Small one-shot hint bubble |
| `coach_tour_overlay.dart` | Spotlight walkthrough |
| `component_kit.dart` | Shared small components |
| `day_chips.dart` | Weekday selector chips |
| `day_status_sheet.dart` | Mark Finished / Not attending / Cancelled with span |
| `delete_confirmation_dialog.dart` | Destructive confirmation |
| `edit_class_time_picker_sheet.dart` | Start/end picker for the editor |
| `empty_state_card.dart` | Friendly empty state |
| `error_view.dart` | Error + retry |
| `event_date_picker_sheet.dart` | Event date picker |
| `event_sheet.dart` | Add/edit event, category, reminder, broadcast |
| `event_tile.dart` | Event row on Today |
| `first_run_options.dart` | Scan / add tiles for empty schedule |
| `klasify_skeleton.dart` | Loading skeleton |
| `live_pulse.dart` | "Live" dot animation |
| `next_class_card.dart` | Hero card for live/next/celebration states |
| `office_name_sheet.dart` | Add/rename office |
| `office_status_editor_sheet.dart` | Set open/closed/break + note; rename/retire |
| `office_status_strip.dart` | Horizontal office availability strip |
| `pill.dart` | Small status pill |
| `pinned_action_bar.dart` | Bottom pinned save/confirm bar |
| `pressable_scale.dart` | Press feedback animation |
| `quick_action_menu.dart` | FAB menu contents |
| `quick_actions_button.dart` | Expanding FAB |
| `schedule_time_picker.dart` | Shared time picker |
| `section_header.dart` | Small-caps section label |
| `selected_day_header.dart` | Sticky day header |
| `settings_row.dart` | Settings list row |
| `status_banner.dart` | Inline status/warning banner |
| `swipe_actions.dart` | Swipe-to-edit/delete plane |
| `time_box.dart` | Start/end time block |
| `week_agenda_view.dart` | Week agenda layout + break threshold |
| `weekday_tile.dart` | Weekday tile in the strip |

### 6.11 `lib/features/schedule_import/` (36 files)

**Entry and model**

| File | Purpose |
|---|---|
| `import_schedule_screen.dart` | Orchestrates pick → scan → parse → review → save; owns dialogs/notifications; preserves drafts while paused |
| `import_route_cache.dart` | Keeps an in-progress import route mounted when visiting Today |
| `models/import_draft.dart` | Editable row before it becomes a `ClassItem`; note kinds |
| `models/import_mode.dart` | Add / replace-all / replace-selected choice |

**Services**

| File | Purpose |
|---|---|
| `services/schedule_ocr_service.dart` | PaddleOCR lifecycle, image/PDF scanning, cancellation, page windows |
| `services/timetable_grid_scanner.dart` | Finds weekday headers, time rules, and cells; merges OCR blocks spatially |
| `services/ocr_image_preprocessor.dart` | Crop, deskew, enhance, upscale, threshold for OCR |
| `services/import_save_service.dart` | Commits reviewed rows with the chosen mode, syncs reminders, builds the success copy |

**Utils — parsing and geometry**

| File | Purpose |
|---|---|
| `utils/parse_chain.dart` | Parser cascade + scoring across candidates |
| `utils/import_review_analysis.dart` | Pure review logic: draft → `ClassItem`, conflict/invalid notes, OCR and room flags, classes that remain per mode |
| `utils/sectioned_schedule_parser.dart` | Header bands, day sections, exam records, day-less blocks |
| `utils/schedule_text_parser.dart` | Lower-level text line parsing |
| `utils/timetable_parser.dart` | Line-oriented timetable parser with no-guess fallback |
| `utils/cor_schedule_parser.dart` | CHED/registrar-style "COR" schedule parsing |
| `utils/domain_rescoring.dart` | Rescores OCR text using subject/room/professor vocabulary |
| `utils/schedule_line_preparation.dart` | Normalizes lines before parsing |
| `utils/timetable_format.dart` | Time/day formatting for parser output |
| `utils/timetable_grid_geometry.dart` | Grid line/column detection |
| `utils/timetable_grid_pixels.dart` | Pixel-level grid analysis (runs in an isolate) |
| `utils/timetable_clock_ticks.dart` | Reads clock/time-rule ticks |
| `utils/cell_assignment.dart` | Maps OCR boxes to grid cells |
| `utils/adaptive_grid_rules.dart` | Layout heuristics per grid type |
| `utils/adaptive_ocr_threshold.dart` | Chooses binarization threshold |
| `utils/ocr_image_size.dart` | Decode size + scaling math |
| `utils/ocr_resample.dart` | Resampling helpers |
| `utils/skew_correction.dart` | Rotate/deskew image |
| `utils/skew_profile_estimator.dart` | Estimates skew from projection profiles |
| `utils/pdf_page_image.dart` | Renders a PDF page to an image |
| `utils/pdf_timetable_text.dart` | Extracts embedded PDF text |
| `utils/pdf_timetable_scan_result.dart` | PDF scan result model (pages, grid, text) |

**Widgets**

| File | Purpose |
|---|---|
| `widgets/import_review_widgets.dart` | Review cards, badges, banners, replacement pickers |
| `widgets/import_picker_card.dart` | Empty-state card: choose/scan a file, manual entry, offline copy |
| `widgets/import_selected_file_tile.dart` | Selected-file name, type icon, filename ellipsis |
| `widgets/import_replacement_options.dart` | Add / replace-all / replace-selected controls and confirmation copy |
| `widgets/import_success_card.dart` | Import-complete card with View schedule / Import another |
| `widgets/import_source_preview_screen.dart` | Zoomable source image/PDF preview |

### 6.12 `test/` (67 Dart test files)

The suite is organized by risk area:

| Area | Files |
|---|---|
| Database | `database_crud_test`, `database_validation_test`, `events_db_test`, `office_statuses_db_test`, `class_status_db_test`, `class_status_migration_test` |
| Models/rules | `class_status_test`, `event_item_test`, `next_class_test`, `schedule_rules_test`, `office_status_test`, `schedule_backup_codec_test` |
| Screens/widgets | `edit_class_screen_test`, `home_screen_hero_test`, `home_screen_stacks_test`, `events_home_test`, `weekly_schedule_view_test`, `ui_widgets_test`, `day_status_sheet_test`, `office_editor_manage_test`, `office_status_strip_test`, `office_name_sheet_test`, `swipe_actions_test`, `large_text_test`, `component_kit_test` |
| Auth/legal | `auth_legal_test`, `signup_department_test`, `app_info_test` |
| Sync/backup | `auto_backup_test`, `reminder_service_test`, `crash_reporting_test` |
| Onboarding/coach | `onboarding_test`, `coach_tour_test`, `coach_tour_store_test`, `coach_tour_trigger_test`, `first_class_coach_store_test`, `home_first_class_coach_test` |
| Import/OCR | `import_draft_test`, `import_review_analysis_test`, `import_review_edit_test`, `import_timetable_cancel_test`, `import_weak_grid_rescue_test`, `import_widgets_test`, `schedule_text_parser_test`, `sectioned_schedule_parser_test`, `cor_schedule_parser_test`, `timetable_parser_test`, `timetable_grid_scanner_test`, `timetable_grid_geometry_test`, `timetable_grid_pixels_test`, `timetable_clock_ticks_test`, `ocr_image_size_test`, `adaptive_ocr_threshold_test`, `skew_profile_estimator_test`, `pdf_page_image_test`, `pdf_timetable_text_test`, `pdf_timetable_scan_result_test`, `non_timetable_schedule_test` |
| Benchmarks | `bench3_round_test`, `bench4_round_test`, `bench5_scan_speed_test`, `bench6_accuracy_test`, `bench7_cor_accuracy_test`, `scan_improvements_test` |
| Visual/golden | `app_look_capture_test`, `design_capture_test`, `event_sheet_capture_test`, `widget_test` |

Support files:
- `test/goldens/` — reference PNGs for visual regressions.
- `test/fixtures/` — OCR benchmark images and truth JSON.
- `test/golden_tolerance.dart` — pixel-diff tolerance.

**Why this matters in the defense:** the golden tests are pinned to Windows and
Flutter 3.47.9 because text rasterization differs by OS/SDK. CI runs on Windows
for that reason. Changing the SDK without re-recording goldens causes 1–4%
pixel drift even when no UI changed.

### 6.13 `android/`

| File | Purpose |
|---|---|
| `app/src/main/kotlin/.../MainActivity.kt` | Hosts the Flutter engine; MethodChannel receiver for widget updates |
| `.../NextClassWidgetProvider.kt` | `AppWidgetProvider`: reads schedule JSON, computes live/next state, renders RemoteViews, schedules boundary alarms |
| `.../WidgetCalendarIds.kt` | Generated cell ids for the calendar layout |
| `AndroidManifest.xml` | Permissions, widget receiver, boot/time-change intents |
| `res/layout/widget_next_class.xml` | Compact/board widget layout |
| `res/layout/widget_next_class_calendar.xml` | Tall calendar layout |
| `res/xml/next_class_widget_info.xml` | Widget metadata/sizing |
| `res/drawable/next_class_widget_*` | Widget backgrounds, icons, pills, progress |
| `res/values*/` | Colors, dimens, styles, strings, launcher background |
| `app/build.gradle.kts` | App id, SDK levels, signing, Flutter config |
| `ios/` | Standard Flutter iOS runner scaffolding (not the primary target) |

**Widget flow:** the Flutter shell calls `NextClassWidgetService.sync(classes, statuses)`.
The MethodChannel writes the JSON into the widget's `SharedPreferences`, then
`NextClassWidgetProvider.updateAllWidgets` renders. The provider filters marked
dates (finished/not attending/cancelled), finds the live or next class, renders
the right layout for the widget's height, and books an `AlarmManager` boundary
for the next start/end plus a minute tick. It also listens for
`TIME_TICK`, `DATE_CHANGED`, `TIME_CHANGED`, `TIMEZONE_CHANGED`,
`LOCALE_CHANGED`, `BOOT_COMPLETED`, and `MY_PACKAGE_REPLACED`.

### 6.14 `php-backend/` (20 files)

| File | Purpose |
|---|---|
| `.htaccess` | Rewrite everything to `index.php`; pass Authorization header; deny `config.php` |
| `config.php` | DB/JWT/Google settings with env overrides, plus the dev-only reset-code log flag |
| `index.php` | CORS, route table, error → JSON mapping |
| `src/common.php` | PDO/MySQL, JSON, JS coercions, timestamps, JWT, auth guard, rate limit, logging |
| `src/auth.php` | Register/login/Google/refresh/profile/password/delete |
| `src/sync.php` | Push and pull |
| `src/admin.php` | Users, roles, departments, offices |
| `src/google_jwks.php` | Verifies Google ID tokens via JWKS |
| `README.md` | Setup/deployment |
| `PROVENANCE.md` | Origin/porting notes |
| `tests/bootstrap.php` | Test environment |
| `tests/run.php` | Test runner |
| `tests/auth_test.php` | Auth parity tests |
| `tests/sync_test.php` | Sync parity tests |
| `tests/admin_test.php` | Admin parity tests |
| `tests/google_jwks_test.php` | Google verification tests |
| `storage/logs/` | App log (plaintext reset codes only when the dev flag is on) |

### 6.15 `docs/` (31 files)

| File | Purpose |
|---|---|
| `sync_api_contract.md` | Authoritative API shapes, status codes, error codes |
| `mysql_schema.sql` | Full MySQL DDL + admin provisioning |
| `ADMIN.md` | Admin operations |
| `DEPLOYMENT.md` | Deployment steps |
| `RELEASE_CHECKLIST.md` | Pre-release checklist |
| `ROADMAP.md` | Product roadmap and open questions |
| `APP_AUDIT_2026-10-31.md` | Audit snapshot |
| `campus/it-building.md` | IT Building evacuation plans, floors 1–4, rooms/exits |
| `privacy-policy.html` | Public privacy policy |
| `design/*.html/png` | Settings/backup design references |
| `superpowers/plans/*` | Implementation plans (UI, OCR, migration, offices) |
| `superpowers/specs/*` | Design specs including the PHP/XAMPP migration |
| `store/klasify-play-launch-kit.docx` | Store listing kit |

---

## Part 7 — How each major screen works

### 7.1 Today (`home_screen.dart`)

Init:
1. Register a database listener.
2. `_load()` reads four things independently:
   - classes,
   - class statuses,
   - events,
   - office statuses.
   Each secondary read has its own `catchError`; a failed event read does not
   blank the schedule.
3. `_syncRemindersOnLaunch()` refreshes pending notifications.
4. `_scheduleHeroRefresh()` wakes at the next minute boundary, so "Ends in 12
   min" is correct without polling every second.

Build:
- `findNextClass(classes, now, statuses)` decides the hero:
  - live class (isNow),
  - next upcoming class,
  - or a celebration/empty state.
- Classes that already ended or were marked leave the queue; the hero promotes
  the live/next class, and the rest render as segmented stacks.
- Consecutive classes merge into a stack when the gap is below
  `WeekAgendaView.breakThreshold`; each stack boundary shows a break divider.
- Events are filtered to `isUpcomingOn(now)`; the minute ticker makes past
  events disappear exactly when they start.
- The office strip renders only cached rows. If the table is empty, it is hidden.

Office editing: an admin taps an office → `showOfficeStatusEditorSheet` →
`AuthService.adminSetOfficeStatus` → PATCH → `SyncService.syncNow()` → next pull
updates the cache. The strip shows "Syncing…" until the server value arrives.

### 7.2 Week (`schedule_screen.dart`)

- Holds `_selectedDay` (defaults to today), classes, statuses.
- Weekday strip changes the day; content slides in from the direction of travel.
- A minute timer re-renders time-sensitive states.
- Lifecycle resume reloads from SQLite.
- A `dayRequest` notifier lets Today's celebration teaser jump to a weekday.
- Each class row supports tap → status sheet, swipe → edit/delete, long-press →
  delete with undo.

### 7.3 Add/edit a class (`edit_class_screen.dart`)

Entry points:
- FAB → add on today,
- weekday tile → add on that day,
- class row → edit,
- import review → edit a draft (`returnDraft`).

Save path:
1. Trim fields; empty professor becomes `Not specified`.
2. Validate subject/room/professor/day/time.
3. Build `ClassItem` with the existing id when editing.
4. If `returnDraft`, pop the item only — no database write.
5. Else check overlap via `findOverlappingClass`.
6. `DatabaseHelper.insert` or `update`. If an edit changed the weekday,
   `deleteStatusesFrom(classId, today)` removes future marks from the old day;
   past marks stay as history.
7. `ReminderService.sync()`.
8. `notifyListeners()` already fired inside the database call, so Today/Week
   reload, the widget updates, and auto-backup schedules.
9. Pop.

### 7.4 Mark a class (`day_status_sheet.dart` + `class_status.dart`)

The sheet offers:
- status: Finished / Not attending / Cancelled,
- span: This class / Until date / Until I clear.

`setClassStatus` runs in one transaction and returns the class's previous
ranges so the sheet can undo. The sheet writes through `DayStatusActions`
injected by the caller (`DayStatusActions.database` in the app), so it never
imports the database directly:
1. Builds an incoming range (single date, date→chosen date, or date→∞).
2. Calls `replaceStatusRange`, which cuts any overlapping existing ranges into
   before/after segments. Split segments get fresh ids — reusing the source id
   would collide with the row still in the table.
3. Deletes every status row for that class, then re-inserts the resulting set
   with a fresh `updated_at`. Existing tombstones are re-attached afterwards so
   unpushed deletions are not lost.
4. Next push sends all changed rows.

Clearing one day uses `clearStatusOnDay`: it splits the range around that date
instead of deleting the whole range.

### 7.5 Events (`event_sheet.dart`, `event_item.dart`)

The sheet saves and deletes through `EventActions` injected by the caller
(`EventActions.database` in the app), keeping `DatabaseHelper` out of the
widget. It offers:
- Add/edit title, venue, date, start time, category, reminder switch, lead time.
- School events are visible to everyone; personal events belong to the user.
- Admins can broadcast a school/department event. Broadcast rows are read-only
  for regular users; `_canManageEvent` checks role and department.
- Events have no end time: they are "starts at" moments.
- Reminder fire minute = `start - lead`, clamped at 0 (never before midnight).

### 7.6 Import (`import_schedule_screen.dart`)

The pipeline in order:

```
Pick file (PNG/JPG/WEBP/PDF, ≤20 MB)
  │
  ├─ PDF → render pages → embedded text + optional grid rows
  └─ image → grid scan
        ├─ detect weekday headers
        ├─ detect clock ticks / time rules
        ├─ map OCR boxes into cells
        └─ if grid is weak: run flat-text cascade too
  │
  ├─ ParseChain (sectioned → list → no-guess)
  ├─ Domain rescoring (subjects, rooms, professors)
  ├─ Build ImportDraft rows
  ├─ Analyse against saved classes (conflicts, invalid rows, unknown rooms)
  └─ Review screen
        ├─ edit row → returns a draft, not a save
        ├─ add manual row
        ├─ choose Add / Replace all / Replace selected
        └─ Save → ImportSaveService → insertMany / replaceAll / replaceSelected
```

Important behaviors:
- **No guessing**: if a weekly grid cannot be mapped reliably, the app saves
  nothing and asks for a clearer image or manual entry.
- **Every row is reviewed**; OCR confidence below the threshold marks a row.
- **Atomic save**: a failed insert rolls back the whole import.
- **Drafts survive** a trip to Today via `ImportRouteCache`.
- **Cancellation** stops after the current OCR step and prunes nothing saved.
- **PDF limits**: scans up to 24 pages; warns when pages were skipped or could
  not be mapped.

### 7.7 Reminders (`reminder_service.dart`)

Two independent reminder families:

**Weekly classes**
- Master switch in SharedPreferences (`class_reminders_enabled`).
- Lead time: 10 / 30 / 60 minutes.
- For each class, it computes `start - lead` (clamped at 0).
- If the class has status marks, it schedules **one notification per date** up
  to the last marked date, skipping marked dates.
- After the last mark, it schedules a **weekly repeating** notification.
- An until-cleared mark has no tail; clearing it triggers a re-sync.
- IDs are deterministic hashes of subject|room|day|start|date, so rescheduling
  replaces rather than duplicates.
- Stale IDs are pruned at the end, even if scheduling failed midway.

**Events**
- Two gates: the global event-reminders switch and the per-event switch.
- One-off alarm at `start - lead`; past events are skipped.

Android specifics:
- Channel `class_schedule_reminders_v5` (bumped when the description changed).
- Requests notification permission and exact-alarm access.
- If exact alarms are unavailable, it uses inexact scheduling and warns.

### 7.8 Backup and restore (`backup_screen.dart`, `auto_backup_service.dart`)

**Manual export**
- `ScheduleBackupCodec.encode(classes, events)` → JSON file via `FilePicker.saveFile`.
- Format: `{format, version: 1, exportedAt, classes[], events[]}`.
- Legacy `class_schedule_backup` files are accepted.

**Automatic backup**
- `AutoBackupService` listens to `DatabaseHelper`.
- 1.5 s debounce collapses bursts of edits.
- Writes atomically (temp + rename) to the app support directory:
  - `auto_backups/klasify-auto-backup.json` (always current),
  - `auto_backups/klasify-backup-yyyyMMdd-HHmm.json` (rolling, 6 kept).
- Android's device backup can include this directory in Google Drive, but
  Klasify itself never opens a socket for it.

**Restore**
- Pick a file or load the auto backup.
- Decode + validate every row and overlaps **before** touching the database.
- Confirm the destructive replace.
- `replaceAll(classes)` then `replaceAllEvents(events)` — each in a transaction.
- Re-sync reminders.

### 7.9 Profile, auth, settings, admin

- **Profile** shows identity, import/backup shortcuts, settings, logout.
- **Login/signup** call `AuthService`, which stores the session in secure storage.
- **Settings & privacy** shows admin entry only for admins; account rows only
  when signed in; sync-now; notifications; dark mode; legal; help.
- **Personal details** edits name/email; delete account calls the server and
  clears the session, leaving local schedule data in place (documented decision).
- **Admin**:
  - `admin` sees office availability for their scope.
  - `super_admin` also sees users, can change roles/departments, add/rename/retire
    offices.
  - Rename = tombstone old key + insert new row with same status/note, so phones
    drop the old name and gain the new one on the next pull.
  - Retire = soft delete; students lose it on the next sync.

### 7.10 Cross-cutting UI behavior

- **Theme:** `ThemeModeService` (light/dark/system) is a `ChangeNotifier`.
  `ScheduleApp` wraps `MaterialApp` in a `ListenableBuilder`, so changing the
  theme rebuilds instantly without a restart. The choice is persisted in
  SharedPreferences.
- **Coach marks:** separate one-shot stores cover onboarding completion, the
  post-first-class tour, the empty-schedule coach, and the swipe hint. Each
  persists a flag, so no hint is shown twice.
- **Feedback:** `showAppNotification` is the single in-app banner
  (success/warning/error/info). Destructive actions confirm first; a class
  delete shows a snackbar with Undo.
- **Motion and layout:** `PressableScale` gives press feedback,
  `AppStateTransition` animates loading → content, and profile/settings hubs cap
  content at 680 px while schedule surfaces use the full width.
- **Resilience:** read failures render an `ErrorView` with retry. Screens
  subscribe to `DatabaseHelper`, so a write made on another surface appears
  immediately.

---

## Part 8 — The five flows you must be able to narrate

### The master path (draw this first)

```
UI tap
  → screen validates and builds a model
  → DatabaseHelper write in ONE transaction
       → SQLite row + fresh updated_at (UTC)
       → notifyListeners()
            ├─ Today / Week rebuild from SQLite
            ├─ Android widget JSON is refreshed
            └─ auto-backup debounce starts
  → if signed in, next SyncService cycle:
       push: POST /sync/push  → PHP → MySQL upsert
             server returns local_id → server_id + server_time
             client stores the mapping and the cursor
       pull: GET /sync/pull?since=...
             server returns deltas + tombstones
             client upserts into SQLite (last-write-wins)
             notifyListeners() → screens refresh
```

Every flow below is a variation of that path. If you can narrate this diagram,
you can answer most architecture questions.

### Flow 1 — Add a class, end to end

```
Tap FAB → EditClassScreen
  → validate fields
  → findOverlappingClass(...)
  → DatabaseHelper.insert(item)
       ├─ validateClass
       ├─ transaction: _validateSchedule + INSERT
       │     └─ SQLite trigger re-validates
       ├─ stamp updated_at (UTC ISO)
       └─ notifyListeners()
  → ReminderService.sync()
  → pop
  → Today/Week listeners reload from SQLite
  → widget service pushes JSON to Android
  → auto-backup debounce starts
```

No network call is required. If signed in, the next sync push sends the row.

### Flow 2 — Delete a class and undo

```
Swipe/long-press → deleteClassWithUndo(ClassDeleteActions.database)
  → deleteClass(id)
       ├─ classes.deleted = 1, updated_at = now
       ├─ class_status.deleted = 1 for that class
       └─ notifyListeners()
  → snackbar with Undo
  → Undo: restoreClass(class) + restoreMarks(id, marks)
       ├─ re-check overlaps
       ├─ deleted = 0, updated_at = now
       └─ notifyListeners()
```

The tombstone is intentional: if the deletion had been pushed, a hard delete
would make the server resurrect the row on the next pull. Tombstones travel to
the server; `purgeDeleted` removes them only after the server has acknowledged.

### Flow 3 — Mark a class "not attending until Friday"

```
Status sheet → setClassStatus(status, span)
  → replaceStatusRange(existing, incoming)
       ├─ cut overlapping ranges before/after
       ├─ tombstone replaced rows
       └─ insert new range
  → notifyListeners()
  → reminders reschedule (skip marked dates)
  → next push sends changed statuses
```

### Flow 4 — Sync push, then pull

```
SyncService.syncNow()
  ├─ push()
  │    ├─ read lastPushAt from SharedPreferences
  │    ├─ getChangedClasses/Events/Statuses(lastPushAt)
  │    ├─ POST /sync/push  { device_id, last_push_at, rows[] }
  │    ├─ server upserts by (user_id, local_id) or server_id
  │    ├─ response maps local_id → server_id
  │    ├─ client stores mappings
  │    └─ store server_time as new lastPushAt
  └─ pull() only if push succeeded
       ├─ GET /sync/pull?since=lastPullAt&device_id=...
       ├─ upsert classes/events/statuses/offices
       ├─ purgeDeleted(lastPushAt)
       └─ store server_time as new lastPullAt
```

Why push before pull? If pull ran first while local changes were unsent, server
rows could overwrite those local edits. Waiting loses nothing; the next cycle
pushes first.

### Flow 5 — Office status change (the case study)

```
Admin taps office on Today or Admin screen
  → PATCH /admin/office-statuses/guidance {status, custom_message}
  → 200
  → SyncService.syncNow()
       → pull returns office_statuses rows
       → upsertOfficeStatusFromServer
            ├─ deleted? → delete local row
            └─ else → INSERT OR REPLACE
       → notifyListeners()
  → strip re-renders
```

If the office is retired:

```
DELETE /admin/offices/guidance → server row deleted=1
  → next pull includes {office_name: guidance, deleted: true}
  → client deletes the local row outright
  → strip no longer renders it
```

### 8.1 Why the phone in front of you still shows three offices

This is a real, explainable state, not a bug in the code:

- The three office rows were cached on **Nov 9**, when the phone last synced.
- The server rows are now `deleted=1` (retired on **Nov 11**).
- The phone is currently **signed out** (`FlutterSecureStorage.xml` is empty).
- `SyncService` only starts its timer and performs pulls when
  `AuthService.isLoggedIn` is true.
- Therefore the phone has never received the tombstones.

Fix: sign in once on the phone. The first `syncNow()` pulls the tombstones and
`upsertOfficeStatusFromServer` deletes the three rows. They stay gone after
logout because deletion is local and the rows are not re-created by the app.

The code does **not** hardcode offices: the table is created empty, and only a
server pull can insert rows.

---

## Part 9 — The backend, layer by layer

### 9.1 Request lifecycle

```
Phone → http://192.168.1.67/klasify-api/...
  → Apache .htaccess
       ├─ real file? serve it (except config.php is denied)
       └─ otherwise rewrite to index.php
  → index.php
       ├─ CORS headers
       ├─ OPTIONS → 204
       ├─ read_json_body() (once, before auth)
       ├─ match [method, regex, handler]
       ├─ handler(...) 
       └─ exit
  → exceptions:
       ApiError   → {error, code} with its status
       Throwable  → log + 500 SERVER_ERROR
```

The route table is a plain array. There is no framework and no dependency
manager. This is deliberate for XAMPP deployment.

### 9.2 Authentication

- **Register:** validate email/password (≥8), reject duplicate, bcrypt cost 12,
  insert user, return `{user, token, expires_at}` (201).
- **Login:** look up by email where `deleted=0`, `password_verify`, return token.
- **Google:** verify ID token via Google JWKS (or tokeninfo in fallback mode),
  require verified email, find by `google_sub` then email, optionally create in
  `signup` mode.
- **Refresh:** accepts an expired token only for 30 days after `exp`; a valid
  signature alone is not enough. It re-reads role, department and
  `token_version` from the DB, then issues a new 7-day token.
- **JWT:** HS256, claims `{user_id, email, tv, iat, exp}`, 7-day TTL. `tv` must
  match `users.token_version`.
- **Auth guard:** `require_auth()` reads `Authorization: Bearer`, verifies the
  JWT, then loads the user row. Missing/deleted users and revoked `tv` values
  are rejected on every request, not only at refresh time.
- **Revocation:** password change, password reset, and account deletion bump
  `token_version`, so every older token dies immediately. The app signs out
  after a password change because its own token is revoked too.
- **Rate limits:** register 10/hour/IP; login 10/minute/email and 30/minute/IP;
  forgot-password 5/hour/email and 20/hour/IP; reset-password 10/hour/email and
  30/hour/IP; Google 30/minute. Exceeding any bucket returns 429.
- **Password reset:** always returns 200 to avoid account enumeration; 6-digit
  code hashed with bcrypt, 15-minute expiry. Plaintext codes reach
  `storage/logs/app.log` only when `KLASIFY_DEBUG_RESET_CODES=1` (local dev);
  production needs a mailer.
- **Delete account:** soft-deletes the user and their classes/events/statuses,
  bumps `token_version`, and leaves local phone data alone.

### 9.3 Sync push

For each table, the server:

1. Validates every row and **skips** bad rows with a log line (partial success).
2. Resolves the caller's role/department for event broadcast rules.
3. Matches an existing row by `server_id` first, then by `(user_id, local_id)`.
4. Updates or inserts.
5. Returns `{local_id, server_id, updated_at}` for every accepted row.
6. Stores `last_push_at` in `sync_cursors` per `(user_id, device_id)`.

Classes are private to the user. Events can be personal or broadcast; a broadcast
row is stored with `user_id = NULL` and a department scope, and only an admin
whose scope covers it may edit it. Class statuses resolve their `local_class_id`
to a server class id; rows whose class is not yet on the server are skipped and
retried next cycle.

### 9.4 Sync pull

`GET /sync/pull?since=<iso>&device_id=<id>`:

- `since` is **inclusive**; re-seeing a row is harmless because upserts are
  idempotent.
- Returns classes for the user.
- Returns events where `user_id = caller` **or** broadcast (`user_id IS NULL`)
  matching the caller's department.
- Returns class statuses for the user.
- Returns office statuses where `department IS NULL` or matches the caller's
  department.
- Includes `deleted` rows so clients can apply tombstones.
- Stores `last_pull_at`.
- Returns `server_time`, which the client stores as its next cursor.

### 9.5 Admin

- `admin` and `super_admin` pass `admin_caller()`.
- Role/department changes and office add/rename/retire require `super_admin`.
- A department admin sees only users in their department (or themselves).
- Office list excludes deleted and department-scoped rows.
- Rename preserves availability and note by tombstoning the old key and inserting
  the new one.
- Self-demotion is blocked.

### 9.6 MySQL schema

| Table | Role |
|---|---|
| `users` | Account, bcrypt hash, Google sub, role, department, token_version, soft delete |
| `classes` | Per-user weekly rows, `local_id` mapping, soft delete |
| `events` | Per-user or broadcast rows, department scope, soft delete |
| `class_statuses` | Date ranges linked to server class ids |
| `office_statuses` | School/department office availability |
| `password_resets` | Hashed 6-digit codes, expiry, used timestamp |
| `sync_cursors` | Per-user/per-device push and pull cursors |
| `rate_limit_hits` | DB-backed rate limiting (PHP has no process memory) |

All timestamps are UTC `DATETIME(3)`. All syncable tables carry `updated_at`
and `deleted`.

### 9.7 Deployment (XAMPP)

1. Copy `php-backend/` under `htdocs/klasify-api`.
2. Create the database with `docs/mysql_schema.sql` (existing installs apply
   `docs/migrations/2026-11-14_token_version.sql`).
3. Set `config.php` values (or env vars), including a random `jwt_secret`;
   never ship the repository placeholder.
4. Keep MySQL on `bind-address=127.0.0.1`; do not expose port 3306 to the LAN.
5. Enable `mod_rewrite`.
6. Point the app at the host:
   `flutter run --dart-define=KLASIFY_API_URL=http://<LAN-IP>/klasify-api`.
   Release builds require an absolute `https://` URL and throw otherwise.
7. Health check: `GET /health` → `{"status":"ok","version":"1.0.0"}`.

The default URL in `features/auth/auth_api.dart` (re-exported as
`AuthService.baseUrl`) is the dev PC's LAN address; it is a compile-time
default, not a hardcoded account or school.

---

## Part 10 — Sync correctness details (the hard questions)

### 10.1 Last-write-wins, with a local edge

On pull, for an existing local row:

```
if local.updated_at > server.updated_at:
    keep local row
    only stamp server_id so the next push updates the same server row
else:
    overwrite local with server row
```

So the server wins ties, but a strictly newer local edit is not lost. The local
edit re-pushes on the next cycle.

### 10.2 Why local ids and server ids both exist

- SQLite needs a stable local primary key before the network exists.
- MySQL needs its own auto-increment id.
- `local_id` is remembered on the server.
- `server_id` is remembered on the phone.
- Future pushes match by server id first, so an edit updates rather than duplicates.

### 10.3 Tombstone lifecycle

```
Delete locally
  → deleted = 1, updated_at = now
  → push includes it
  → server sets deleted = 1
  → pull returns it (or it is already gone from live views)
  → purgeDeleted(lastPushAt) hard-deletes locally
```

If the app purged an unpushed tombstone, the server would still have the live
row, and the next pull would resurrect it. That is why the purge takes a cutoff.

### 10.4 Cursors

- Client: `klasify_last_push_at`, `klasify_last_pull_at` in SharedPreferences.
- Server: `sync_cursors` per user/device for observability.
- The client cursor is authoritative for what it asks next; the server cursor
  records the last time each device talked to it.
- The cursor is the server's `server_time`, not the phone's clock. This avoids
  clock skew.

### 10.5 Device id

`klasify_device_id` is a microsecond timestamp generated once per install. It is
sent with push and pull so the server can track cursors per device. It is not a
security identity; the JWT is.

### 10.6 Auth gating

- No session → `push()` and `pull()` return false immediately.
- No timer runs while signed out.
- Restoring a session at cold start starts the timer.
- Logging out stops the timer and cancels retries.

### 10.7 Failure and retry

- While signed in, the background timer runs every 5 minutes.
- A failed cycle schedules a retry at 30 s, 60 s, 120 s, 240 s, capped at 300 s.
  The attempt counter resets on a successful cycle.
- A retry only fires if the user is still signed in and no other sync is running.
- `SyncService.lastError` holds the last failure; Settings → "Sync now" reports
  the outcome to the user.

---

## Part 11 — Testing, CI, and release

### 11.1 Flutter tests

- `flutter analyze` must be clean.
- `flutter test` runs 67 files / 526 tests.
- Database tests use `sqflite_common_ffi` with a test-specific database name.
- Golden tests render screens and compare PNGs with a tolerance.
- OCR benchmarks shell out to Tesseract in CI because the native PaddleOCR
  engine cannot run in the test VM.
- The PHP parity harness (`php-backend/tests/run.php`) runs 56 tests against a
  disposable `klasify_test` database rebuilt from `docs/mysql_schema.sql`.

### 11.2 CI

`.github/workflows/ci.yml`:

1. Windows runner (goldens were recorded on Windows).
2. Flutter pinned to `3.47.9` — a different SDK re-rasterizes text.
3. Install Tesseract for OCR benchmark coverage.
4. `flutter analyze --no-fatal-infos`.
5. `flutter test --reporter expanded`.
6. `flutter build apk --profile`.
7. Upload APK artifact + GitHub prerelease.

### 11.3 Release hygiene

- `docs/RELEASE_CHECKLIST.md` covers version bump, changelog, APK, store copy.
- `releases/` keeps signed snapshots.
- Never commit untracked mockups (`.rnd`, `.taste-skill/`, `mockup_*.html`).

---

## Part 12 — Mock defense toolkit

### 12.1 The 60-second pitch

> Klasify is a local-first class timetable for students. Everything you see is
> backed by a SQLite database on the phone, so the app works with no account and
> no internet. A student can add classes by hand or scan a photo or PDF; OCR runs
> entirely on-device, and every row is reviewed before it is saved. Today shows
> the live or next class, Week shows the full timetable, and students can mark
> occurrences as finished, not attending, or cancelled. Reminders are scheduled
> locally, and an Android home-screen widget keeps the next class visible.
>
> On top of that, there is an optional PHP/MySQL backend. Signing in enables
> cross-device sync, school events, office availability, and admin tools. Sync is
> push-then-pull with per-device cursors and soft-delete tombstones, so edits and
> deletions survive offline periods. If the server is down, the app keeps working
> and the next sync catches up.

### 12.2 The 5-minute demo script

1. **Today** — point at the hero: "This is computed from the local database every
   minute; no network."
2. **Add a class** — show validation and the overlap rule; save.
3. **Week** — show the class appears immediately (database listener).
4. **Mark a class** — choose "Not attending, until Friday"; show the range pill.
5. **Reminders** — show lead-time choices and that reminders are local.
6. **Import** — pick a timetable photo, show the review screen, explain that
   nothing is saved until confirm.
7. **Backup** — show the automatic backup status and export format.
8. **Profile → sign in** — show sync, then open Admin (if demo account is admin)
   and change an office status.
9. **Explain the offline case** — turn off Wi-Fi, add a class, turn Wi-Fi back on,
   sync.

### 12.3 Likely questions and answers

**Q: Where is the data stored?**
A: In SQLite on the phone, file `class_schedule.db`, schema v9. Tables:
`classes`, `class_status`, `events`, `office_statuses`. Preferences and sync
cursors are in SharedPreferences; the session token is in Android Keystore-backed
secure storage.

**Q: Is the app useless without internet?**
A: No. Every core feature works offline. Only sync, account management, admin,
and fresh office/event pulls need the server.

**Q: How does the backend get the data?**
A: `SyncService` pushes rows changed since the last push, then pulls rows changed
since the last pull. The server maps local ids to server ids and returns the
mapping.

**Q: What happens if two devices edit the same class?**
A: Last-write-wins. The server wins ties; a strictly newer local edit is kept and
re-pushed.

**Q: How are deletions handled?**
A: Soft deletes. `deleted=1` plus a new timestamp travels to the server; after the
server acknowledges, the phone purges the tombstone. This prevents resurrection.

**Q: Why not delete rows immediately?**
A: Because a pull could bring the row back from the server. The tombstone is the
record that the deletion happened.

**Q: How do you stop duplicate rows after a push?**
A: The server returns `local_id → server_id`; the phone stores `server_id`. Future
pushes match by server id first.

**Q: What if the push fails?**
A: The pull is skipped. Applying server rows while unsent local changes are stuck
could overwrite them. The next cycle retries push first.

**Q: How do reminders work without a server?**
A: `flutter_local_notifications` schedules them with the OS. Class reminders are
weekly repeats; marked dates get individual one-off notifications that are
skipped, and the tail becomes a weekly repeat again.

**Q: Why are some notifications not exact?**
A: Android requires the "Alarms & reminders" permission for exact alarms. Without
it, the app schedules inexact alarms and warns the user.

**Q: How does OCR work?**
A: PaddleOCR runs on-device. The pipeline preprocesses the image (deskew, enhance,
threshold), detects grid geometry, maps text into cells, then runs a parser chain.
Every row goes to a review screen; low-confidence rows are flagged. If a weekly
grid cannot be mapped reliably, the app refuses to guess.

**Q: What is sent to the OCR service?**
A: Nothing. There is no OCR server. The image stays on the phone.

**Q: How is the schedule backed up?**
A: A manual JSON export and an automatic atomic JSON file after every change.
The automatic file lives in the app support directory and keeps six dated copies.

**Q: What does the backend use for auth?**
A: Email/password with bcrypt cost 12 and a 7-day HS256 JWT; optional Google
sign-in. Tokens carry a `tv` claim tied to `users.token_version`. Refresh
accepts an expired token only inside a 30-day grace window, re-reads the role
and `token_version`, and refuses revoked sessions.

**Q: How are passwords reset?**
A: A 6-digit code, bcrypt-hashed, valid 15 minutes, 5 requests/hour/email.
Reset attempts are also capped (10/hour/email, 30/hour/IP). The endpoint always
returns 200 so it cannot be used to discover registered emails. A successful
reset revokes existing sessions. In development the plaintext code reaches the
server log only with `KLASIFY_DEBUG_RESET_CODES=1`; production needs a mailer.

**Q: How do you prevent SQL injection?**
A: Every query uses PDO prepared statements with bound parameters
(`ATTR_EMULATE_PREPARES = false`).

**Q: How do you prevent unauthorized admin actions?**
A: `require_auth` validates the JWT and re-checks the user row (deleted users
and revoked token versions fail), `admin_caller` reads the role from the
database, and `admin_super_caller` narrows destructive/role-changing routes to
super admins. Self-demotion is blocked.

**Q: How do office statuses reach students?**
A: They are cached from `GET /sync/pull`. The app never creates offices. Retiring
an office sends a tombstone; the phone deletes its cached row.

**Q: Why do offices still show on the demo phone?**
A: It is signed out, so sync is not running. Sign in once and the next pull
delivers the tombstones. This is a state issue, not hardcoded data.

**Q: Why SQLite and not just the server?**
A: Latency, offline use, and reliability. A student in a basement classroom still
sees their timetable. The server is a sync and admin layer.

**Q: Why PHP instead of Node?**
A: The project migrated to XAMPP for simple campus deployment. The PHP API is a
behavioral port of the earlier Node API; the contract and tests are preserved.
`docs/superpowers/specs/2026-11-09-php-xampp-migration-design.md` records the
decision.

**Q: Is the app secure?**
A: Passwords are bcrypt-hashed; tokens are signed with a deployment-specific
secret and carry a revocable `tv`; deleted accounts fail closed; login,
register, and reset endpoints are rate-limited. Release builds refuse a
non-HTTPS API URL (debug keeps LAN HTTP for the demo). The token is in secure
storage, not plain preferences. SQL is parameterized. Remaining production
work is the TLS endpoint itself, a real mailer, and tightening CORS.

**Q: What is not implemented?**
A: Campus navigation, mini-map, live room occupancy, and turn-by-turn directions.
Only the IT Building data collection exists in `docs/campus/it-building.md`.
There is no model, table, endpoint, screen, search, or routing code for it.

**Q: What would you build next?**
A: Measure core usage first, then the cheap Phase A campus directory (room →
building → floor → nearest exit). Defer maps and live occupancy until there is a
data owner and evidence of demand.

**Q: What was the hardest bug?**
A: The OCR pipeline: grid geometry can lock onto a non-timetable image and hide a
parseable text schedule. The fix is a weak-grid rescue that scores both candidates
and refuses to guess when neither is credible. The benchmark suite pins the
regressions.

**Q: If it is offline-first, why does it request Internet permission?**
A: Only the optional sync, account, and admin features use it. If permission is
denied or the phone is offline, every core feature still works from SQLite.

**Q: What happens when the user signs out?**
A: The secure session is cleared, the sync timer stops, and no pulls run. The
local schedule, marks, events, and cached offices stay on the phone. Signing
back in resumes sync from the stored cursors.

**Q: How are time zones handled?**
A: Class and event times are stored as wall-clock minutes since midnight, so the
timetable does not shift when the phone travels. Sync timestamps are stored in
UTC. Reminders are scheduled in the phone's current local time zone.

**Q: How do you know the app still works?**
A: 527 Flutter tests, 68 files, golden screenshots, OCR benchmark fixtures, PHP
parity tests, and CI on a pinned Windows/Flutter toolchain.

### 12.4 Terms to define confidently

| Term | Meaning here |
|---|---|
| Local-first | The local database is authoritative for the UI; network is optional |
| Tombstone | A row kept with `deleted=1` so the deletion can sync |
| Cursor | The server timestamp marking what has already been pushed/pulled |
| LWW | Last-write-wins conflict resolution |
| Broadcast event | An admin-posted event visible to a school/department |
| Occurrence | One dated instance of a weekly class |
| Draft | An import row before it is saved |
| Pull | Fetch server changes since the cursor |
| Push | Send local changes since the cursor |
| Delta | The set of rows changed since a timestamp |

### 12.5 Honest limitations to admit

- Navigation/mini-map/live occupancy are roadmap items, not code.
- No mailer is configured; reset codes are only logged when the explicit dev
  flag is on. Production needs SMTP.
- The default API URL is a LAN HTTP address for debug; release builds enforce
  HTTPS, but the demo deployment has not been put behind TLS yet.
- Sync is last-write-wins, not a CRDT; simultaneous edits on two devices can
  lose one side's text.
- The backend is single-tenant per user for classes; there is no shared class
  roster.
- The iOS target is scaffolding; the widget and notification work are Android-first.
- Office data is only as fresh as the last successful pull.

---

## Appendix A — Schema quick reference

```
classes
  id, subject, room, professor, day, start_minutes, end_minutes,
  deleted, updated_at, server_id

class_status
  id, class_id, status, start_date, end_date,
  deleted, updated_at, server_id

events
  id, title, venue, date, start_minutes, reminder_enabled, lead_minutes,
  category, department, broadcast, deleted, updated_at, server_id

office_statuses
  office_name PK, status, custom_message, updated_at
```

## Appendix B — API quick reference

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | no | Health check |
| POST | `/auth/register` | no | Create account |
| POST | `/auth/login` | no | Sign in |
| POST | `/auth/google` | no | Google sign-in/signup |
| POST | `/auth/refresh` | bearer (may be expired) | New token |
| PATCH | `/auth/me` | bearer | Edit name/email |
| POST | `/auth/change-password` | bearer | Change password |
| POST | `/auth/forgot-password` | no | Request reset code |
| POST | `/auth/reset-password` | no | Consume reset code |
| DELETE | `/auth/account` | bearer | Soft-delete account |
| POST | `/sync/push` | bearer | Push changes |
| GET | `/sync/pull?since=` | bearer | Pull changes |
| GET | `/admin/users` | admin | List users (scoped) |
| PATCH | `/admin/users/{id}/role` | super_admin | Set role |
| PATCH | `/admin/users/{id}/department` | super_admin | Set department |
| GET | `/admin/office-statuses` | admin | List offices |
| PATCH | `/admin/office-statuses/{office}` | admin | Set status/note |
| POST | `/admin/offices` | super_admin | Add office |
| PATCH | `/admin/offices/{office}` | super_admin | Rename office |
| DELETE | `/admin/offices/{office}` | super_admin | Retire office |

Errors always have the shape `{ "error": "...", "code": "..." }`.

## Appendix C — Commands

```bash
# App
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter run --dart-define=KLASIFY_API_URL=http://192.168.1.67/klasify-api

# Backend (XAMPP)
# start Apache + MySQL, then:
curl http://192.168.1.67/klasify-api/health

# PHP parity tests (XAMPP's php.exe; use `php` if it is on PATH)
"C:\xampp\php\php.exe" php-backend/tests/run.php
```

## Appendix D — The one-slide summary

```
UI (Flutter)
  ↓ reads/writes
SQLite (source of truth)
  ↓ notifyListeners
Reminders · Widget · Auto-backup
  ↓ optional, signed in
SyncService  →  PHP API  →  MySQL
  ↑ pull (tombstones + deltas)
```

If you can draw that diagram and explain one flow across it, you can defend the
whole app.
