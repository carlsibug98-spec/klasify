import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A quiet handoff between mutually exclusive screen states such as loading,
/// error, empty, and ready content. Timetable content remains still after it
/// has settled so it stays easy to scan.
class AppStateTransition extends StatelessWidget {
  const AppStateTransition({
    super.key,
    required this.stateKey,
    required this.child,
  });

  final ValueKey<String> stateKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;

    return AnimatedSwitcher(
      duration: AppTheme.motionStandard,
      switchInCurve: AppTheme.motionEaseOut,
      switchOutCurve: AppTheme.motionEaseOut,
      transitionBuilder: (child, animation) => ExcludeSemantics(
        excluding: animation.status == AnimationStatus.reverse,
        child: IgnorePointer(
          ignoring: animation.status == AnimationStatus.reverse,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .02),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
        ),
      ),
      child: KeyedSubtree(key: stateKey, child: child),
    );
  }
}
