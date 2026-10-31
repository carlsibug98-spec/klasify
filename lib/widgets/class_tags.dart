import 'package:flutter/material.dart';

import '../models/class_status.dart';
import '../theme/app_theme.dart';
import 'pill.dart';

/// Small labels shared by the class surfaces (the Today card and the
/// weekly schedule's segmented rows): the live NOW tag, the hero's
/// "Next up" tag, and the user-mark status pill.

/// The NOW label: a small pill in the app's live color, with text in the
/// theme's inverse ink so it reads on both light and dark schemes.
class NowTag extends StatelessWidget {
  const NowTag({super.key, required this.color, this.pulse});

  final Color color;
  final Widget? pulse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse != null) ...[pulse!, const SizedBox(width: 5)],
          Text(
            'NOW',
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Next up" pill on the class the hero is showing as next. Filled with the
/// inverse ink, like the hero block, so it matches the hero's label.
class NextUpTag extends StatelessWidget {
  const NextUpTag({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Text(
        'Next up',
        style: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Status pill with the app's theme colors: green for finished, amber for
/// cancelled, neutral for not attending.
class ClassStatusPill extends StatelessWidget {
  const ClassStatusPill({super.key, required this.status, required this.label});

  final DayStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      DayStatus.finished => (
        AppTheme.successBackgroundOf(context),
        AppTheme.successForegroundOf(context),
      ),
      DayStatus.cancelled => (
        AppTheme.warningBackgroundOf(context),
        AppTheme.warningForegroundOf(context),
      ),
      DayStatus.notAttending => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
    };
    return Pill(label: label, background: background, foreground: foreground);
  }
}
