# UI audit fixes — all at once (2026-10-27)

Source: `docs/superpowers/specs/2026-10-27-ui-full-audit.md` (score 15/20).
User picked "all at once". Baseline: clean tree @ 2033fec, 344 pass / 12 skip / 0 fail.

Skills: impeccable (`harden` / `extract` / `optimize` / `adapt` / `polish` sequence,
craft-floor loaded), emil-design-eng (tokenized motion, no visual regressions),
using-superpowers (verify each step, evidence over assumption).

## Fix matrix

| # | Finding | Fix | Files | Visual delta |
|---|---------|-----|-------|--------------|
| 1 | [P1] Editor hint `#707070` = 3.29:1 (AA fail) | New shared `hint #8F8F8F` token (5.10:1 on field, 5.70:1 on card) | compose_colors.dart (new), edit_class_screen.dart, edit_class_time_picker_sheet.dart | Hints/wheel values slightly brighter |
| 2 | [P2] Dark compose palette copied in 3 files, drifting (#2A2A2A/#2C2C2C, stray #85B7EB, #3A1C1C vs #3A1D1D) | One `ComposeColors` token set in `lib/theme/compose_colors.dart`; all three files consume it; stray blue → white (editor's own affirmation color); 1-bit error-container drift unified | same 3 files | Time-picker Done now white |
| 3 | [P2] Import scan dark branches leak into light mode (white spinner, dark progress track, dark file tile hardcoded over adaptive card) | Compute from `isDark` like their siblings | import_review_widgets.dart | Light-mode scan card correct |
| 4 | [P2] Cancel-scan sheet always-dark over an adaptive screen (audit: "decide once") | Decide: adapt, like every other sheet in the app. Dark branch = today's tokens; light branch = scheme roles (surfaceContainer bg, surfaceContainerHigh chips, scheme.error confirm) | import_review_widgets.dart | Light-mode sheet now matches screen |
| 5 | [P2] Import review list builds every draft row eagerly | `ListView(children:)` → `CustomScrollView` + `SliverList.builder` for drafts (WeekAgendaView pattern); static sections become `SliverToBoxAdapter`s | import_schedule_screen.dart | None |
| 6 | [P2] Reminder switch target 48×28 | Visual stays 48×28; InkWell box becomes 48×48 (Material's own Switch pattern: 60×48 target / 52×32 visual) | reminders_screen.dart | Row grows ~10px → regenerate reminders.png |
| 7 | [P2] Nav row fixed 56px overflows at fontScale 2.0 | `SizedBox(height:56)` → min-height 56 that grows with content (pixel-identical at 1.0) | bottom_navigation_item.dart | None at default scale |
| 8 | [P3] Nav label 11px vs M3 12 | Bump to 12 | bottom_navigation_item.dart | Labels +1px |
| 9 | [P2] Predictive back not opted in | `android:enableOnBackInvokedCallback="true"`; PopScope paths already correct (audit verdict) | AndroidManifest.xml | Android 13+ back peek |

Deliberately NOT in scope: APK weight (P3, deliberate OCR stack — opencv trimming is a
build-engineering project, not UI); hero/onboarding/coach hexes (design-locked,
golden-covered); `AppTheme` scheme definitions (that IS the token source).

## Verification per step

1. New token file + editor/time-picker/import swaps → `flutter analyze` 0 new,
   targeted tests (edit_class_screen_test, import tests).
2. Contrast math re-run as a script (`scripts/verify_contrast.py`): every text token
   on its backgrounds ≥ 4.5:1, printed as evidence.
3. Sliver conversion → import_review_edit_test + import flow tests must stay green
   (rows are near the top of the test viewport; lazy building cannot hide them).
4. Reminder toggle → regenerate `reminders.png` via `--update-goldens`, restore any
   byte-diffed-but-visually-identical goldens from git.
5. Nav → widget_test nav finds + `takeException()` guards; arithmetic check at 2.0.
6. Full suite at the end: target 344+ pass / 0 fail / 0 new analyze infos.
7. Commit, worklog, `keepsafe_backup.sh ui-audit`.
