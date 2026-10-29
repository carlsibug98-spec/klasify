# 001 — Replace `Curves.easeIn` fly-off with the app's ease-out curve

- **Status**: DONE
- **Commit**: 610a515
- **Severity**: HIGH
- **Category**: Easing & duration
- **Estimated scope**: 1 file, 1 line

## Problem

The delete fly-off in `SwipeActions` accelerates out using `Curves.easeIn`, which starts slow and delays the moment the user is watching. Per the audit playbook, `ease-in` on UI is always a finding and entering/exiting motion should use `ease-out`.

Location: `lib/widgets/swipe_actions.dart:253`

```dart
// lib/widgets/swipe_actions.dart:253 — current
await _animateTo(_flyOffTarget, curve: Curves.easeIn);
```

## Target

```dart
// lib/widgets/swipe_actions.dart:253 — target
await _animateTo(_flyOffTarget, curve: AppTheme.motionEaseOut);
```

## Repo conventions to follow

- Easing tokens live in `lib/theme/app_theme.dart`: `motionEaseOut = Cubic(0.23, 1, 0.32, 1)`.
- `_animateTo` already sets duration to `AppTheme.motionDuration(context, AppTheme.motionPage)` and respects reduced motion.
- Exemplar: `lib/widgets/swipe_actions.dart:261` uses `AppTheme.motionEaseOut` for the row collapse.

## Steps

1. In `lib/widgets/swipe_actions.dart`, change line 253 from `curve: Curves.easeIn` to `curve: AppTheme.motionEaseOut`.

## Boundaries

- Do NOT touch any other animation in `swipe_actions.dart`.
- Do NOT change the fly-off distance, haptics, or collapse timing.
- Do NOT add new dependencies.

## Verification

- **Mechanical**: `flutter analyze` clean; `flutter test` passes.
- **Feel check**: trigger a full-swipe delete, set playback to 10% in DevTools (or slow the animation), and confirm the card accelerates out of view immediately rather than lingering at the start. Toggle `prefers-reduced-motion` and confirm the fly-off still jumps (duration collapses to zero).
- **Done when**: no `Curves.easeIn` remains in `lib/widgets/swipe_actions.dart`.
