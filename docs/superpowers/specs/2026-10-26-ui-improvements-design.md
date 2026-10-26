# Design Document: Klasify UI & Interaction Improvements

- **Date**: 2026-10-26
- **Status**: Proposed (Under Review)
- **Author**: Assistant & User Pair Programming

---

## 1. Intent and Why
Klasify's UI has accumulated extraneous wrappers (container cards behind empty states and reminders), broken progress reporting in OCR scanning, visually misaligned indicators, and inconsistent interactions (class cards shrinking during swipe drags, action buttons bleeding through semi-transparent cards, and an undo snackbar instead of upfront confirmation on delete). 

This update streamlines the visual hierarchy across the app, removes outlines for a clean borderless look, ensures scanning progress reliably reflects reality, replaces delete undo with explicit confirmation, and standardizes call-to-actions to "Import schedule".

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **Today Screen**:
  - Remove the enclosing card background from the "Scan it" and "Add by hand" options.
  - Remove the "Data Structures" preview card and all associated code/structures.
  - Show upcoming hero class time as relative duration ("Starts in Xd Yh Zm" or "Starts in Xh Ym") instead of clock time.
- **Weekly Schedule Screen**:
  - Replace the "Add class" and "Import timetable" empty state buttons with "Scan it" and "Add by hand" without any card behind them.
- **Class Reminders**:
  - Remove the "Back up your schedule" section.
  - Remove the card background behind "Remind me before class" and resize the widget for a clean standalone appearance.
- **Scanning Flow**:
  - Remove the "High-accuracy scan server" option card, settings persistence, and client logic.
  - Fix the scanning progress calculation so it does not prematurely jump to 90% during the grid detection stage (rotated scan passes).
  - Fix OCR progress percentage typography and baseline text alignment.
- **Edit Class & Deletion**:
  - Fix the layout and position of "Tap to confirm" on the delete action button to prevent squeezing or clipping.
  - Replace post-delete undo with an upfront confirmation dialog (`showDeleteConfirmation`) across all class deletion entry points (Edit screen, swipe action, long-press).
- **Import Review & Complete**:
  - Fix button placement in Import Review for items that require review or validation.
  - Redesign the buttons on the Import Complete card without outlines.
- **Card Swiping & Design Consistency**:
  - Prevent class cards from shrinking when swiped (disable pressed scale during horizontal gestures).
  - Hide the background Edit/Delete action plane when the card is closed so buttons do not bleed through 50% opacity marked classes.
  - Remove the 3-dot overflow menu (`PopupMenuButton`) from the class card.
  - Remove border outlines across all designs (`BorderSide.none`, borderless cards/buttons/chips).
  - Update all CTA copy from "Import timetable" to "Import schedule".

### Non-Goals
- Changing the underlying OCR recognition engines or database schema.
- Modifying notification scheduling rules in `ReminderService`.
- Rewriting unrelated screens (e.g. Onboarding tutorial flow).

### Anti-Goals
- Adding complex multi-tier abstraction layers or new state management packages.
- Hiding errors silently during import validation.
- Breaking existing test coverage.

---

## 3. Constraints
- **Platform & Language**: Flutter / Dart.
- **Design Guidelines**: Follow Ponytail's minimal implementation principles (prefer standard widgets, minimal diffs, avoid over-engineering) and interaction craft (smooth transitions, clean typography, tabular figures).
- **Semantics & Accessibility**: Ensure all modified actions and states retain proper labels, live regions, and tap targets.

---

## 4. Approaches Considered

### Approach 1: Targeted Refinement & Simplification (Selected)
- Modify each target component and screen directly:
  - Clean up `FirstRunOptions` (remove outer container, remove `showExample` and `Data Structures` example card).
  - Reuse `FirstRunOptions` in `WeekAgendaView` empty state.
  - Remove `_vlServerCard` and high-accuracy server logic from `import_schedule_screen.dart` and `schedule_ocr_service.dart`.
  - Fix the progress calculation in `schedule_ocr_service.dart` during rotated grid scanning (keep it within the 0.15–0.40 range).
  - Fix baseline alignment of OCR percentage in `ImportScanProgress`.
  - Replace `deleteClassWithUndo` with `showDeleteConfirmation` in `HomeScreen`, `ScheduleScreen`, `ClassFormScreen`, and `EditClassScreen`.
  - In `SwipeActions`, make the background action plane visible only when `_revealed` is true.
  - In `ClassCard`, remove `PressableScale` scale-down during swipe and delete `PopupMenuButton`.
  - Remove outlines (`BorderSide.none`, `Border.all` deletions) in `AppTheme`, cards, and button styles.
  - Update all occurrences of "Import timetable" to "Import schedule".
- *Trade-offs*: Fast, predictable, lowest regression risk, perfectly aligns with Ponytail.

### Approach 2: Screen Re-architecture
- Create generic abstraction frameworks for empty states, confirmation dialogs, and import flows.
- *Trade-offs*: Unnecessary overhead, violates YAGNI and Ponytail simplicity, risks introducing new bugs.

---

## 5. Detailed Component Specifications

### 5.1 Today Screen & Hero
- **`lib/widgets/first_run_options.dart`**:
  - Remove the outer `Container(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(24), padding: const EdgeInsets.all(14))`. The two tiles (`Scan it` and `Add by hand`) are laid out directly in an `IntrinsicHeight` `Row`.
  - Delete `showExample` parameter and the entire `Data Structures` example card container (lines 71-120).
- **`lib/screens/home_screen.dart`**:
  - On line 321, replace `'Starts ${formatMinutes(next.item.startMinutes)}'` with `next.whenText`.
  - `NextClass.whenText` already returns `"Starts in Xd Yh Zm"` or `"Starts in Xh Ym"` or `"Starts in X min"`. Ensure formatting reads cleanly in days, hours, and mins.

### 5.2 Weekly Schedule Empty State
- **`lib/widgets/week_agenda_view.dart`**:
  - In `allClassesEmpty`: replace the `EmptyStateCard` with `FirstRunOptions(onScan: ..., onAdd: ...)`.
  - Ensure it has no card container behind it.

### 5.3 Class Reminders
- **`lib/screens/reminders_screen.dart`**:
  - Remove the "Back up your schedule" `Material` card (lines 356-407).
  - In `_ReminderPanel`: remove the outer `Container(color: scheme.surfaceContainer, borderRadius: 24)`.
  - Resize `_ReminderCard` so "Remind me before class" and the lead time chips render as a clean, cohesive borderless section.

### 5.4 Scanning & Progress
- **`lib/features/schedule_import/import_schedule_screen.dart`**:
  - Remove `_vlServerCard` and calls to `_loadVlServerUrl`, `_saveVlServerUrl`, and `_vlUrlController`.
- **`lib/features/schedule_import/services/schedule_ocr_service.dart`**:
  - In `scanGridImage` (lines 116-124), fix the progress reporting:
    - Replace `onProgress(.9, 'Trying a rotated grid scan')` with progress within the grid stage: `onProgress(.20 + .06 * turns, 'Checking rotated timetable layout')`.
    - Map rotated grid scan progress to the `[0.20, 0.40]` range instead of `[0.9, 0.99]`.
- **`lib/features/schedule_import/widgets/import_review_widgets.dart`**:
  - In `ImportScanProgress`: align the `$percent%` text with the stage heading using `CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic` or vertical centering with matching typography so it is cleanly aligned.

### 5.5 Edit Class & Delete Confirmation
- **`lib/screens/edit_class_screen.dart`**:
  - `EditClassScreen` maintains its two-tap destructive pattern. When armed (`_deleteArmed = true`), fix the button layout so that "Tap to confirm" is properly centered, uses appropriate font size and padding, and never wraps or clips across different screen densities.
- **Confirmation Step Replacement for Undo**:
  - Replace `deleteClassWithUndo` (used by `HomeScreen`, `ScheduleScreen`, and `WeekAgendaView`) with an upfront confirmation dialog (`showDeleteConfirmation`):
    - When triggered from swipe-to-delete or card long-press, prompt the user with `showDeleteConfirmation`.
    - If the user confirms, delete from the database and call `ReminderService.instance.sync()`. Show a standard success banner ("Class deleted") without an "Undo" action.
    - In `SwipeActions`: if `onDelete` is triggered by a full-swipe or fling, await confirmation. If cancelled by the user, animate the card smoothly back to its resting position (`_animateTo(0)`).
    - Remove the undo restoration logic and notification toast from the app.

### 5.6 Import Review & Import Complete
- **Import Review**:
  - In `ImportAttentionBanner`: fix the placement of action buttons (e.g. "Acknowledge and continue") to align cleanly with the content, without odd right-floating offsets.
  - In `ImportDraftCard`: for flagged cards or drafts needing validation, ensure clear layout without misaligned buttons.
- **Import Complete (`_importSuccessCard`)**:
  - Replace `OutlinedButton.icon` with borderless styled buttons.
  - Align "View schedule" and "Import another" in a consistent, polished layout without borders.

### 5.7 Swipe Gestures, Action Plane UI/UX & Design Consistency
- **Swipe Action Plane UI/UX Overhaul**:
  - **Visible Action Labels**: Add clear, legible labels ("Edit", "Delete") under the icons in `_ActionPlane` with bold styling (`textTheme.labelSmall`), vertical centering, and touch-target padding so users instantly understand both actions.
  - **Action Reveal Micro-Interaction**: Scale and fade the action icons and labels smoothly (scaling from 0.85 to 1.0) as the user drags the plane open, providing organic physical feedback.
  - **Zero Card Shrink**: Remove `PressableScale` scale-down during swipe drag so the class card maintains its full 100% scale while swiping.
  - **Prevent Button Bleed-Through**: Wrap the action plane (`Positioned(...)`) in `Visibility(visible: _revealed, child: ...)` so that when the card is closed, the red Delete and blue Edit buttons are completely hidden and cannot bleed through cards with 0.5 opacity when marked.
  - **Smooth Confirmation & Dismissal**: When delete is triggered, if the user cancels the confirmation dialog, the card smoothly glides back to its resting closed state using an ease-out motion curve (`_animateTo(0.0)`).
- **Remove 3-dot Menu & Preserve Accessibility**:
  - In `ClassCard`, remove the `PopupMenuButton<_ClassAction>` (`Icons.more_vert_rounded`).
  - Add `CustomSemanticsAction` to `ClassCard` semantics for "Edit class" and "Delete class" so screen reader users (TalkBack/VoiceOver) retain full access to these actions without needing visual buttons or swipe gestures.
- **Remove Design Outlines**:
  - In `app_theme.dart`: set `OutlinedButtonThemeData` side to `BorderSide.none`, remove card borders (`BorderSide.none`), remove container borders (`Border.all(...)`) in `FirstRunOptions`, `ImportScheduleScreen`, `RemindersScreen`, and `PinnedActionBar`.
- **CTA Copy**:
  - Change all instances of "Import timetable" to "Import schedule" in `MainNavigationScreen`, `SettingsScreen`, `ImportScheduleScreen`, `NextClassCard`, and `WeekAgendaView`.

---

## 6. What's Left to the Builder
- Exact layout padding adjustments for pixel-perfect balance on small screens.
- Updating widget and unit tests that assert against previous strings ("Import timetable", "Data Structures", undo snackbar).
