import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Expandable Floating Action Button for triggering quick actions.
class QuickActionsButton extends StatelessWidget {
  const QuickActionsButton({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: FloatingActionButton(
      heroTag: 'main_navigation_quick_actions',
      tooltip: expanded ? 'Close class actions' : 'Open class actions',
      onPressed: onPressed,
      child: AnimatedRotation(
        turns: expanded ? .125 : 0,
        duration: AppTheme.motionDuration(context, AppTheme.motionFast),
        curve: AppTheme.motionEaseOut,
        child: const Icon(Icons.add_rounded),
      ),
    ),
  );
}
