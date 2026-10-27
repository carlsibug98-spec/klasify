# Plan: stale feature-information pass (Task 20)

User report: "some the information about features of the app are not updated."
Scope: every surface that *describes* features — in-app copy, README,
FULL_APP_AUDIT.md, dead code that misrepresents the feature set. This is a
truthfulness pass, not a redesign; layout and design-locked surfaces stay
untouched.

## Findings inventory

| # | Surface | Stale claim | Reality (verified) |
|---|---------|-------------|--------------------|
| F1 | Coach tour step 1 (`coach_tour_overlay.dart:42-44`) | "Tap it for the room and details." | Hero card has no onTap (home_screen wires only onLongPress delete); room/time are printed on the card itself |
| F2 | Import picker footer (`import_schedule_screen.dart:1779-1785`) | "No internet connection is needed." — unconditional | False when the optional PaddleOCR-VL server URL is set: image scans try the server first (line 331 uses the live text) |
| F3 | Import picker "Works offline" chip (`:1652-1658`) | Always shown, static | Misleading when the server is configured |
| F4 | 20 MB error (`:318`) | "for reliable on-device processing" | With a server set, image bytes are uploaded; decode is local either way |
| F5 | `class_form_screen.dart` (534 lines) | Presented by README structure as the add/edit form | Dead code: router maps `/class-form` → `EditClassScreen`; zero references in lib/ or test/ |
| F6 | `home_screen.dart:329-331` | `next.isNow ? next.whenText : next.whenText` | Dead ternary, both branches identical (critique P3) |
| F7 | README line 14 | "Guided five-step coach tour" | Tour has 4 steps (hero, swipe, fab, nav) |
| F8 | README lines 3 / 58 / 64 / 179 | "does not use … a server", "No image or PDF is uploaded to a server." | Optional self-hosted server feature exists and ships in the UI |
| F9 | README structure listing (116-172) | Lists removed `class_details_sheet.dart`, dead `class_form_screen.dart`; missing ~30 current files (edit_class_screen, compose_colors, swipe_actions, day_status_sheet, app_info, import utils/services…) | |
| F10 | README line 197 | "OCR parsing is isolated in `lib/utils/timetable_parser.dart`" | Actual path: `lib/features/schedule_import/utils/timetable_parser.dart` |
| F11 | README §Full-app audit + FULL_APP_AUDIT.md | Presented as current | Capstone-era snapshot (2026-10-20) with stale mappings (class_form_screen, overflow menus) |
| F12 | README features list | No mention of optional scan server or Android predictive back (Task 18) | Both shipped |

Verified-accurate surfaces (no change): onboarding copy, About sheet copy
("Timetable, reminders, and the home-screen widget all work offline" — true),
pubspec description, README swipe/status-sheet/backup claims, editor weekday
chips, quick actions.

## Fixes

1. **F1** — step 1 body → 'This black card shows what's in progress or coming
   up, with the room and the time.' Regenerate `coach_tour_step1.png` (the only
   golden pinning this copy).
2. **F2** — footer becomes state-aware, same source of truth as the server
   card (`_vlUrlController.text.trim().isNotEmpty`, the value scans actually
   use at line 331):
   - off: 'Your timetable stays on your device. No internet connection is
     needed.' (unchanged)
   - on: 'Your timetable stays on your device. Image scans try your
     high-accuracy server first, then fall back to this device.'
3. **F3** — chip label: 'Works offline' (off) / 'Offline fallback' (on). Same
   icon, same container — copy-only.
4. **F4** — 'Choose a file smaller than 20 MB for reliable processing.'
5. **F5** — delete `lib/screens/class_form_screen.dart`.
6. **F6** — collapse to `whenText: next.whenText,` (keep the explanatory
   comment above it).
7. **F7** — 'Guided four-step coach tour'.
8. **F8** — README: nuance the four privacy claims (default on-device; optional
   self-hosted server sends image scans when configured; schedule data never
   leaves the device either way).
9. **F9** — rewrite the structure listing from the actual tree.
10. **F10** — fix the parser path.
11. **F11** — historical banner on FULL_APP_AUDIT.md + README note.
12. **F12** — add two feature bullets (optional self-hosted high-accuracy scan
    server; predictive back).

## Verification

- `flutter analyze` — expect ≤ 7 pre-existing infos, 0 new.
- Full suite — expect 344 pass / 12 skip / 0 fail; one golden regenerated
  (coach_tour_step1.png) via `--update-goldens` on design_capture_test only.
- `dart format` touched files.
- Commit + worklog Task 20 + keepsafe backup.

Out of scope (critique P2 direction decisions, untouched): server-card
relocation, compose-editor theme bridge, add-another loop, review-undo.
