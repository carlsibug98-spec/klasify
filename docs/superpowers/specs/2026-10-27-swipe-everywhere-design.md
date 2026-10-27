# Design: Swipe behavior on every class row surface

Date: 2026-10-27
Status: approved (user directive: "update all of the information in the app …
compare this swipe to delete, and implement all of its behaviour"; question
round opted out via continuation directive)

## Intent

Task 10 made the Today list and Week agenda rows implement the complete
swipe-mockup behavior (attached Edit→Delete plane, snap/armed states,
haptics, full-swipe fly-off, row collapse, 5-second undo, reduced-motion
support). An audit shows two class surfaces still carry only the old delete
affordances. Every surface where a class can be deleted should behave the
same way.

## Audit result

| Surface | Delete affordance today | Swipe? | Decision |
|---|---|---|---|
| Home · Today's classes rows | ⋮ menu, long-press | yes | done in Task 10 |
| Schedule · Week agenda rows | ⋮ menu, long-press | yes | done in Task 10 |
| Home · hero (NextClassCard) | long-press only | **no** | add SwipeActions |
| Import review · draft rows | trash icon button | **no** | add SwipeActions |
| Class form · Delete button | form button | n/a | not a row; keep |
| Reminders / settings | no deletable rows | n/a | not applicable |

## Approach

### Shared widget changes (`swipe_actions.dart`)

- New optional `radius` parameter (default `AppTheme.cardRadius`): the row
  clip, the card's corner squaring, and Delete's self-rounding all use it,
  so the hero (28 px corners) squares correctly.
- Conditional clipping: the row clip and the card squaring clip engage only
  while the plane is revealed (`_revealed`); the plane also fades with
  `reveal` and ignores pointers when closed. Rest-state rendering is then
  untouched — the hero's ambient shadow keeps rendering when closed — while
  the interaction behavior is byte-identical to the mockup once a drag starts.

### Home hero (`home_screen.dart`)

- Wrap only the real-class `NextClassCard` branch in `SwipeActions`; the
  celebration and empty variants stay unwrapped (there is no class to
  delete). The hero row's outer `Padding` insets move into
  `SwipeActions.padding` so the plane lines up with the card exactly.
- `onEdit` opens the class form with the hero's item (the hero previously
  had no edit affordance at all); `onDelete` runs `deleteClassWithUndo`
  (5-second undo snackbar, same as list rows). The long-press fallback and
  the `ValueKey`-driven AnimatedSwitcher stay as they are.

### Import review rows (`import_review_widgets.dart` + screen)

- Wrap each `ImportDraftCard` in `SwipeActions`; the card's vertical 5 px
  margin moves into `SwipeActions.padding` so the collapse takes the gap
  with it.
- `onEdit` runs the existing draft editor; `onDelete` runs the existing
  `_deleteDraft` (immediate removal + success notification, reported as
  `true` — drafts are pre-save staging, so no undo is invented).
- The trash icon button stays as the discoverable fallback, like the ⋮ menu
  on class cards.

## Goals / non-goals

- Goal: one gesture contract everywhere a class row can be deleted.
- Non-goal: changing `SwipeActions`' gesture constants or the mockup
  contract; adding swipe to forms/settings; adding undo to draft removal.
- Anti-goal: regressing the hero's rest-state design (shadow, 28 px corners)
  or the import review layout.

## Testing plan (TDD)

1. Hero: full-swipe deletes via `deleteClassWithUndo` (undo snackbar
   appears); plane Edit opens the class form; celebration/empty heroes
   expose no swipe plane.
2. Import rows: full-swipe removes the draft and shows the notification;
   plane Edit opens the draft editor; trash button still removes.
3. Rest-state: the hero still renders its `DecoratedBox` shadow when the
   plane is closed (no clip at rest).
4. Existing suites stay green (swipe_actions_test 15, home_screen_hero_test,
   import_review_edit_test, widget_test, …).
