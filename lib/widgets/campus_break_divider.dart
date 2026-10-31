import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Marker for campus study/lunch breaks between the day's segmented
/// stacks (approved mockup C).
///
/// A single centered surface-fill-only chip — no flanking rules. With the
/// segmented stacks the rows carry no trailing gap of their own, so the
/// divider owns the full rhythm: symmetric padding around the chip, the
/// break sitting centered in the gap between two stacks.
class CampusBreakDivider extends StatelessWidget {
  const CampusBreakDivider({super.key, required this.breakMinutes});

  final int breakMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final h = breakMinutes ~/ 60;
    final m = breakMinutes % 60;
    final durationText = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';

    return Padding(
      padding: const EdgeInsets.only(
        left: AppTheme.pageInset,
        right: AppTheme.pageInset,
        top: 7,
        bottom: 7,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.chipRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.coffee_outlined,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                '$durationText break',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
