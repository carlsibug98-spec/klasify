# Swipe Everywhere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the complete swipe-mockup behavior to the two class surfaces
that still lack it: the Home hero (`NextClassCard`) and the import review
draft rows (`ImportDraftCard`).

**Architecture:** Extend the existing `SwipeActions` widget minimally — a
`radius` parameter and conditional clipping so rest-state rendering (the
hero's ambient shadow) is untouched — then wrap the two surfaces. No gesture
constant changes; `deleteClassWithUndo` and `_deleteDraft` semantics stay.

**Tech Stack:** Flutter / Dart (Material 3).

**Spec:** `docs/superpowers/specs/2026-10-27-swipe-everywhere-design.md`

## Global Constraints
- No changes to the SwipeActions gesture contract (144 px plane, snap @0.5,
  full-swipe @1.15, fling -900 px/s, rubber band, haptics, reduced motion).
- Hero celebration/empty variants stay unwrapped.
- Import draft removal keeps its immediate-removal + notification semantics.
- All existing tests stay green; `flutter analyze` gains no new issues.

## Review Focus
1. Hero rest state must render identically (shadow intact, 28 px corners).
2. Deleting the hero shows the 5-second undo snackbar, and undo restores it.
3. Import rows collapse with their 5 px gap; the trash fallback still works.
4. Screen-reader: planes stay excluded from semantics until revealed.

---

### Task 1: SwipeActions `radius` + conditional clipping

**Files:**
- Modify: `lib/widgets/swipe_actions.dart`
- Test: `test/swipe_actions_test.dart`

- [ ] **Step 1: Failing tests** — (a) a `SwipeActions(radius: 28)` row does
  NOT clip its child's shadow at rest (row ClipRRect `clipBehavior` is none
  when closed); (b) default rows keep `AppTheme.cardRadius`.
- [ ] **Step 2: Implement** — add `radius` param; gate row + card clips on
  `_revealed`; fade plane with `reveal` + `IgnorePointer` when closed.
- [ ] **Step 3: Run** swipe_actions_test — all 15+ pass.

### Task 2: Home hero swipe

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Test: `test/home_screen_hero_test.dart`

- [ ] **Step 1: Failing tests** — full-swipe on the hero calls the delete
  path and shows the undo snackbar; plane Edit opens the class form;
  celebration hero has no swipe plane.
- [ ] **Step 2: Implement** — wrap the real-class branch in `SwipeActions`
  (radius 28, padding from the outer `Padding`), `onEdit` → class form,
  `onDelete` → `deleteClassWithUndo`.
- [ ] **Step 3: Run** home_screen_hero_test + widget_test — green.

### Task 3: Import review row swipe

**Files:**
- Modify: `lib/features/schedule_import/widgets/import_review_widgets.dart`
- Modify: `lib/features/schedule_import/import_schedule_screen.dart`
- Test: `test/import_review_edit_test.dart`

- [ ] **Step 1: Failing tests** — full-swipe on a draft row removes it and
  shows the notification; plane Edit opens the draft editor; trash button
  still removes.
- [ ] **Step 2: Implement** — wrap `ImportDraftCard` at the call site
  (margin → `SwipeActions.padding`), `onEdit` → `_edit`,
  `onDelete` → `_deleteDraft` reported as `Future.value(true)`.
- [ ] **Step 3: Run** import_review_edit_test + import_draft_test — green.

### Task 4: Full verification

- [ ] `flutter analyze` — no new issues.
- [ ] `flutter test` — full suite green (baseline 332 pass / 12 skip).
- [ ] Commit + worklog update.
