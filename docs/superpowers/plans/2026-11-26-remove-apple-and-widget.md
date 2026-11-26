# Remove Apple sign-in and the Android home-screen widget — plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the non-functional Apple sign-in option and the Android
home-screen widget, keeping every other app behavior and all phone data intact.

**Architecture:** Two independent removals. The Apple removal deletes UI and
pins it with a regression test. The widget removal deletes the Flutter service
and MethodChannel, the native provider/manifest/resources, dead helpers and
tests, and launcher-widget copy; the shell keeps its class loading, Today
recount, and startup coach-tour trigger.

**Tech Stack:** Flutter/Dart, Android (Kotlin, AppWidget resources), sqflite
test FFI, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-26-remove-apple-and-widget-design.md`

## Global Constraints

- Real implementations only; no stub replacements.
- Preserve schedules, class statuses, events, accounts, and reminders.
- Full `flutter test` and `flutter analyze --no-fatal-infos` stay green.
- Never stage `.rnd`, `.taste-skill/`, `mockup_*.html`, or `profile_mockup.html`.
- No `dart format` on whole existing files.
- Commit Apple removal and widget removal separately; explicit paths only.

## Review Focus

- **Coach tour and Today count survive:** `_loadClassesForShell` must still
  assign `_classes`, call `_recountToday`, and arm `_maybeStartCoachTour`.
  `coach_tour_trigger_test` and `widget_test` pin this.
- **No hidden channel call:** `launcher_widget_removed_test` boots the real
  shell and asserts the `klasify/next_class_widget` channel gets zero calls.
- **No dangling Android resources:** no `@string/next_class_widget_*`,
  `widget_next_class*`, or `NextClassWidgetProvider` references remain.
- **No dead Dart:** `markedDateKeys`, widget help sheet, preview, and steps are
  gone; analyzer reports no unused imports.

---

### Task 1: Remove Apple sign-in

**Files:**
- Modify: `lib/screens/auth/login_screen.dart`
- Modify: `lib/screens/auth/signup_screen.dart`
- Create: `test/auth_social_options_test.dart`

- [x] Remove the "Continue with Apple" button and `_appleIcon()` from both
      screens.
- [x] Add a widget test asserting Google is present and Apple text/icon never
      render on either screen.
- [x] Run the auth suites: 8 tests green; analyzer clean.

### Task 2: Pin and remove the widget channel

**Files:**
- Create: `test/launcher_widget_removed_test.dart`
- Create: `lib/services/...` (delete `next_class_widget_service.dart`)
- Modify: `lib/screens/main_navigation_screen.dart`

- [x] Write the failing guard test (mock `klasify/next_class_widget`, boot the
      shell, expect zero calls); watch it fail.
- [x] Delete `NextClassWidgetService` and its import/use.
- [x] Rename `_syncWidgetSchedule` to `_loadClassesForShell`; drop
      `getClassStatuses` and the channel call; keep class load, recount, and
      coach-tour arming.
- [x] Re-run the guard test and shell/coach tests green.

### Task 3: Remove native widget code and resources

**Files:**
- Delete: `android/app/src/main/kotlin/com/klasify/app/NextClassWidgetProvider.kt`
- Delete: `android/app/src/main/kotlin/com/klasify/app/WidgetCalendarIds.kt`
- Delete: `android/app/src/main/res/layout/widget_next_class*.xml`
- Delete: `android/app/src/main/res/xml/next_class_widget_info.xml`
- Delete: `android/app/src/main/res/drawable/next_class_widget_*.xml`
- Delete: `android/app/src/main/res/values/strings.xml`,
  `values/dimens.xml`, `values-night/dimens.xml`
- Modify: `MainActivity.kt`, `AndroidManifest.xml`, `values/colors.xml`,
  `values-night/colors.xml`

- [x] Reduce `MainActivity` to a plain `FlutterActivity`.
- [x] Remove the widget receiver and its intent filters from the manifest.
- [x] Strip widget colors from both color files; delete widget-only dimens and
      strings; delete layouts/drawables/metadata.
- [x] Confirm no remaining `@string/` or widget resource references.

### Task 4: Remove dead Dart, copy, and tests

**Files:**
- Modify: `lib/models/class_status.dart`
- Modify: `test/class_status_test.dart`
- Modify: `lib/screens/profile/profile_sheets.dart`
- Modify: `lib/screens/onboarding_screen.dart`
- Modify: `test/app_look_capture_test.dart`, `test/coach_tour_trigger_test.dart`,
  `test/event_sheet_capture_test.dart`
- Delete: `test/goldens/mock_widget_states.png`

- [x] Remove `markedDateKeys` and its three tests.
- [x] Remove the widget help sheet, preview, and steps (unreferenced).
- [x] Rewrite About copy without the widget; update onboarding comments and
      Semantics to say "card", not "widget".
- [x] Remove launcher-widget MethodChannel stubs from capture/coach tests.

### Task 5: Update living docs and verify

**Files:**
- Modify: `README.md`, `docs/APP_WALKTHROUGH.md`, `FULL_APP_AUDIT.md`,
  `docs/RELEASE_CHECKLIST.md`, `pubspec.yaml`

- [x] Remove widget feature bullets, architecture entries, service/Android
      tables, flow annotations, defense notes, and store-review copy.
- [x] Update test counts to 84 test files / 609 tests and add the two new
      regression tests to the walkthrough table.
- [x] Run `flutter analyze --no-fatal-infos`: no issues.
- [x] Run full `flutter test`: 609 tests, 0 failures.
- [x] Commit Apple removal and widget removal separately; do not stage
      untracked mockups or design artifacts.
