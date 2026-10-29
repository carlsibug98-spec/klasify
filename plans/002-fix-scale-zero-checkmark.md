# 002 — Stop the status checkmark from appearing from `scale(0)`

- **Status**: DONE
- **Commit**: 610a515
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: 1 file, ~6 lines

## Problem

The "marked" checkmark badge in the day-status sheet pops in from `scale(0)`, which reads as appearing from nothing. The audit playbook requires entrances to start from `scale(0.9–0.97)` plus an opacity fade.

Location: `lib/widgets/day_status_sheet.dart:576-582`

```dart
// lib/widgets/day_status_sheet.dart:576 — current
Positioned(
  top: 6,
  right: 6,
  child: AnimatedScale(
    scale: selected ? 1 : 0,
    duration: AppTheme.motionDuration(context, AppTheme.motionFast),
    curve: AppTheme.motionEaseOut,
    child: ExcludeSemantics(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: selected ? scheme.inverseSurface : null,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: _CheckMark(size: 12, color: scheme.onInverseSurface, strokeWidth: 3),
      ),
    ),
  ),
),
```

## Target

```dart
// lib/widgets/day_status_sheet.dart:576 — target
Positioned(
  top: 6,
  right: 6,
  child: AnimatedOpacity(
    opacity: selected ? 1 : 0,
    duration: AppTheme.motionDuration(context, AppTheme.motionFast),
    curve: AppTheme.motionEaseOut,
    child: AnimatedScale(
      scale: selected ? 1 : 0.9,
      duration: AppTheme.motionDuration(context, AppTheme.motionFast),
      curve: AppTheme.motionEaseOut,
      child: ExcludeSemantics(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: selected ? scheme.inverseSurface : null,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: _CheckMark(size: 12, color: scheme.onInverseSurface, strokeWidth: 3),
        ),
      ),
    ),
  ),
),
```

## Repo conventions to follow

- Motion tokens: `AppTheme.motionFast` (120ms) and `AppTheme.motionEaseOut` (`Cubic(0.23, 1, 0.32, 1)`), collapsed to zero under reduced motion via `AppTheme.motionDuration`.
- Exemplar: `lib/widgets/pressable_scale.dart` uses `AnimatedScale` with `scale: 0.98` and `AppTheme.motionEaseOut`.

## Steps

1. In `lib/widgets/day_status_sheet.dart`, wrap the existing `AnimatedScale` (line ~576) in an `AnimatedOpacity` that animates `opacity: selected ? 1 : 0` with `AppTheme.motionFast` / `AppTheme.motionEaseOut`.
2. Change the inner `AnimatedScale`'s `scale` from `selected ? 1 : 0` to `selected ? 1 : 0.9`.

## Boundaries

- Do NOT touch the status tile background animation or the span-segment animation.
- Do NOT change the checkmark glyph or colours.
- Do NOT add new dependencies.

## Verification

- **Mechanical**: `flutter analyze` clean; `flutter test` passes.
- **Feel check**: select a status tile, set playback to 10%, and confirm the checkmark scales up from ~0.9 while fading in rather than popping from nothing. Toggle `prefers-reduced-motion` and confirm the badge still appears/disappears instantly.
- **Done when**: no `scale: selected ? 1 : 0` remains in `lib/widgets/day_status_sheet.dart`.
