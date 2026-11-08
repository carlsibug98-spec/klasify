import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one empty-state pattern used across Today, Week and first run.
///
/// Empty states are boxed cards matching the app's card language (fill +
/// hairline + ambient shadow), so they sit with the same weight as the
/// class cards around them. A quiet icon, one line of guidance, and at
/// most two actions.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.cardFillColorOf(scheme),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.fromBorderSide(AppTheme.cardBorderSideOf(scheme)),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: scheme.onSurfaceVariant, size: 18),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    title,
                    style: textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Wrap(spacing: 10, runSpacing: 10, children: actions),
            ),
          ],
        ],
      ),
    );
  }
}