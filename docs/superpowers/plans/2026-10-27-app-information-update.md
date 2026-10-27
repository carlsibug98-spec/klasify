# Plan: App information update

Spec: `docs/superpowers/specs/2026-10-27-app-information-update-design.md`
Verification baseline: analyze clean (7 pre-existing infos), 342 pass / 12 skip / 0 fail.
Skills: impeccable craft-floor (copy = product's own language), emil-design-eng
(interruptible, quiet surfaces; no motion changes needed), TDD for the new About surface.

## Task 1 — Version constant + drift guard (TDD)

RED: `test/app_info_test.dart` — parse `pubspec.yaml` `version:` → expect
`AppInfo.version == '1.3.3'`, `AppInfo.build == 8`, label "Version 1.3.3 (build 8)".
(Compile fails first: no AppInfo yet.)

GREEN: `lib/services/app_info.dart` — const-only class: name, version, build,
`versionLabel` getter, `tagline` ('Your schedule stays on this device.'), keep-in-sync
doc comment.

## Task 2 — Settings About group + about sheet (TDD)

RED (same test file): pump SettingsScreen → 'About Klasify' row visible with version
subtitle; tap → sheet shows logo Semantics/name 'Klasify', version label, tagline,
'Open-source licenses' entry. (Also asserts the group header 'About'.)

GREEN: settings_screen.dart — third `_SettingsGroup` ("About") with one
`_SettingsRowData` (info_outline_rounded icon, route sentinel handled in-group: onTap
opens `_showAboutSheet`); sheet follows the day-status sheet idiom (showModalBottomSheet,
useSafeArea, sheetRadius, safe-area padding), content per spec; licenses row →
showLicensePage(applicationName: AppInfo.name, applicationVersion: AppInfo.version,
applicationIcon: AssetImage logo, applicationLegalese: AppInfo.tagline).

## Task 3 — Empty-state voice unification

`lib/screens/home_screen.dart` `_TodayEmptyState`: 'Enjoy the open space.' →
'Enjoy your open space.' (Week already uses the latter; no test pins the old string;
no golden captures empty states.)

## Task 4 — pubspec + README factual pass

- pubspec.yaml description → "A local-first weekly class timetable with offline OCR
  import, class reminders, and an Android home-screen widget."
- README.md:
  - Features: replace the stale "class details bottom sheet" bullet with the real
    interaction model (tap = status sheet; swipe left = Edit/Delete planes,
    full-swipe delete with 5-second undo — Today rows, hero, Week agenda, import
    review rows); add coach tour bullet (five steps, once, after the first class);
    add About bullet.
  - Onboarding: 4 pages → 3 pages (feature bullet + UI design bullet).
  - Import section step 1: Settings row is "Import schedule"; empty Today screen
    offers "Scan it" / "Add by hand" tiles; resume is automatic when a draft exists
    (label unchanged).
  - UI design section: fix the Class details bullet → status sheet + swipe actions;
    Settings bullet mentions the About group; onboarding count.

## Task 5 — Verify

`flutter analyze` (expect only the 7 pre-existing infos) + `flutter test` full suite
(expect ≥ 342 pass + new tests, 0 fail). dart format touched files. No goldens touched.

## Task 6 — Ship

Commit (spec + plan + code + tests), run `bash /home/z/my-project/scripts/keepsafe_backup.sh v54-app-info`,
append worklog Task 15.
