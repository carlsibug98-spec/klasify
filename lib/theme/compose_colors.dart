import 'package:flutter/material.dart';

/// The dark "compose mode" palette: the intentionally dark, focused surfaces
/// that ignore the app theme — the class editor, its time-picker sheet, and
/// the dark branch of the import scan/review widgets (which adapt between
/// this palette and the active scheme).
///
/// Every color these surfaces use lives here so the palette has a single
/// source of truth; previously each file hand-copied its own hexes and they
/// drifted silently (#2A2A2A vs #2C2C2C, #3A1C1C vs #3A1D1D, a stray blue
/// accent). Text tokens meet WCAG AA (≥ 4.5:1) on every background they are
/// used with — see scripts/verify_contrast.py for the recomputable math.
abstract final class ComposeColors {
  /// Scaffold background (pure black).
  static const Color background = Color(0xFF000000);

  /// Section cards, sheets, and the time-picker surface on black.
  static const Color surface = Color(0xFF141414);

  /// The attention/cancel sheet's near-black background.
  static const Color bannerSurface = Color(0xFF1A1A1A);

  /// Text fields, info chips, and the picker's highlight band.
  static const Color field = Color(0xFF1F1F1F);

  /// Focused text field fill.
  static const Color fieldFocused = Color(0xFF2C2C2C);

  /// Raised chrome on compose surfaces: chips, step circles, tracks,
  /// secondary tiles.
  static const Color raised = Color(0xFF2A2A2A);

  /// Sheet drag handle. 3.41:1 on [surface] — above the 3:1 WCAG component
  /// minimum (the old #4A4A4A measured 2.08:1).
  static const Color grabber = Color(0xFF6A6A6A);

  /// Placeholder hints, unselected picker values, skipped/skipped-state text.
  /// The dimmest text token that passes WCAG AA on every fill it can appear
  /// over — [field] (5.64:1), focused [fieldFocused] (4.78:1),
  /// [errorContainer] (5.23:1), and [surface] (6.31:1).
  static const Color hint = Color(0xFF979797);

  /// Secondary text (labels, supporting copy).
  static const Color muted = Color(0xFFA3A3A3);

  /// Validation errors and destructive accents (soft red that reads on dark).
  static const Color error = Color(0xFFF28B82);

  /// Red-tinted fill behind error content (field error state, warning icons).
  static const Color errorContainer = Color(0xFF3A1D1D);

  /// Text and icons on [error] fills.
  static const Color onError = Color(0xFF1A0A0A);

  /// Delete button.
  static const Color danger = Color(0xFFE53935);

  /// Delete button after the first tap (armed, waiting for confirmation).
  static const Color dangerArmed = Color(0xFFB71C1C);
}
