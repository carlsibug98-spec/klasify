# Klasify UI & Interaction Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul Klasify UI by removing container cards on empty states/reminders, fixing scanning progress and alignment, replacing delete undo with confirmation dialogs, removing design outlines, standardizing CTAs to "Import schedule", and refining card swipe interactions.

**Architecture:** Update UI components and screens using targeted refinements following Ponytail principles (minimal code diffs, no unnecessary abstractions). Replace undo snackbar triggers with modal delete confirmation; make action planes visible only during active swipe; standardize CTA strings across navigation, settings, and cards.

**Tech Stack:** Flutter / Dart (Material 3).

**Spec:** `docs/superpowers/specs/2026-10-26-ui-improvements-design.md`

## Global Constraints
- Remove border outlines across all designs (`BorderSide.none`, borderless buttons/cards).
- Standardize all user-facing import CTAs from "Import timetable" to "Import schedule".
- Preserve screen reader semantics: when visual 3-dot menus are removed, add `CustomSemanticsAction` to card semantics nodes.
- Maintain tests passing and backward compatibility of core schedule models.

## Review Focus
1. When upcoming class is days away (e.g. 2 days), NextClassCard displays relative "Starts in 2d Xh Ym" without layout overflow.
2. When a class is marked done/missed (opacity 0.5), background Edit/Delete buttons are completely invisible until dragged.
3. When deleting a class via swipe or long-press, cancelling the dialog leaves the class card closed in place without deletion.
4. When performing an image scan with rotated passes, the progress bar stays under 40% while in "detecting grid" stage.
5. On smaller phone viewports, the "Tap to confirm" label on `EditClassScreen` delete action is fully visible and centered without wrapping.

---

### Task 1: Global Outline Removal and Theme Cleanup

**Files:**
- Modify: `lib/theme/app_theme.dart:450-455`
- Modify: `lib/widgets/pinned_action_bar.dart:28-35`
- Test: `test/component_kit_test.dart`

**Interfaces:**
- Consumes: `AppTheme.theme`
- Produces: Borderless button and container theme definitions (`BorderSide.none`)

- [ ] **Step 1: Write/update the failing test for borderless theme**
In `test/component_kit_test.dart`, assert that `OutlinedButton` theme has `BorderSide.none` and `PinnedActionBar` does not render a visible border line:
```dart
testWidgets('OutlinedButton theme has no border outline', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: OutlinedButton(onPressed: () {}, child: const Text('Test')),
      ),
    ),
  );
  final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
  final side = button.style?.side?.resolve({}) ?? AppTheme.theme.outlinedButtonTheme.style?.side?.resolve({});
  expect(side?.style, equals(BorderStyle.none));
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/component_kit_test.dart`
Expected: FAIL (border side currently has width 1.5)

- [ ] **Step 3: Remove outlines in `app_theme.dart` and `pinned_action_bar.dart`**
In `lib/theme/app_theme.dart`, set `outlinedButtonTheme` style side to `BorderSide.none`. In `lib/widgets/pinned_action_bar.dart`, remove the top border `BorderSide` from the decoration.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/component_kit_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/theme/app_theme.dart lib/widgets/pinned_action_bar.dart test/component_kit_test.dart
git commit -m "style: remove outlines from button themes and action bars"
```

---

### Task 2: Standardize CTA Copy to "Import schedule"

**Files:**
- Modify: `lib/screens/main_navigation_screen.dart:242`
- Modify: `lib/screens/settings_screen.dart:58-62`
- Modify: `lib/features/schedule_import/import_schedule_screen.dart:968-971`
- Modify: `lib/widgets/next_class_card.dart:66-70`
- Modify: `lib/widgets/week_agenda_view.dart:188-192`
- Test: `test/home_screen_hero_test.dart`, `test/settings_screen_test.dart`

**Interfaces:**
- Consumes: App route strings
- Produces: Updated UI copy ("Import schedule" replacing "Import timetable" and "Import a timetable")

- [ ] **Step 1: Write/update tests for "Import schedule" copy**
In `test/settings_screen_test.dart`, verify that the settings screen shows 'Import schedule' instead of 'Import a timetable'.

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/settings_screen_test.dart`
Expected: FAIL with "Import a timetable" found instead of "Import schedule"

- [ ] **Step 3: Update copy in the navigation, settings, import, and empty cards**
Update:
- `lib/screens/main_navigation_screen.dart`: `importLabel: 'Import schedule'`
- `lib/screens/settings_screen.dart`: `title: 'Import schedule'`
- `lib/features/schedule_import/import_schedule_screen.dart`: `title: Text(reviewing ? 'Review import' : 'Import schedule')`
- `lib/widgets/next_class_card.dart`: `subject = 'Add a class or import a schedule to begin.'`

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/settings_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/screens/main_navigation_screen.dart lib/screens/settings_screen.dart lib/features/schedule_import/import_schedule_screen.dart lib/widgets/next_class_card.dart test/settings_screen_test.dart
git commit -m "refactor: standardize CTA copy from import timetable to import schedule"
```

---

### Task 3: Today Screen Empty State & Hero Relative Countdown

**Files:**
- Modify: `lib/widgets/first_run_options.dart:1-224`
- Modify: `lib/screens/home_screen.dart:315-325`
- Test: `test/first_run_options_test.dart`, `test/home_screen_hero_test.dart`

**Interfaces:**
- Consumes: `FirstRunOptions(onScan: ..., onAdd: ...)`
- Produces: Borderless, container-free option tiles without example data structures; hero card showing `Starts in ...`

- [ ] **Step 1: Write failing tests for cardless FirstRunOptions and relative hero whenText**
Add test in `test/first_run_options_test.dart` verifying that `FirstRunOptions` does not contain 'Data Structures' and has no outer card decoration, and test in `test/home_screen_hero_test.dart` that hero card shows relative start time (e.g. `Starts in 2h 15m`):
```dart
testWidgets('FirstRunOptions does not show Data Structures example card', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FirstRunOptions(onScan: () {}, onAdd: () {}),
      ),
    ),
  );
  expect(find.text('Data Structures'), findsNothing);
  expect(find.text('Scan it'), findsOneWidget);
  expect(find.text('Add by hand'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/first_run_options_test.dart`
Expected: FAIL ('Data Structures' found)

- [ ] **Step 3: Implement changes in `first_run_options.dart` and `home_screen.dart`**
- In `first_run_options.dart`: Remove outer container with `scheme.surfaceContainer`, remove `showExample` and the `Data Structures` card block (lines 71-120).
- In `home_screen.dart` line 321: Use `next.whenText` instead of `'Starts ${formatMinutes(next.item.startMinutes)}'`.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/first_run_options_test.dart test/home_screen_hero_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/widgets/first_run_options.dart lib/screens/home_screen.dart test/first_run_options_test.dart test/home_screen_hero_test.dart
git commit -m "feat: remove card and example from first run options and use relative time in hero"
```

---

### Task 4: Weekly Schedule Empty State

**Files:**
- Modify: `lib/widgets/week_agenda_view.dart:170-200`
- Test: `test/weekly_schedule_view_test.dart`

**Interfaces:**
- Consumes: `FirstRunOptions`
- Produces: Cardless "Scan it" and "Add by hand" options when schedule is empty

- [ ] **Step 1: Write failing test in `test/weekly_schedule_view_test.dart`**
Verify that when `allClassesEmpty: true`, the week view shows "Scan it" and "Add by hand" instead of "Import a timetable" and without an `EmptyStateCard`:
```dart
testWidgets('WeekAgendaView displays Scan it and Add by hand when all classes empty', (tester) async {
  await tester.pumpWidget(...);
  expect(find.text('Scan it'), findsOneWidget);
  expect(find.text('Add by hand'), findsOneWidget);
  expect(find.text('Import a timetable'), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/weekly_schedule_view_test.dart`
Expected: FAIL

- [ ] **Step 3: Replace `EmptyStateCard` with `FirstRunOptions` in `week_agenda_view.dart`**
In `week_agenda_view.dart`, when `allClassesEmpty` is true, render `FirstRunOptions` with `onScan` triggering `AppRoutes.importSchedule` and `onAdd` triggering `onAddClassForDay(selectedDay)`.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/weekly_schedule_view_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/widgets/week_agenda_view.dart test/weekly_schedule_view_test.dart
git commit -m "feat: use cardless scan it and add by hand in weekly schedule empty state"
```

---

### Task 5: Class Reminders Cleanup & Resizing

**Files:**
- Modify: `lib/screens/reminders_screen.dart:212-412`
- Test: `test/reminders_screen_test.dart`

**Interfaces:**
- Consumes: `ReminderService.instance`
- Produces: Resized, borderless "Remind me before class" widget without outer container and without "Back up your schedule"

- [ ] **Step 1: Write failing test in `test/reminders_screen_test.dart`**
Assert that "Back up your schedule" is not displayed and reminder panel does not wrap in outer container card:
```dart
testWidgets('RemindersScreen does not show Back up your schedule', (tester) async {
  await tester.pumpWidget(...);
  expect(find.text('Back up your schedule'), findsNothing);
  expect(find.text('Remind me before class'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/reminders_screen_test.dart`
Expected: FAIL ("Back up your schedule" found)

- [ ] **Step 3: Remove backup card and outer container in `reminders_screen.dart`**
- Delete lines 356-407 ("Back up your schedule" `Material` card).
- In `_ReminderPanel`, remove outer `Container(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(24))`.
- Resize `_ReminderCard` padding and layout so the switch and chips have clean, balanced proportions without borders.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/reminders_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/screens/reminders_screen.dart test/reminders_screen_test.dart
git commit -m "feat: remove backup card and resize reminders widget without outer container"
```

---

### Task 6: Scanning Options, Progress Bar & Percentage Alignment

**Files:**
- Modify: `lib/features/schedule_import/import_schedule_screen.dart:49-55, 145-185, 328-330, 1004, 1707-1790`
- Modify: `lib/features/schedule_import/services/schedule_ocr_service.dart:114-128`
- Modify: `lib/features/schedule_import/widgets/import_review_widgets.dart:376-412`
- Test: `test/import_schedule_screen_test.dart`

**Interfaces:**
- Consumes: `ScheduleOcrService`, `ImportScanStage`
- Produces: Reliable progress reporting during rotated grid scans (<40% in stage 2), clean percentage typography, removal of VL server UI

- [ ] **Step 1: Write failing test for scan server removal and progress bounds**
In `test/import_schedule_screen_test.dart`, assert that "High-accuracy scan server" is not present on the import screen:
```dart
testWidgets('ImportScheduleScreen does not show high accuracy scan server', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: ImportScheduleScreen()));
  expect(find.textContaining('High-accuracy scan server'), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/import_schedule_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: Remove scan server UI and fix progress & percentage alignment**
- In `import_schedule_screen.dart`: Remove `_vlServerCard` and calls to `_loadVlServerUrl`, `_saveVlServerUrl`, and `_vlUrlController`.
- In `schedule_ocr_service.dart`: In `scanGridImage()`, change `onProgress(.9, ...)` to `onProgress(.20 + .06 * turns, 'Checking rotated timetable layout')`, scaling progress within `[0.20, 0.40]` instead of jumping to `0.90`.
- In `import_review_widgets.dart` (`ImportScanProgress`): Align `$percent%` with `widget.stage.shortLabel` using proper cross-axis alignment (`CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic`) or matched line-height centering.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/import_schedule_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/features/schedule_import/import_schedule_screen.dart lib/features/schedule_import/services/schedule_ocr_service.dart lib/features/schedule_import/widgets/import_review_widgets.dart test/import_schedule_screen_test.dart
git commit -m "fix: remove scan server, correct grid progress jump, and align scan percentage"
```

---

### Task 7: Edit Class Button & Delete Confirmation Validation

**Files:**
- Modify: `lib/screens/edit_class_screen.dart:940-995`
- Modify: `lib/widgets/class_delete_undo.dart:1-81`
- Modify: `lib/screens/home_screen.dart:188-191`
- Modify: `lib/screens/schedule_screen.dart:142-145`
- Modify: `lib/widgets/swipe_actions.dart:168-185`
- Test: `test/edit_class_screen_test.dart`, `test/delete_confirmation_dialog_test.dart`

**Interfaces:**
- Consumes: `showDeleteConfirmation(context, ...)`
- Produces: Centered "Tap to confirm" on `EditClassScreen`; delete with confirmation dialog across Home, Schedule, and Swipe without undo toast

- [ ] **Step 1: Write failing tests for delete confirmation instead of undo**
Write test asserting that swiping to delete or tapping delete prompts `showDeleteConfirmation` and does not display an 'Undo' snackbar action:
```dart
testWidgets('Deleting class shows confirmation dialog and no undo action', (tester) async {
  // Setup class and trigger delete
  await tester.pumpAndSettle();
  expect(find.text('Delete class?'), findsOneWidget);
  // Tap delete in dialog
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
  expect(find.text('Undo'), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/edit_class_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: Fix "Tap to confirm" layout and replace undo with confirmation**
- In `edit_class_screen.dart` (`_buildActionsRow`): When armed, center the "Tap to confirm" text with `Text(..., textAlign: TextAlign.center, style: TextStyle(fontSize: 14, ...))` so it does not wrap or clip.
- In `class_delete_undo.dart` (or `delete_class_action.dart`): Show `showDeleteConfirmation(context, title: 'Delete class?', message: 'Are you sure you want to delete ${item.subject}?')` before deleting. If confirmed, delete and sync reminders; show notification "Class deleted" without `actionLabel: 'Undo'`.
- In `swipe_actions.dart`: When delete is triggered, await completion; if cancelled by user, animate card back via `_animateTo(0.0)`.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/edit_class_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/screens/edit_class_screen.dart lib/widgets/class_delete_undo.dart lib/screens/home_screen.dart lib/screens/schedule_screen.dart lib/widgets/swipe_actions.dart test/edit_class_screen_test.dart
git commit -m "feat: fix delete tap-to-confirm position and replace undo with confirmation dialog"
```

---

### Task 8: Import Review & Import Complete Polish

**Files:**
- Modify: `lib/features/schedule_import/import_schedule_screen.dart:1440-1515`
- Modify: `lib/features/schedule_import/widgets/import_review_widgets.dart:740-825, 950-1085`
- Test: `test/import_schedule_screen_test.dart`

**Interfaces:**
- Consumes: `ImportAttentionBanner`, `_importSuccessCard`
- Produces: Polished, borderless button placement for validation banners, draft cards, and import completion

- [ ] **Step 1: Write failing test for Import Complete button design**
Assert that the completion card buttons do not have borders and are clearly structured.

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/import_schedule_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: Update `ImportAttentionBanner` button placement and `_importSuccessCard`**
- In `import_review_widgets.dart` (`ImportAttentionBanner`): Place the acknowledge/dismiss button inline or full-width with consistent padding instead of floated `centerRight`.
- In `import_schedule_screen.dart` (`_importSuccessCard`): Redesign "View schedule" and "Import another" with full-width or primary/secondary filled styling, without outlines (`BorderSide.none`).
- In `ImportDraftCard`: Ensure drafts with validation issues cleanly present the issue text and edit action.

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/import_schedule_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/features/schedule_import/import_schedule_screen.dart lib/features/schedule_import/widgets/import_review_widgets.dart test/import_schedule_screen_test.dart
git commit -m "fix: polish import review validation button placement and complete screen design"
```

---

### Task 9: Card Gesture & Visual Polish (Swipe UI/UX Overhaul, Scale, Bleed Prevention & 3-Dot Removal)

**Files:**
- Modify: `lib/widgets/class_card.dart:125-145, 252-308`
- Modify: `lib/widgets/swipe_actions.dart:200-298`
- Test: `test/class_card_test.dart`, `test/swipe_actions_test.dart`

**Interfaces:**
- Consumes: `ClassCard`, `SwipeActions`
- Produces: Polished swipe UI/UX with clear labels ("Edit", "Delete") and reveal micro-scaling, non-shrinking class card during swipes, invisible action plane when closed (no bleed through 50% opacity), smooth animated return on cancelled delete, removal of 3-dot menu with custom semantics retained

- [ ] **Step 1: Write failing test in `test/class_card_test.dart` and `test/swipe_actions_test.dart`**
Assert that `PopupMenuButton` is not in `ClassCard`, custom semantics actions for "Edit class" and "Delete class" are present, card does not scale down on horizontal drag, and action plane displays labels:
```dart
testWidgets('ClassCard does not render 3-dot popup menu', (tester) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ClassCard(item: testItem, onEdit: () {}, onDelete: () {}))));
  expect(find.byType(PopupMenuButton), findsNothing);
  expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
});

testWidgets('SwipeActions action plane includes Edit and Delete labels', (tester) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SwipeActions(forceOpen: true, onEdit: () {}, onDelete: () {}, child: const Text('Card')))));
  expect(find.text('Edit'), findsOneWidget);
  expect(find.text('Delete'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**
Run: `flutter test test/class_card_test.dart test/swipe_actions_test.dart`
Expected: FAIL

- [ ] **Step 3: Overhaul swipe UI/UX, remove 3-dot menu, prevent bleed-through, and fix swipe scale**
- In `class_card.dart`:
  - Remove `PopupMenuButton<_ClassAction>` (lines 252-308).
  - Add `customSemanticsActions` for "Edit class" (`onEdit`) and "Delete class" (`onDelete`) on `Semantics`.
  - Remove `PressableScale` scale-down during swipe gestures so card scale stays 1.0.
- In `swipe_actions.dart`:
  - Update `_ActionPlane` to include clear labels ("Edit", "Delete") under each icon with bold styling (`textTheme.labelSmall`), vertical centering, and touch-target padding.
  - Add micro-scale easing to the action icons and labels as `_controller.value` moves from 0 to 1.
  - Wrap the `Positioned` action plane in `Visibility(visible: _revealed, child: ...)` so it is completely hidden while the card is closed (`_controller.value <= 0.02`), preventing red/blue buttons from shining through marked cards at 0.5 opacity.
  - On delete cancellation, ensure the card smoothly glides back closed (`_animateTo(0.0)`).

- [ ] **Step 4: Run test to verify it passes**
Run: `flutter test test/class_card_test.dart test/swipe_actions_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**
```bash
git add lib/widgets/class_card.dart lib/widgets/swipe_actions.dart test/class_card_test.dart test/swipe_actions_test.dart
git commit -m "feat: overhaul swipe UI/UX, remove 3-dot menu, prevent swipe shrinking, and hide action plane when closed"
```

---

### Task 10: Full Test Suite Verification

- [ ] **Step 1: Run complete test suite**
Run: `flutter test`
Expected: All tests pass (with only the pre-existing un-edited OCR test documented).

- [ ] **Step 2: Final cleanup and commit**
Review all changes against Ponytail simplification rules and ensure no dead code or unnecessary files remain.
```bash
git status
```
