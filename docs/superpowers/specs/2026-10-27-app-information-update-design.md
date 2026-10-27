# App information update — design

Date: 2026-10-27
Task: "Can you update everything about the information of the app"
Skills: using-superpowers (process), impeccable (craft floor: copy = the product's own
language), emil-design-eng (interaction polish), brainstorming (scope, gate lifted —
user opted out of question rounds; directive repeated from the queued instruction).

## Intent and why

Every surface a user reads should state true, current, consistent facts. The app's
feature set grew substantially (swipe-everywhere, coach tour, widget, About-less
settings), but several long-lived information surfaces were written before those
features landed and now describe an app that no longer exists. This pass audits every
information surface and brings the stale ones up to date — no visual redesign, no
feature work beyond the one missing information surface (version/about).

## Audit result (all surfaces)

Accurate, no change: onboarding pages 1–3 copy (design-locked, mock goldens),
FirstRunOptions tiles + example card, hero copy (celebration golden), coach tour steps,
coach hint, Settings rows, Reminders, Backup, import flow copy, class form, day-status
sheet, Android widget strings, app title (Klasify everywhere), rename remnants (none —
single intentional doc comment in schedule_backup_codec.dart).

Stale or missing:

1. **pubspec.yaml description** — "with schedule and room search" describes a feature
   that does not exist (there is no room search).
2. **README.md** — (a) says onboarding has 4 pages, the app has 3 (two places);
   (b) documents a "class details bottom sheet" that was replaced by swipe actions +
   the status sheet; (c) tells users to find "Import a timetable" in Settings — the row
   is "Import schedule" (consistent in quick action + app bar); (d) claims a "Resume
   import" quick-action label — the label stays "Import schedule", the resume behavior
   is automatic (openOrResumeImport); (e) the feature list omits the swipe-gesture
   system and the coach tour entirely.
3. **Version/about information missing entirely** — no screen shows the app version.
4. **Empty-state voice split** — Today's empty card says "Enjoy the open space.",
   Week's says "Enjoy your open space." Same situation, two voices. The app copy is
   second-person ("Your timetable", "your phone", "Enjoy your break"), so "your" wins.
   (Mockups contain neither phrase; hero celebration copy is design-locked and stays.)

## Goals / non-goals / anti-goals

- Goals: factual accuracy on every surface; one voice for the same situation; the
  version reachable from Settings; README matches the shipped app.
- Non-goals: rewriting design-locked onboarding/hero copy; renaming "Import schedule"
  (destination) vs "Import a timetable" (action button) — destination vs action naming
  is deliberate and internally consistent; visual changes.
- Anti-goals: marketing fluff in place of facts; adding surfaces that duplicate info
  the hero/lists already show.

## Approach

Considered: (a) copy-only pass, no new surfaces — leaves version undiscoverable;
(b) copy pass + version footer text in Settings — cheapest, but no about context and
no licenses entry; (c) copy pass + an About group in Settings that opens the app's own
quiet bottom sheet (logo, name, version, the local-first statement, licenses entry).
**Chosen: (c)** — it completes the information surface set using existing idioms
(SettingsRow group + the day-status sheet pattern: showModalBottomSheet, useSafeArea,
sheetRadius 28), carries the local-first promise (the app's defining fact), and keeps
licenses one tap away without a new dependency (showLicensePage).

Version lives in one place in code (`lib/services/app_info.dart`, const) with a
drift-guard test that parses pubspec.yaml and fails if the two disagree — no
package_info_plus dependency, no build recipe change (disk-constrained sandbox).

## Parts decided

- Today empty card message → "Enjoy your open space." (Week already matches).
- About group sits under its own "About" section header, last group on Settings:
  icon info_outline_rounded, title "About Klasify", subtitle the version label
  ("Version 1.3.3 (build 8)"), chevron; tap opens the sheet.
- Sheet content: logo (36px, assets/klasify_logo.png), "Klasify" title, version line,
  tagline "Your schedule stays on this device.", divider, a row "Open-source licenses"
  → showLicensePage (applicationName Klasify, version, icon, legalese = tagline).
- README/pubspec rewritten to match audited reality (swipe system, 5-second undo,
  coach tour once after the first class, 3 onboarding pages, real labels).

## What's left to the builder

- Exact README wording within the audited facts; test placement (new
  test/app_info_test.dart: pubspec drift guard + About row opens sheet + sheet content
  + licenses entry present); keep `flutter analyze` at the 7 pre-existing infos and the
  suite at 0 failures; no golden changes expected (empty states are not captured).
