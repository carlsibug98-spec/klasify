# Remove Apple sign-in and the Android home-screen widget — design

Date: 2026-11-26
Status: implemented (2026-11-26)
Related: `docs/superpowers/specs/2026-11-20-account-scoped-cache-design.md`

## Problem

Two user-facing surfaces no longer match the product:

- Both auth screens offer "Continue with Apple", but the backend has no Apple
  token exchange, so the button cannot complete a real sign-in.
- The Android home-screen widget ("Upcoming") duplicates the in-app Today
  hero, adds a MethodChannel + native AppWidgetProvider + two RemoteViews
  layouts + 22 drawables to maintain, and forces the shell to load class
  statuses on every database change just to render a launcher surface.

The project rule is real implementations only; an auth button that cannot
authenticate and a launcher surface that mostly mirrors the app are both
maintenance cost without product value.

## Intent

Remove both surfaces completely, in two independent commits, without changing
any other app behavior or touching user data.

## Decisions

### Apple sign-in

- Delete the Apple button and its `_appleIcon()` helper from `LoginScreen` and
  `SignupScreen`. Google sign-in and email/password stay unchanged.
- Add `test/auth_social_options_test.dart`: both screens must show
  "Continue with Google" and must never show "Continue with Apple" or
  `Icons.apple`.

### Android home-screen widget

- Delete the Flutter side (`NextClassWidgetService`, its MethodChannel use) and
  the native side (`NextClassWidgetProvider`, `WidgetCalendarIds`, manifest
  receiver, widget layouts/metadata/drawables/dimens/strings, widget colors).
- Rename the shell's `_syncWidgetSchedule` to `_loadClassesForShell` and keep
  its real responsibilities: loading `_classes`, recounting Today, and arming
  the one-time startup coach tour. Drop the statuses read and the channel call.
- Remove the now-unused `markedDateKeys` helper and its three tests.
- Delete the unreferenced widget help sheet (`showProfileWidgetHelpSheet`,
  `ProfileWidgetHelpSheet`, `_WidgetPreview`, `_WidgetStep`) and remove
  launcher-widget wording from About, onboarding comments/Semantics, the
  pubspec description, README, and living docs.
- Add `test/launcher_widget_removed_test.dart`: mock
  `klasify/next_class_widget`, boot the real shell, assert zero calls. The
  test failed before the removal and pins the channel against reintroduction.
- Remove the orphaned `test/goldens/mock_widget_states.png`; no test reads it.

## Non-goals

- Historical audits (`docs/APP_AUDIT_2026-10-31.md`), design HTML, superpowers
  plans, and release APKs keep their original widget references.
- No schema change, no backend change, no data migration. Existing schedules,
  statuses, events, and accounts are untouched.
- No new widget replacement and no Apple backend work.

## Verification

- `flutter analyze --no-fatal-infos`: clean.
- Full `flutter test`: 84 test files, 609 tests, 0 failures (2026-11-26).
- Grep for `next_class_widget`, `NextClassWidgetService`, and Apple sign-in in
  `lib/`, `test/`, and `android/` returns nothing outside the removal guard.
- Android release build was **not** rerun in this session; resource deletions
  have no remaining references (`@string/`, layouts, drawables, ids).
