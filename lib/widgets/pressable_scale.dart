import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Subtle press feedback: scales its child down a touch while a pointer is
/// down, and eases back on release. Used on the app's primary tap targets
/// (class cards, hero card) where ripple alone reads as flat.
///
/// [Listener] is used instead of [GestureDetector] on purpose: it observes
/// pointer events without entering the gesture arena, so it never competes
/// with the [InkWell] inside the child. Inert when [enabled] is false or
/// reduced motion ("remove animations") is on.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.98,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return Listener(
      onPointerDown: widget.enabled && !reducedMotion
          ? (_) => setState(() => _pressed = true)
          : null,
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: AppTheme.motionDuration(context, AppTheme.motionFast),
        curve: AppTheme.motionEaseOut,
        child: widget.child,
      ),
    );
  }
}
