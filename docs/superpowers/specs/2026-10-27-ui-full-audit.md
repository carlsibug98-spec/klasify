# Klasify full UI audit — 2026-10-27

Audit playbook: impeccable `audit` (native variant), scored against `reference/android.md`.
Craft lens: emil-design-eng (motion values, press feedback, interruptibility).
Process: using-superpowers (verification before claims; evidence over assumption).

Scope: every user-facing surface — onboarding (3 pages), Home (hero, Today list,
first-run, empty states), Week (strip, agenda, break dividers), Settings (+ About),
Reminders, Backup, Import (picker, scan progress, review), Edit class (compose mode),
class form, day-status sheet, time pickers, coach tour, notifications, home-screen
widget. 61 Dart files, ~13,000 lines. Evidence: source read end-to-end,
`flutter analyze` (7 pre-existing infos, 0 new), full suite **344 pass / 12 skip /
0 fail**, WCAG contrast math on 25 color pairs, AndroidManifest + launch-theme review.

---

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility | 3 | Editor hint text 3.29:1 (AA fail); reminder switch target 48×28 |
| 2 | Performance | 3 | Import review list builds all rows + swipe controllers eagerly |
| 3 | Appearance & Theming | 3 | Dark "compose" palette hand-copied in 3 files, drifting (#85B7EB stray) |
| 4 | Platform Conformance | 3 | Predictive back not opted in (`enableOnBackInvokedCallback` absent) |
| 5 | Adaptivity | 3 | Custom nav bar fixed at 56px overflows at Android max font scale (2.0) |
| **Total** | | **15/20** | **Good — address weak dimensions** |

## Platform Conformance Verdict

**Pass, with one gap.** This reads as a native Android app, not a ported website:
Material 3 is the rulebook — FAB (56dp, tooltip, rotating icon), snackbars with
actions and severity durations, bottom sheets with drag handles, Material dialogs,
M3 switches/chips, NavigationRail on expanded width with content max-width 1100.
System Back is never trapped: onboarding back steps pages progressively, the editor
guards unsaved changes via PopScope confirm, import guards an in-flight scan. Insets
are handled with SafeArea + `media.padding.bottom` in every sheet; status-bar icon
contrast is set per-surface with AnnotatedRegion (including the always-black editor).
The one gap: **Android 13+ predictive back is not enabled** — the manifest lacks
`android:enableOnBackInvokedCallback="true"`, so back works but shows no peek.
The custom pill bottom-nav (instead of M3 NavigationBar) is a deliberate, coherent
brand pattern — 3 destinations, labels always visible, 56dp rows — and stays within
Material structure; not a violation. Dynamic Color is unused, which is a legitimate
choice for the strict black/white identity (static scheme is the documented fallback).

## Executive Summary

- Audit Health Score: **15/20** (Good — address weak dimensions)
- Issues: **P0: 0 · P1: 1 · P2: 5 · P3: 2**
- Top issues:
  1. **[P1]** Editor hint text `#707070` on `#1F1F1F` = **3.29:1** — fails WCAG AA (4.5:1) for 16px text (`edit_class_screen.dart:1082`).
  2. **[P2]** Predictive back not opted in on Android 13+ (manifest flag absent).
  3. **[P2]** Import review list is a `for` loop inside a non-builder `ListView` — every draft row and its `SwipeActions` animation controllers build eagerly (~30–60 complex rows typical).
  4. **[P2]** Custom reminder switch is 48×28 — visual size kept, but the tap target is 28dp tall vs the 48dp Material minimum (WCAG 2.5.8's 24px floor is met).
  5. **[P2]** Bottom nav rows are a fixed `SizedBox(height: 56)`; at Android's 200% font scale the icon+label column needs ≈56.4px → RenderFlex overflow.
- Recommended next step: run the fixes below (all small), then re-run this audit — score should reach 18–19/20.

## Detailed Findings by Severity

### [P1] Editor hint contrast fails WCAG AA
- **Location**: `lib/screens/edit_class_screen.dart:1082` — `hintStyle: TextStyle(color: _EditorColors.outline /* #707070 */, fontSize: 16)` on field fill `#1F1F1F`.
- **Category**: Accessibility · **Guideline**: WCAG 2.1 SC 1.4.3 (4.5:1 for normal text); measured 3.29:1 (3.72:1 on the `#141414` card).
- **Impact**: placeholder hints are illegible in low light / bright sunlight for low-vision users — the editor is where users type the most.
- **Recommendation**: use the palette's `muted #A3A3A3` (6.53:1 ✓) or add a dedicated `hint` token ≈ `#8F8F8F`.
- **Suggested command**: `/impeccable harden`

### [P2] Predictive back not enabled (Android 13+)
- **Location**: `android/app/src/main/AndroidManifest.xml` — no `android:enableOnBackInvokedCallback="true"` on `<application>`.
- **Category**: Platform Conformance · **Guideline**: android.md "Honor the predictive Back gesture".
- **Impact**: back navigation works but without the Android 13+ peek animation; on Android 15+ targeting the app increasingly reads as legacy.
- **Recommendation**: add the flag; PopScope usage is already correct (progressive onboarding, discard confirms), so behavior should opt in cleanly — verify the in-scan cancel path still intercepts as intended.
- **Suggested command**: `/impeccable harden`

### [P2] Import review list is not virtualized
- **Location**: `lib/features/schedule_import/import_schedule_screen.dart:1104` — `for (var i = 0; i < _drafts.length; i++) SwipeActions(... ImportDraftCard(...))` inside `ListView(children: ...)` (line 991).
- **Category**: Performance
- **Impact**: a 40–60 class OCR import builds every card plus a `TickerProviderStateMixin` swipe controller per row before the first frame; slower review-screen entry and extra memory on low-end devices.
- **Recommendation**: split the review section into its own `ListView.builder` (or convert the body to CustomScrollView slivers, matching WeekAgendaView's `SliverChildBuilderDelegate` pattern).
- **Suggested command**: `/impeccable optimize`

### [P2] Reminder switch tap target is 48×28
- **Location**: `lib/screens/reminders_screen.dart:434` (`_ReminderToggle`) — visual 48×28, InkWell wraps only the SizedBox.
- **Category**: Accessibility / Platform Conformance · **Guideline**: android.md 48×48 dp minimum touch targets (WCAG SC 2.5.8's 24px floor is met).
- **Impact**: harder to hit accurately; Semantics(onTap) keeps it operable for TalkBack, and the comment shows the size is a deliberate mockup fidelity choice — but fidelity shouldn't cost the target.
- **Recommendation**: keep the 48×28 visual, pad the hit area to ≥48×48 (`SizedBox(height: 48)` + `Center`, or `ButtonStyle` tap-target padding). Same pattern Material's own Switch uses (60×48 target, 52×32 visual).
- **Suggested command**: `/impeccable polish`

### [P2] Bottom nav row overflows at 200% font scale
- **Location**: `lib/widgets/bottom_navigation_item.dart:39` — `SizedBox(height: 56)` around icon (28) + gap (2) + label.
- **Category**: Adaptivity · **Guideline**: android.md "sp units, never fixed px, so type follows the system font-size setting" (text scales; the fixed container doesn't).
- **Impact**: at Android's maximum font scale (2.0) the label needs ≈26.4px → total ≈56.4px → RenderFlex overflow (clipped label in release). At 1.3× it fits (verified by arithmetic).
- **Recommendation**: let the row grow (`IntrinsicHeight`/min-height pattern) or cap the label's scale in the nav only (`textScaler: TextScaler.linear(1.0)` is acceptable here — the full label already exists in Semantics).
- **Suggested command**: `/impeccable adapt` (verify at `adb shell settings put system font_scale 2.0`)

### [P2] Dark "compose" palette duplicated in three files, drifting
- **Location**: `edit_class_screen.dart:1104` (`_EditorColors`), `import_review_widgets.dart` (23 raw hex), `edit_class_time_picker_sheet.dart` (10 raw hex).
- **Category**: Theming
- **Impact**: same-look surfaces drift silently — `#2A2A2A` vs `#2C2C2C` fields, and a stray off-brand blue `#85B7EB` accent in the time picker sheet. Three places to fix the P1 hint color.
- **Recommendation**: lift one `EditorColors`/token set (or theme extension) and import it in all three; decide once whether the import cancel sheet (`_AndroidCancelConfirmationSheet`, always-dark) matches its adapting parent screen — today it stays dark in light mode.
- **Suggested command**: `/impeccable extract`

### [P3] APK weight: 94MB arm64
- **Location**: release build (libonnxruntime 17.9MB, libopencv_java4 24MB, libapp 8.3MB, libflutter 11.8MB).
- **Category**: Performance
- **Impact**: on-device OCR is the product promise, so the weight is bought deliberately; still a large download for a timetable app.
- **Recommendation**: when convenient, evaluate opencv module trimming (usually only a subset is used) — not urgent.
- **Suggested command**: `/impeccable optimize`

### [P3] Nav label is 11px / below M3 nav label scale
- **Location**: `bottom_navigation_item.dart:127` — `fontSize: 11` vs M3 NavigationBar label 12.
- **Category**: Typography (Material type scale)
- **Impact**: tiny legibility cost; ellipsis already handles long labels.
- **Recommendation**: bump to 12 with the existing weight system, or accept as deliberate density.
- **Suggested command**: `/impeccable typeset`

## Patterns & Systemic Issues

- **Dark-surface palette is copied, not tokenized** (3 files) — the single systemic theming gap; everything else resolves through `Theme.of(context)`.
- **Everything else is tokenized**: raw `Colors.*` outside the intentional dark surfaces is essentially absent; motion durations/curves and layout radii/gaps all come from `AppTheme` constants.
- **No systemic a11y gap**: semantics are pervasive and *composed* (not boilerplate); every gesture has a non-gesture fallback. The findings are three local misses, not a pattern.

## Positive Findings (maintain and replicate)

- **Motion system is textbook emil-design-eng**: tokenized 120/180/220ms (all under the 300ms ceiling), custom `cubic-bezier(0.23,1,0.32,1)` ease-out and `(0.77,0,0.175,1)` ease-in-out — the exact curves the philosophy recommends; enter-only transitions everywhere (no crossfade ghosting, rapid taps restart a short enter instead of queueing); `PressableScale` 0.98/120ms using `Listener` deliberately outside the gesture arena; `LivePulse` is the *only* pulsing element, transform+opacity only, sine-seamed loop; swipe plane is transform-driven with a single layout collapse, rubber-band, viewport-relative fly-off for tablets.
- **Reduced motion is honored everywhere with information preserved**: durations collapse to zero via `AppTheme.motionDuration`; the undo snackbar *keeps* the message and action and drops only the ticking bar; press feedback goes inert; parallax disables.
- **Semantics quality is genuinely high**: weekday tiles announce full date + class count; class cards compose subject, time, room, professor, live/done/next state and mark duration into one label; nav items announce selected state with deduped labels; decorative ghost numerals are excluded.
- **Every swipe action has a discoverable fallback**: ⋮ menu on cards, trash icon on import rows, long-press delete, coach tour + one-time hint that retires itself.
- **State coverage is complete**: skeleton/spinner loading, non-destructive error copy with retry ("Your saved data wasn't changed"), two empty-state tiers (no schedule yet vs free day) with actions, first-run options, coach tour.
- **Snackbar craft**: severity-based durations (3/5/6s), live countdown + progress for actions, acting dismisses, `replaceCurrent` snaps instead of queueing, root messenger so Undo survives route changes, swipe-down dismiss.
- **Robustness details**: version-guarded asyncs (race protection), minute-aligned timers (not periodic), DST-safe week math, double-tap save guard, unsaved-changes PopScope, armed two-tap delete, tabular figures on all times, widget sync versioning.
- **Responsive foundations**: NavigationRail ≥600dp + 1100px content cap; week strip and day chips switch Expanded-row ↔ 48dp-scroll; launch theme has night variants; `adjustResize` + SafeArea everywhere; `configChanges` handles rotation/uiMode/fontScale without recreation.
- **Verification culture**: 344 tests green, 13 golden images, analyze clean at baseline, design decisions documented in code comments ("why", not just "what").

## Recommended Actions

1. **[P1] `/impeccable harden`** — fix the editor hint color (3.29:1 → ≥4.5:1); while in there, add the predictive-back manifest flag and re-verify PopScope interception paths.
2. **[P2] `/impeccable extract`** — lift the duplicated dark palette into one token set consumed by editor, import review, and time picker; decide the cancel sheet's theme behavior; kill the stray `#85B7EB`.
3. **[P2] `/impeccable optimize`** — virtualize the import review list (builder delegate, WeekAgendaView pattern).
4. **[P2] `/impeccable adapt`** — 48dp tap target for the reminder switch; nav row height that survives font_scale 2.0; capture evidence on a phone + one tablet per android.md (dark mode + 1.3 font scale included).
5. **[P3] `/impeccable polish`** — final pass: nav label 11→12px, time-picker sheet accent alignment.

> You can ask me to run these one at a time, all at once, or in any order you prefer.
>
> Re-run `/impeccable audit` after fixes to see your score improve (expected: 18–19/20).

Suggestion (non-blocking, from the impeccable context loader): this project has no
PRODUCT.md yet — `/impeccable init` would capture the product context once and make
future design passes faster.
