import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small "happening now" indicator: a solid dot with one soft halo that
/// breathes in and out. The only pulsing element allowed in the app — it is
/// reserved for live status, seen occasionally (when a class is in progress),
/// and its purpose is state indication: making "in class" legible at a glance.
///
/// Motion rules followed here:
/// - Animates `transform` (scale) and `opacity` only — GPU-composited layers.
/// - One halo, not stacked ripples; 2.4s cycle, sine-eased (`ease-in-out`
///   semantics) so the loop has no visible snap at either end.
/// - Honors reduced motion: with platform animations disabled the dot stays
///   fully opaque and still. This uses [MediaQuery.disableAnimations], which
///   covers both accessibility "reduce motion" settings and test automation.
class LivePulse extends StatefulWidget {
  const LivePulse({
    super.key,
    this.size = 8,
    this.color,
    this.haloOpacity = 0.35,
  });

  /// Diameter of the solid dot in logical pixels.
  final double size;

  /// Dot colour. Defaults to the theme's live signal colour.
  final Color? color;

  /// Peak opacity of the breathing halo behind the dot.
  final double haloOpacity;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  // Sine-shaped ease-in-out so scale and opacity reach the loop endpoints
  // smoothly — no visible jump where the cycle restarts. A half-period of a
  // cosine mapped to [0,1]: derivative is zero at both ends (0 and 1), which
  // makes the forward and reverse halves join seamlessly on repeat.
  static final Animatable<double> _breath = CurveTween(curve: _SineCurve());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery must be read here, not in initState(). Keep the pulse honest
    // when the system "reduce motion" setting changes mid-session.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.liveOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final dot = SizedBox.square(
      dimension: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
    if (reduced) return ExcludeSemantics(child: dot);

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final breath = _breath.evaluate(_controller); // 0 -> 1 -> 0
          final haloScale = 1 + 0.9 * breath; // grows to ~1.9x, never from 0
          final haloAlpha = widget.haloOpacity * (1 - 0.75 * breath);
          return SizedBox.square(
            dimension: widget.size * 1.9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: haloScale,
                  child: Opacity(
                    opacity: haloAlpha.clamp(0.0, 1.0),
                    child: SizedBox.square(
                      dimension: widget.size,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                dot,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A sine-shaped ease-in-out curve: `t -> 0.5 - 0.5 * math.cos(math.pi * t)`.
/// Derivative is zero at both endpoints, so a forward/reverse loop built from
/// it has no visible snap where the cycle restarts.
class _SineCurve extends Curve {
  @override
  double transformInternal(double t) => 0.5 - 0.5 * (math.cos(math.pi * t));
}
