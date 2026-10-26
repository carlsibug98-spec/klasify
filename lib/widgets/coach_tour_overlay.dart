import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one-time coach tour, from the design: a spotlight ring around the
/// target and a floating tooltip with the step kicker, title, body, progress
/// dots and the Next / Got it button. Shown once, right after the user adds
/// their first class — steps whose target isn't on screen are skipped.
///
/// Visual contract (from the mocks): a 2px white ring around the highlighted
/// region with a huge soft dark veil everywhere else (the web mock's
/// `0 0 0 1200px rgba(0,0,0,.66)` shadow, drawn here as an even-odd hole cut
/// in a full-screen scrim), a white tooltip card whose caret leans on the
/// spotlight, the black progress bar-dot for the current step, and a filled
/// "Next"/"Got it" button. Reduced motion collapses the entrance to a jump.
class CoachTourOverlay extends StatefulWidget {
  const CoachTourOverlay({
    super.key,
    required this.keys,
    required this.onDone,
    this.onTargetActive,
  });

  /// RenderObject anchors for the tour targets.
  final CoachTargetKeys keys;

  /// Runs when the tour ends (finished or skipped). The caller marks the
  /// store before mounting, so this only dismisses the overlay.
  final VoidCallback onDone;

  /// Fires whenever the spotlight moves (including the initial step), so
  /// the shell can stage demonstrations — e.g. holding the swipe plane open
  /// on the card step.
  final ValueChanged<CoachTarget>? onTargetActive;

  /// The steps, in tour order.
  static const List<CoachStepSpec> steps = [
    CoachStepSpec(
      target: CoachTarget.hero,
      title: 'Your next class, live',
      body:
          'This black card shows what’s in progress or coming up. Tap it for '
          'the room and details.',
    ),
    CoachStepSpec(
      target: CoachTarget.swipeCard,
      title: 'Swipe a class left',
      body: 'Edit or delete a class without opening it.',
    ),
    CoachStepSpec(
      target: CoachTarget.fab,
      title: 'Add or scan classes',
      body:
          'Type one in, or scan a timetable photo or PDF. You review it before '
          'anything is saved.',
    ),
    CoachStepSpec(
      target: CoachTarget.nav,
      title: 'Week and Settings',
      body:
          'Week shows every day at a glance. Settings holds reminders and '
          'backup.',
    ),
  ];

  @override
  State<CoachTourOverlay> createState() => _CoachTourOverlayState();
}

/// A tour step definition: which thing to spotlight and what to say.
class CoachStepSpec {
  const CoachStepSpec({
    required this.target,
    required this.title,
    required this.body,
  });

  final CoachTarget target;
  final String title;
  final String body;
}

/// Which pieces of the app the tour can spotlight.
enum CoachTarget { hero, swipeCard, fab, nav }

/// Anchors for the overlay: keys attached to the hero, the first class card,
/// the quick-actions button and the bottom navigation bar.
class CoachTargetKeys {
  CoachTargetKeys({
    required this.heroKey,
    required this.swipeTargetKey,
    required this.fabKey,
    required this.navKey,
  });

  final GlobalKey heroKey;
  final GlobalKey swipeTargetKey;
  final GlobalKey fabKey;
  final GlobalKey navKey;

  static const double _heroRadius = 28;
  static const double _cardRadius = 22;
  static const double _fabRadius = 22;
  static const double _navRadius = 24;

  static const double _pad = 6;

  GlobalKey _keyOf(CoachTarget target) => switch (target) {
    CoachTarget.hero => heroKey,
    CoachTarget.swipeCard => swipeTargetKey,
    CoachTarget.fab => fabKey,
    CoachTarget.nav => navKey,
  };

  double _radiusOf(CoachTarget target) => switch (target) {
    CoachTarget.hero => _heroRadius,
    CoachTarget.swipeCard => _cardRadius,
    CoachTarget.fab => _fabRadius,
    CoachTarget.nav => _navRadius,
  };

  /// Global rect of a target, expanded [ _pad] px like the mocks. Null when
  /// the target isn't currently on screen (no next class yet, no classes
  /// today, desktop layout).
  ({Rect rect, double radius})? locate(CoachTarget target) {
    final context = _keyOf(target).currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return (
      rect: (box.localToGlobal(Offset.zero) & box.size).inflate(_pad),
      radius: _radiusOf(target),
    );
  }
}

class _CoachTourOverlayState extends State<CoachTourOverlay>
    with SingleTickerProviderStateMixin {
  static const _tipSideGap = 20;
  static const _holeGap = 18;

  final List<CoachStepSpec> _steps = List.of(CoachTourOverlay.steps);
  int _stepIndex = 0;
  CoachTarget? _reportedTarget;

  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: AppTheme.motionStandard,
  );

  final GlobalKey _tipKey = GlobalKey();

  // Resolved geometry for the current step; refreshed post-frame.
  Rect? _hole;
  double _holeRadius = 22;
  bool _tipBelow = true;
  double _tipLeft = _tipSideGap.toDouble();
  double _tipWidth = 350;
  double? _tipTop;
  double? _tipBottom;
  double _caretX = 48;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneUnavailableLeadingSteps();
      _measure();
      if (!MediaQuery.of(context).disableAnimations) {
        _entry.forward(from: 0);
      } else {
        _entry.value = 1;
      }
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  CoachStepSpec get _current => _steps[_stepIndex];

  /// Reports the currently spotlighted target once per transition.
  void _reportTarget(CoachTarget target) {
    if (_reportedTarget == target) return;
    _reportedTarget = target;
    widget.onTargetActive?.call(target);
  }

  /// Steps whose target isn't on screen don't exist for this tour; with the
  /// overlay freshly mounted the anchors may need a frame, so this only ever
  /// runs post-frame.
  void _pruneUnavailableLeadingSteps() {
    while (_steps.isNotEmpty &&
        widget.keys.locate(_steps.first.target) == null) {
      setState(() => _steps.removeAt(0));
    }
    if (_steps.isEmpty) widget.onDone();
  }

  void _goTo(int index) {
    if (index >= _steps.length) {
      widget.onDone();
      return;
    }
    setState(() => _stepIndex = index);
    _measure();
    if (!MediaQuery.of(context).disableAnimations) {
      _entry.forward(from: 0);
    } else {
      _entry.value = 1;
    }
  }

  /// Recomputes hole and tooltip geometry from the target's current box.
  ///
  /// Runs post-frame: the first pass renders the tooltip with a height
  /// estimate so the second pass can decide below/above with the real size.
  void _measure() {
    if (!mounted) return;
    final screen = MediaQuery.sizeOf(context);
    final located = widget.keys.locate(_current.target);
    if (located == null) {
      // Target vanished mid-tour (reload, resize): drop the step.
      setState(() {
        _steps.removeAt(_stepIndex);
        if (_stepIndex >= _steps.length) _stepIndex = _steps.length - 1;
      });
      if (_steps.isEmpty) {
        widget.onDone();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      return;
    }
    final hole = located.rect;
    _reportTarget(_current.target);
    final maxWidth = (screen.width - 2 * _tipSideGap).clamp(0.0, 350.0);
    final tipLeft = (screen.width - maxWidth) / 2;
    // The tooltip's real height once laid out; before that, the mock's
    // four-row card is around 210-240px tall.
    final tipBox = _tipKey.currentContext?.findRenderObject() as RenderBox?;
    final tipHeight = tipBox?.size.height ?? 216;
    // Prefer below the spotlight like the mocks; fall to above when that
    // would leave the tooltip colliding with the screen's bottom edge.
    final below = hole.bottom + _holeGap + tipHeight <= screen.height - 8;

    final next = (
      hole: hole,
      radius: located.radius,
      tipBelow: below,
      tipLeft: tipLeft,
      tipWidth: maxWidth,
      tipTop: below ? hole.bottom + _holeGap : null,
      tipBottom: below ? null : screen.height - hole.top + _holeGap,
      caretX: (hole.center.dx - tipLeft - 8)
          .clamp(24, maxWidth - 24)
          .toDouble(),
    );
    if (next == _lastGeometry) return;
    _lastGeometry = next;
    setState(() {
      _hole = next.hole;
      _holeRadius = next.radius;
      _tipBelow = next.tipBelow;
      _tipLeft = next.tipLeft;
      _tipWidth = next.tipWidth;
      _tipTop = next.tipTop;
      _tipBottom = next.tipBottom;
      _caretX = next.caretX;
    });
    if (!_measuredWithTipBox && tipBox != null) {
      _measuredWithTipBox = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  ({
    Rect hole,
    double radius,
    bool tipBelow,
    double tipLeft,
    double tipWidth,
    double? tipTop,
    double? tipBottom,
    double caretX,
  })?
  _lastGeometry;
  bool _measuredWithTipBox = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Swallows every tap anywhere, so the app can't be used while the
          // tour is guiding; tapping past the tip advances, matching the
          // playful product tours.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goTo(_stepIndex + 1),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _SpotlightPainter(hole: _hole, radius: _holeRadius),
              ),
            ),
          ),
          if (_hole != null) _tooltip(scheme, textTheme),
        ],
      ),
    );
  }

  Widget _tooltip(ColorScheme scheme, TextTheme textTheme) {
    final animation = CurvedAnimation(
      parent: _entry,
      curve: AppTheme.motionEaseOut,
    );
    final tip = DecoratedBox(
      key: _tipKey,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 14, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'STEP ${_stepIndex + 1} OF ${_steps.length}',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface,
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _TourTextButton(label: 'Skip tour', onTap: widget.onDone),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _current.title,
              style: textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontSize: 20,
                height: 1.3,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _current.body,
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 15,
                height: 22 / 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Semantics(
                    label: 'Step ${i + 1} of ${_steps.length}',
                    child: Container(
                      width: i == _stepIndex ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _stepIndex
                            ? scheme.onSurface
                            : const Color(0xFF8A8A8A),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _CtaButton(
                  label: _stepIndex == _steps.length - 1 ? 'Got it' : 'Next',
                  onTap: () => _goTo(_stepIndex + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final entrance = FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
        alignment: _tipBelow ? Alignment.topLeft : Alignment.bottomLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(decoration: const BoxDecoration(), child: tip),
            if (_tipBelow)
              Positioned(
                top: -7,
                left: _caretX,
                child: _Caret(color: scheme.surface, above: true),
              )
            else
              Positioned(
                bottom: -7,
                left: _caretX,
                child: _Caret(color: scheme.surface, above: false),
              ),
          ],
        ),
      ),
    );

    return Positioned(
      left: _tipLeft,
      width: _tipWidth,
      top: _tipTop,
      bottom: _tipBottom,
      child: entrance,
    );
  }
}

/// The full-screen veil with a rounded hole, plus the 2px white ring.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.hole, required this.radius});

  final Rect? hole;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (hole == null) {
      // Before the first measure everything sits under the veil.
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xA8000000),
      );
      return;
    }
    final holeRect = RRect.fromRectAndRadius(hole!, Radius.circular(radius));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(holeRect);
    canvas.drawPath(path, Paint()..color = const Color(0xA8000000));
    canvas.drawRRect(
      holeRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.radius != radius;
}

/// The white caret leaning on the tooltip edge: a 16px square rotated 45°,
/// one corner rounded like the mocks.
class _Caret extends StatelessWidget {
  const _Caret({required this.color, required this.above});

  final Color color;
  final bool above;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 3.141592653589793 / 4,
      origin: const Offset(8, 8),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(
            topLeft: above ? const Radius.circular(3) : Radius.zero,
            bottomRight: above ? Radius.zero : const Radius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// "Skip tour": quiet text on the tooltip's top row.
class _TourTextButton extends StatelessWidget {
  const _TourTextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: scheme.onSurfaceVariant,
      ),
      child: Text(
        label,
        style: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The filled pill: "Next" until the last step, then "Got it".
class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return Semantics(
      button: true,
      child: Material(
        color: scheme.primary,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            child: Text(
              label,
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onPrimary,
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
