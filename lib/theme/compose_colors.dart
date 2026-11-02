import 'package:flutter/material.dart';

/// Theme-aware "compose mode" palette: the focused form surfaces used by the
/// class editor, its time-picker sheet, and the import review widgets.
///
/// Dark mode keeps the original intentionally-dark "compose" look; light mode
/// mirrors it on the app's light surfaces so the editor follows the app theme
/// instead of always being black.
class ComposeColors {
  ComposeColors._();

  /// Returns the palette for the current theme brightness.
  static ComposePalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? ComposePalette.dark
          : ComposePalette.light;
}

/// An immutable set of compose-mode color tokens.
class ComposePalette {
  const ComposePalette({
    required this.background,
    required this.surface,
    required this.bannerSurface,
    required this.field,
    required this.fieldFocused,
    required this.raised,
    required this.grabber,
    required this.hint,
    required this.muted,
    required this.error,
    required this.errorContainer,
    required this.onError,
    required this.danger,
    required this.dangerArmed,
  });

  final Color background;
  final Color surface;
  final Color bannerSurface;
  final Color field;
  final Color fieldFocused;
  final Color raised;
  final Color grabber;
  final Color hint;
  final Color muted;
  final Color error;
  final Color errorContainer;
  final Color onError;
  final Color danger;
  final Color dangerArmed;

  /// Dark "compose" palette (the original look).
  static const ComposePalette dark = ComposePalette(
    background: Color(0xFF000000),
    surface: Color(0xFF141414),
    bannerSurface: Color(0xFF1A1A1A),
    field: Color(0xFF1F1F1F),
    fieldFocused: Color(0xFF2C2C2C),
    raised: Color(0xFF2A2A2A),
    grabber: Color(0xFF6A6A6A),
    hint: Color(0xFF979797),
    muted: Color(0xFFA3A3A3),
    error: Color(0xFFF28B82),
    errorContainer: Color(0xFF3A1D1D),
    onError: Color(0xFF1A0A0A),
    danger: Color(0xFFE53935),
    dangerArmed: Color(0xFFB71C1C),
  );

  /// Light "compose" palette (mirrors the dark one on light surfaces).
  static const ComposePalette light = ComposePalette(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F4F4),
    bannerSurface: Color(0xFFFFFFFF),
    field: Color(0xFFF4F4F4),
    fieldFocused: Color(0xFFFFFFFF),
    raised: Color(0xFFE6E6E6),
    grabber: Color(0xFFC4C4C4),
    hint: Color(0xFF6B6B6B),
    muted: Color(0xFF4A4A4A),
    error: Color(0xFFB3261E),
    errorContainer: Color(0xFFFBDAD6),
    onError: Color(0xFFFFFFFF),
    danger: Color(0xFFE53935),
    dangerArmed: Color(0xFFB71C1C),
  );
}
