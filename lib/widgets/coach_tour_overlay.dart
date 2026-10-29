import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one-time coach tour with a refined spotlight and polished tooltip.
/// Shown once after adding the first class. Also carries the single-step
/// variant the empty Today screen shows newcomers ([firstRunSteps]) — the
/// same spotlight language, one short message.
class CoachTourOverlay extends StatefulWidget {
  const CoachTourOverlay({
    super.key,
    required this.keys,
    required this.onDone,
    this.onTargetActive,
    this.steps,
  });

  /// RenderObject anchors for the tour targets.
  final CoachTargetKeys keys;

  /// Runs when the tour ends (finished or skipped). The caller marks the
  /// store before mounting, so this only dismisses the overlay.
  final VoidCallback onDone;

  /// Fires whenever the spotlighted step changes, so the shell can stage
  /// demonstrations — e.g. holding the swipe plane open on the card step.
  final ValueChanged<CoachStepSpec>? onTargetActive;

  /// Override for single-step coaches. Null plays the full 5-step tour.
  /// Exactly one step gets the quiet count-free tooltip ("Dismiss", no dots).
  final List<CoachStepSpec>? steps;

  /// The empty-schedule coach: newcomers who came through "Explore first"
  /// (or skipped onboarding entirely) land on the bare tiles with no tour
  /// yet — the tour only fires after a class exists. This one points at the
  /// two ways in, then gets out of the way.
  static const List<CoachStepSpec> firstRunSteps = [
    CoachStepSpec(
      target: CoachTarget.tiles,
      kicker: 'START HERE',
      title: 'Add your first class',
      body:
          'Tap Scan it to import from a photo or PDF, or Add by hand to type classes in.',
    ),
  ];

  /// The full tour's steps, in tour order.
  static const List<CoachStepSpec> tourSteps = [
    CoachStepSpec(
      target: CoachTarget.hero,
      title: 'Your next class',
      body:
          'See what’s up next or in progress, how long until it starts or ends, and the room to head to.',
    ),
    CoachStepSpec(
      target: CoachTarget.swipeCard,
      title: 'Swipe to manage',
      body: 'Swipe left on any class to edit or delete it.',
      demoSwipe: true,
    ),
    CoachStepSpec(
      target: CoachTarget.swipeCard,
      title: 'Mark attendance',
      body: 'Tap a class to mark it as done, skipped, or cancelled.',
    ),
    CoachStepSpec(
      target: CoachTarget.fab,
      title: 'Add classes',
      body:
          'Tap here to add a class manually or scan a timetable from a photo or PDF.',
    ),
    CoachStepSpec(
      target: CoachTarget.nav,
      title: 'Navigate around',
      body:
          'Use the Week tab to see your schedule and Settings for reminders and backup.',
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
    this.demoSwipe = false,
    this.kicker,
  });

  final CoachTarget target;
  final String title;
  final String body;

  /// Small-caps chip label replacing "STEP n OF m" for custom coaches. Null
  /// keeps the tour's step counter.
  final String? kicker;

  /// Holds the first class card's swipe plane open while this step is active.
  final bool demoSwipe;
}

/// Which pieces of the app the tour can spotlight.
enum CoachTarget { hero, swipeCard, fab, nav, tiles }

/// Anchors for the overlay: keys attached to the hero, the first class card,
/// the quick-actions button, the bottom navigation bar and — for the
/// empty-schedule coach — the first-run Scan/Add tiles.
class CoachTargetKeys {
  CoachTargetKeys({
    required this.heroKey,
    required this.swipeTargetKey,
    required this.fabKey,
    required this.navKey,
    required this.tilesKey,
  });

  /// Single-step coaches, where every anchor except [tilesKey] is dead
  /// weight: dummies stand in so the full-tour callers stay compile-checked.
  factory CoachTargetKeys.single(GlobalKey tilesKey) => CoachTargetKeys(
    heroKey: GlobalKey(debugLabel: 'tour-unused-hero'),
    swipeTargetKey: GlobalKey(debugLabel: 'tour-unused-swipe'),
    fabKey: GlobalKey(debugLabel: 'tour-unused-fab'),
    navKey: GlobalKey(debugLabel: 'tour-unused-nav'),
    tilesKey: tilesKey,
  );

  final GlobalKey heroKey;
  final GlobalKey swipeTargetKey;
  final GlobalKey fabKey;
  final GlobalKey navKey;
  final GlobalKey tilesKey;

  static const double _heroRadius = 28;
  static const double _cardRadius = 22;

  /// Mock 04 FAB step: the ring is a rounded square (r22) hugging the FAB's
  /// exact bounds — not a circle.
  static const double _fabRadius = 22;
  static const double _navRadius = 24;
  static const double _tilesRadius = 20;

  static const double _pad = 6;
  static const double _fabPad = 0;

  GlobalKey _keyOf(CoachTarget target) => switch (target) {
    CoachTarget.hero => heroKey,
    CoachTarget.swipeCard => swipeTargetKey,
    CoachTarget.fab => fabKey,
    CoachTarget.nav => navKey,
    CoachTarget.tiles => tilesKey,
  };

  double _radiusOf(CoachTarget target) => switch (target) {
    CoachTarget.hero => _heroRadius,
    CoachTarget.swipeCard => _cardRadius,
    CoachTarget.fab => _fabRadius,
    CoachTarget.nav => _navRadius,
    CoachTarget.tiles => _tilesRadius,
  };

  /// Global rect of a target, expanded [ _pad] px like the mocks. Null when
  /// the target isn't currently on screen (no next class yet, no classes
  /// today, desktop layout).
  ({Rect rect, double radius})? locate(CoachTarget target) {
    final context = _keyOf(target).currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final pad = target == CoachTarget.fab ? _fabPad : _pad;
    return (
      rect: (box.localToGlobal(Offset.zero) & box.size).inflate(pad),
      radius: _radiusOf(target),
    );
  }
}

class _CoachTourOverlayState extends State<CoachTourOverlay>
    with TickerProviderStateMixin {
  static const _tipSideGap = 20;

  /// How long a target may take to appear before its step is dropped, in
  /// frames. The replay path mounts the tour in the same frame it switches to
  /// Today, so the anchors arrive only after the first database load.
  static const int mountFrameBudget = 120;

  int _pruneFramesLeft = mountFrameBudget;

  /// Mock spacing between spotlight and tooltip (mock 04: 16px on every step).
  static const _holeGap = 16;

  late final List<CoachStepSpec> _steps;
  int _stepIndex = 0;
  CoachStepSpec? _reportedStep;

  /// The tooltip's step transition. Longer than the app's control motion:
  /// the card is the only thing on screen and the eye is following it across
  /// a context switch, not waiting on a button press.
  static const Duration _stepTransition = Duration(milliseconds: 320);

  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: _stepTransition,
  );

  final GlobalKey _tipKey = GlobalKey();

  // Resolved geometry for the current step; refreshed post-frame.
  Rect? _hole;
  double _radius = 22;
  bool _tipBelow = true;
  double _tipLeft = _tipSideGap.toDouble();
  double _tipWidth = 350;
  double? _tipTop;
  double? _tipBottom;
  double _caretX = 48;

  @override
  void initState() {
    super.initState();
    _steps = List.of(widget.steps ?? CoachTourOverlay.tourSteps);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneUnavailableLeadingSteps();
      _measure();
      _watchTarget();
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

  /// Reports the currently spotlighted step once per transition, so two
  /// consecutive steps on the same target still update the staged demo.
  void _reportStep(CoachStepSpec step) {
    if (identical(_reportedStep, step)) return;
    _reportedStep = step;
    widget.onTargetActive?.call(step);
  }

  /// Steps whose target isn't on screen don't exist for this tour; with the
  /// overlay freshly mounted the anchors may need a frame, so this only ever
  /// runs post-frame. Mounting may span a navigation transition *and* the
  /// host's first data load — the replay path lands on Today while the list
  /// is still a skeleton, so the hero and card anchors appear well after the
  /// first frame. Waiting only a few frames used to drop the first three
  /// steps for good; the pruner now holds the tour for up to
  /// [mountFrameBudget] frames (about two seconds) before deciding a target
  /// is genuinely absent.
  void _pruneUnavailableLeadingSteps() {
    if (!mounted) return;
    while (_steps.isNotEmpty &&
        widget.keys.locate(_steps.first.target) == null) {
      if (_pruneFramesLeft > 0) {
        _pruneFramesLeft--;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _pruneUnavailableLeadingSteps(),
        );
        // A bare post-frame callback doesn't keep frames coming; without
        // this the wait would stall wherever nothing else is animating.
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      setState(() => _steps.removeAt(0));
    }
    _pruneFramesLeft = mountFrameBudget;
    if (_steps.isEmpty) widget.onDone();
  }

  void _goTo(int index) {
    if (index >= _steps.length) {
      widget.onDone();
      return;
    }
    // Steps whose target isn't on screen can't be shown: a class added for
    // another day has no Today card to swipe, and the desktop shell has no
    // tab bar to spotlight. Skip ahead so the tooltip never describes a
    // control that isn't there while the hole lingers on the old target.
    var next = index;
    while (next < _steps.length &&
        widget.keys.locate(_steps[next].target) == null) {
      next++;
    }
    if (next >= _steps.length) {
      widget.onDone();
      return;
    }
    setState(() => _stepIndex = next);
    _measureAttempts = 0;
    _measure();
    // The synchronous pass above still sees the outgoing tooltip when it
    // reads the tip height, so the below/above call for the new step is made
    // again after the rebuild — with the new copy's real height — and the
    // target watch takes over for anything that moves after that.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    _watchTarget();
    if (!MediaQuery.of(context).disableAnimations) {
      _entry.forward(from: 0);
    } else {
      _entry.value = 1;
    }
  }

  int _measureAttempts = 0;

  /// Recomputes hole and tooltip geometry from the target's current box.
  ///
  /// Runs post-frame: the first pass renders the tooltip with a height
  /// estimate so the second pass can decide below/above with the real size.
  void _measure() {
    if (!mounted || _steps.isEmpty) {
      // The pruner emptied the tour while this callback was queued: draw
      // nothing more, the overlay is on its way out.
      return;
    }
    final screen = MediaQuery.sizeOf(context);
    final located = widget.keys.locate(_current.target);
    if (located == null) {
      // Target may not be laid out yet: the replay path mounts over a Today
      // that is still loading, and a first class added from the sheet lays
      // out a frame later. Hold the step for the mount budget before
      // dropping it.
      if (_measureAttempts < mountFrameBudget) {
        _measureAttempts++;
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      _measureAttempts = 0;
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
    _measureAttempts = 0;
    final hole = located.rect;
    _reportStep(_current);
    // Mock 04's last step narrows the tooltip over the bottom bar to 290;
    // every other step runs the full 350 card.
    final maxTipWidth = _current.target == CoachTarget.nav ? 290.0 : 350.0;
    final maxWidth = (screen.width - 2 * _tipSideGap).clamp(0.0, maxTipWidth);
    // Mock 04 anchors every tooltip at left:20, including the narrower
    // bottom-bar step (a centered 290 card would sit at 50).
    final tipLeft = _tipSideGap.toDouble();
    // The tooltip's real height once laid out; before that, the mock's
    // four-row card is around 210-240px tall.
    final tipBox = _tipKey.currentContext?.findRenderObject() as RenderBox?;
    final tipHeight = tipBox?.size.height ?? 216;
    // The mock 04 placement is per target, not per screen position: the
    // hero's tooltip hangs below it, every lower target's flips above. Fit
    // fallbacks cover cramped screens.
    final fitsBelow = hole.bottom + _holeGap + tipHeight <= screen.height - 8;
    final fitsAbove = hole.top - _holeGap - tipHeight >= 8;
    final spaceBelow = screen.height - 8 - (hole.bottom + _holeGap);
    final spaceAbove = (hole.top - _holeGap) - 8;
    final below =
        _current.target == CoachTarget.hero
            ? (fitsBelow || !fitsAbove)
            : _current.target == CoachTarget.tiles
            ? true
            : (!fitsAbove && fitsBelow) ||
                (!fitsAbove && !fitsBelow && spaceBelow >= spaceAbove);

    final next = (
      hole: hole,
      radius: located.radius,
      tipBelow: below,
      tipLeft: tipLeft,
      tipWidth: maxWidth,
      tipTop: below
          ? (hole.bottom + _holeGap).clamp(8.0, screen.height - tipHeight - 8.0)
          : null,
      tipBottom: below
          ? null
          : (screen.height - hole.top + _holeGap).clamp(8.0, screen.height - tipHeight - 8.0),
      // Center the caret's base on the target, then keep it clear of the
      // card's 20px corners so it never rides the radius.
      caretX:
          (hole.center.dx - tipLeft - _Caret.width / 2)
              .clamp(16.0, maxWidth - _Caret.width - 16.0)
              .toDouble(),
      tipHeight: tipHeight,
    );
    if (next == _lastGeometry) return;
    _lastGeometry = next;
    setState(() {
      _hole = next.hole;
      _radius = next.radius;
      _tipBelow = next.tipBelow;
      _tipLeft = next.tipLeft;
      _tipWidth = next.tipWidth;
      _tipTop = next.tipTop;
      _tipBottom = next.tipBottom;
      _caretX = next.caretX;
    });
  }

  /// Targets move under a stationary overlay: the hero swaps from its empty
  /// state when the schedule finishes loading, and a step change lays fresh
  /// targets out a frame after the copy swaps. For a short stretch of real
  /// frames after mount and after every step change, chase the target box;
  /// `_measure` only rebuilds when something actually moved, and the chain
  /// ends after its frame budget without ever scheduling frames itself —
  /// an idle tour costs nothing.
  static const int _watchFrameBudget = 120;
  int _watchFramesLeft = 0;
  bool _watchArmed = false;

  void _watchTarget() {
    _watchFramesLeft = _watchFrameBudget;
    if (_watchArmed) return;
    _watchArmed = true;
    WidgetsBinding.instance.addPostFrameCallback(_watchTick);
  }

  void _watchTick(Duration _) {
    _watchArmed = false;
    if (!mounted || _steps.isEmpty || _watchFramesLeft <= 0) return;
    _watchFramesLeft--;
    _measure();
    _watchArmed = true;
    WidgetsBinding.instance.addPostFrameCallback(_watchTick);
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
    double tipHeight,
  })?
  _lastGeometry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // After the pruner retires the last step (and until the caller's
    // rebuild) the tooltip would index an empty list — render nothing.
    if (_steps.isEmpty) return const SizedBox.expand();

    // Android slop test: the system Back gesture steers the tour — it
    // advances the tooltip like a tap would and finishes on the last step —
    // instead of leaving the screen under it.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _goTo(_stepIndex + 1);
      },
      child: Material(
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
                // Pure paint: default CustomPainter.hitTest is "true", which
                // would make this full-screen veil eat every outside tap and
                // dead-end both tap-to-advance and tap-to-dismiss.
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SpotlightPainter(hole: _hole, radius: _radius),
                  ),
                ),
              ),
            ),
            if (_hole != null) _tooltip(scheme, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _tooltip(ColorScheme scheme, TextTheme textTheme) {
    final dark = scheme.brightness == Brightness.dark;
    final tip = DecoratedBox(
      key: _tipKey,
      decoration: BoxDecoration(
        // Light mode: the mock's white card over the veil. Dark mode: the
        // surface token is pure black and would melt into the veil, so the
        // card lifts with surfaceContainerHigh instead.
        color: dark ? scheme.surfaceContainerHigh : scheme.surface,
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
        // The mock tooltip: 16px vertical, 18px horizontal.
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Elastic header: the pill yields before "Skip tour" clips.
                // Widget tests (and any device that substitutes a wider
                // system font) lay the kicker out far wider than Roboto does;
                // with flex 1000 the pill is sized to its natural width when
                // the row fits and only donates width under real pressure,
                // so the Spacer stays a pure gap-ender on the reference font.
                Flexible(
                  flex: 1000,
                  fit: FlexFit.loose,
                  child: Container(
                    // Symmetric padding, not a fixed height: the mock pill is
                    // 26px (13.2px text line + 6.4+6.4), and at larger text
                    // scales the pill grows instead of clipping the kicker.
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6.4,
                    ),
                    decoration: BoxDecoration(
                      // One notch above the card: surfaceContainerHigh on the
                      // light card; surfaceContainer on the lifted dark card.
                      color:
                          dark ? scheme.surfaceContainer : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(99),
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
                        // Same elasticity one level down: when the pill
                        // itself was squeezed by the header row, the kicker
                        // text gives back width before the pill overflows.
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            _current.kicker ??
                                'STEP ${_stepIndex + 1} OF ${_steps.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              // Mock kicker: 0.12em at 11px = 1.32.
                              letterSpacing: 1.32,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Single-step coaches dismiss outright; only the multi-step
                // tour has anything to skip out of.
                _TourTextButton(
                  label: _steps.length == 1 ? 'Dismiss' : 'Skip tour',
                  onTap: widget.onDone,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _current.title,
              style: textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontSize: 20,
                height: 26 / 20,
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
                fontWeight: FontWeight.w400,
              ),
            ),
            // A one-step coach has nothing between steps, so the sandbox
            // of dots would read as noise; the full tour keeps them.
            if (_steps.length > 1) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  // Raw dots like the mocks: the active step stretches to a
                  // 22×6 bar, the rest sit as 6×6 pips — no chip wrapper.
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                                  : AppTheme.disabledSecondaryForegroundFor(
                                      scheme,
                                    ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  _CtaButton(
                    label: _stepIndex == _steps.length - 1 ? 'Got it' : 'Next',
                    onTap: () => _goTo(_stepIndex + 1),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              // Same alignment as the multi-step row: CTA hugs the edge.
              Align(
                alignment: Alignment.centerRight,
                child: _CtaButton(
                  label: 'Got it',
                  onTap: () => _goTo(_stepIndex + 1),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // The card arrives from the spotlight's side — down from above when the
    // tip hangs below the target, up from below when it flips. A 12px travel
    // is enough to read as "this card belongs to that hole" without turning
    // a tap into a wait. Opacity lands early; the slide carries the rest.
    final fade = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0, 0.7, curve: Curves.easeOut),
    );
    final slide = Tween<double>(begin: _tipBelow ? -12.0 : 12.0, end: 0)
        .animate(
          CurvedAnimation(parent: _entry, curve: AppTheme.motionEaseOut),
        );

    final entrance = FadeTransition(
      opacity: fade,
      child: AnimatedBuilder(
        animation: slide,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, slide.value), child: child),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(decoration: const BoxDecoration(), child: tip),
            if (_tipBelow)
              Positioned(
                top: -(_Caret.height - _Caret.tuck),
                left: _caretX,
                child: _Caret(
                  color: dark ? scheme.surfaceContainerHigh : scheme.surface,
                  above: true,
                ),
              )
            else
              Positioned(
                bottom: -(_Caret.height - _Caret.tuck),
                left: _caretX,
                child: _Caret(
                  color: dark ? scheme.surfaceContainerHigh : scheme.surface,
                  above: false,
                ),
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
    // The mock veil: 66% black, with a crisp 2px ring tracing the hole.
    canvas.drawPath(path, Paint()..color = const Color(0xA8000000));
    // The white ring dissolves into white page content (every light-mode
    // surface here). A hairline just inside it gives the cutout a drawn
    // edge there and disappears against dark content.
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole!.deflate(1), Radius.circular(radius - 1)),
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
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

/// The pointer leaning on the tooltip edge.
///
/// Drawn as an explicit triangle instead of a rotated square: rotating put
/// the rounded corner on a shoulder rather than the point, and the diamond's
/// sharp apex read as a splinter at 3x. The base sits [tuck] inside the card
/// so no hairline can open between the two fills at fractional device
/// pixel ratios.
class _Caret extends StatelessWidget {
  const _Caret({required this.color, required this.above});

  static const double width = 20;
  static const double height = 10;
  static const double tuck = 1;

  /// Caret sits above the card, pointing up at a target above it.
  final bool above;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(width, height),
      painter: _CaretPainter(color: color, above: above),
    );
  }
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter({required this.color, required this.above});

  final Color color;
  final bool above;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final baseY = above ? h : 0.0;
    final apexY = above ? 0.0 : h;
    // The point is a shallow curve, not a spike: 2.6px of rounding on a 90°
    // apex matches the card's own softness and survives a 3x screenshot.
    final shoulderY = above ? 2.6 : h - 2.6;
    const shoulderInset = 1.7;
    final path =
        Path()
          ..moveTo(0, baseY)
          ..lineTo(w / 2 - shoulderInset, shoulderY)
          ..quadraticBezierTo(w / 2, apexY, w / 2 + shoulderInset, shoulderY)
          ..lineTo(w, baseY)
          ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.above != above;
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

/// The filled pill: "Next" until the last step, then "Got it". Presses sink
/// the pill 3% for hand-sized confirmation — this is the tour's one moving
/// control, so each tap deserves to feel taken.
class _CtaButton extends StatefulWidget {
  const _CtaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return Semantics(
      button: true,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : AppTheme.motionFast,
          curve: AppTheme.motionEaseOut,
          child: Material(
            color: scheme.primary,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              customBorder: shape,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                alignment: Alignment.center,
                child: Text(
                  widget.label,
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
        ),
      ),
    );
  }
}
