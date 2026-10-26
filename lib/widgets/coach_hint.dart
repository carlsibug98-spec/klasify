import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One-time coach hint (the v36 pattern): a quiet tip banner that teaches a
/// gesture, disappears via its close button or once the gesture is actually
/// used, and never comes back — the dismissal is persisted in
/// [SwipeHintStore] by the parent.
class CoachHint extends StatelessWidget {
  const CoachHint({super.key, required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Row(
        children: [
          Icon(
            Icons.swipe_left_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              iconSize: 16,
              padding: EdgeInsets.zero,
              icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
