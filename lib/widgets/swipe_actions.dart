import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Trailing swipe actions for a class card, mirroring the swipe-mockup
/// behavior end to end: drag the card left and the Edit -> Delete plane
/// stays attached to its trailing edge and travels with it.
///
/// Gesture contract (from the mockup's JS):
/// - Inside the plane the drag is 1:1; past it the overshoot is rubber-banded.
/// - A release past half the plane — or a fast leftward fling from anywhere —
///   snaps the plane open; anything gentler closes it.
/// - Tapping a plane action fires it and closes; tapping the card while open
///   just closes.
/// - A release past the full-swipe point (1.15 planes) deletes: card and
///   plane fly off together (viewport-relative, so wide rows still exit),
///   then the row's footprint collapses so the rows below glide up, then
///   [onDelete] runs — [deleteClassWithUndo] at the call sites, which shows
///   the 5-second undo snackbar. A `false` result (failed delete) brings the
///   row back closed and full height.
/// - Dragging right when closed is locked; dragging right when open closes.
///
/// Visual contract (from the v5 mockup's swipe frame):
/// - Both actions are 44px-wide, full-height, icon-only pills clipped to
///   their own 16px rounding on all four corners. The card narrows while
///   keeping its uniform rounding — nothing squares off.
/// - The opened composition reads `[card][8px gap][Edit][4px gap][Delete]`,
///   so a single plane equals 100px of card shift and Delete's edge ends
///   flush at the row's right boundary.
/// - Colors come from the scheme: Edit is `primaryContainer/onPrimary`
///   (grey pill, black icon), Delete is `error/onError` (red pill, white
///   icon), each with a bare 20px icon that grows in with the reveal
///   (scale 0.6 -> 1.0, opacity 0 -> 1); there is no text label — the
///   semantics labels carry the "Edit class" / "Delete class" names.
/// - Past the full-swipe point Edit collapses to zero width and Delete
///   takes the freed space (widening to two extents) as the delete arm.
///
/// Motion rules: everything animates `transform` (and one layout collapse),
/// honors reduced motion (durations collapse to zero via
/// [AppTheme.motionDuration], so opens and closes jump), and fires a light
/// haptic when the snap threshold is crossed and a medium one when the
/// delete threshold arms — once per drag, reset on every drag start.
///
/// The plane actions carry their own semantics labels while revealed; the
/// one-time coach tour (replayable from Settings) teaches the swipe gesture.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    this.onEdit,
    this.onDelete,
    this.onSwipe,
    this.padding = EdgeInsets.zero,
    this.forceOpen = false,
    this.radius,
    this.borderRadius,
    this.targetKey,
  });

  final Widget child;

  /// Runs when the plane's Edit button is tapped. Null hides the Edit action.
  final VoidCallback? onEdit;

  /// Runs after the fly-off and row collapse complete. Returns whether the
  /// delete actually happened: `false` (failed delete) restores the row,
  /// closed and full height. The call sites use [deleteClassWithUndo], so
  /// the 5-second undo snackbar still appears.
  final Future<bool> Function()? onDelete;

  /// Runs after any completed swipe, meaningful or not. The Today screen
  /// uses this to retire the one-time swipe coach hint.
  final VoidCallback? onSwipe;

  /// Outer padding: holds the page inset and the inter-card gap at the call
  /// sites, so the action plane lines up with the card exactly. Collapses
  /// together with the row on delete.
  final EdgeInsetsGeometry padding;

  /// Holds the plane open for a demonstration (the coach tour), snapping it
  /// back open on every release. The card behind stays inert and can never
  /// arm or delete.
  final bool forceOpen;

  /// Corner radius of the row clip. Defaults to [AppTheme.cardRadius];
  /// set it when the wrapped card carries its own larger shape (the hero's
  /// 28px corners). The action pills always round themselves to 16px, so
  /// this only shapes the row edges.
  final double? radius;

  /// Full corner shape of the row clip, for rows whose corners are not
  /// uniform - the weekly schedule's segmented rows carry 16px group
  /// corners with 2px meeting edges ([AppTheme.segmentRadiusOf]). Wins
  /// over [radius] when both are set.
  final BorderRadius? borderRadius;

  /// Anchor for callouts that need the row's content box — the card slot,
  /// page insets excluded. Sits on the row clip, whose box neither includes
  /// [padding] nor moves with the swipe, so a spotlight stays on the card's
  /// resting place while the card travels in and out of it.
  final Key? targetKey;

  /// Width of one action pill (the mockup's 44px buttons).
  static const double actionExtent = 44;

  /// Gap between the card and the Edit pill (the mockup's 8px leading gap).
  static const double _actionGapEdge = 8;

  /// Gap between the Edit and Delete pills (the mockup's 4px inner gap).
  static const double _actionGapInner = 4;

  /// The plane opens to this width: two 44px pills plus the gaps.
  static const double planeWidth =
      _actionGapEdge + actionExtent + _actionGapInner + actionExtent;

  /// Fraction of the plane past which a release counts as a full swipe.
  static const double _fullSwipeFactor = 1.15;

  /// Fling velocity (px/s leftward) that snaps the plane open even from a
  /// short drag — the mockup's FLING rule. Flinging never deletes on its
  /// own; only crossing the full-swipe point does.
  static const double _flingOpenVelocity = -900;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with TickerProviderStateMixin {
  // Controller value 0 = closed, 1 = plane fully open, >1 = overshoot during
  // a drag (up to 2 by the rubber band) or the delete fly-off (up to the
  // viewport-relative target). The generous upper bound covers tablets,
  // whose rows need more than 3.2 planes to fully exit.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppTheme.motionPage,
    upperBound: 12,
  );

  // 1 = full row height; 0 = collapsed after the fly-off (the mockup's
  // height collapse that lets the rows below glide up).
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: AppTheme.motionPage,
    value: 1,
  );

  // The row (card) width, measured every layout. The fly-off distance is
  // viewport-relative, like the mockup's render(W + PLANE, ...).
  double _rowWidth = 0;

  // Fly-off target in controller units: enough translation for the card and
  // plane to fully exit the row.
  double get _flyOffTarget =>
      ((_rowWidth + SwipeActions.planeWidth) / SwipeActions.planeWidth).clamp(
        1.0,
        _controller.upperBound,
      );

  bool get _revealed => _controller.value > 0.02;
  bool get _opened => _controller.value >= 0.95;

  // The clips (row + card squaring) only run while the plane is revealed.
  // Closed, the card keeps its own shape and — for the hero — its ambient
  // shadow renders untouched; the plane hides via its reveal fade instead.
  Clip get _rowClip => _revealed ? Clip.antiAlias : Clip.none;

  // Current card translation in px: 0 closed, -100 at one full plane.
  double get _translate => -_controller.value * SwipeActions.planeWidth;

  bool _snapHapticFired = false;
  bool _deleteArmed = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen) {
      // The card can be mounted already on its demo step. Let the first frame
      // lay the row out, then rehearse the gesture there too instead of
      // snapping open before it was ever visible.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.forceOpen) _playSwipeDemo();
      });
    }
  }

  @override
  void didUpdateWidget(covariant SwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A demonstration starting later (the tour reaching this card) opens the
    // plane in motion; the tour moving on releases the hold and closes it in
    // motion too, so the demonstration both starts and ends animated.
    if (widget.forceOpen && !oldWidget.forceOpen && _controller.value < 0.95) {
      _playSwipeDemo();
    } else if (!widget.forceOpen && oldWidget.forceOpen && _revealed) {
      _demoToken++;
      _animateTo(0.0);
    }
    // The list reused this slot while the row was collapsed (a delete just
    // handed the element to the next class): come back pristine before the
    // new card is seen.
    if (_collapse.value == 0) {
      _collapse.value = 1;
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _collapse.dispose();
    super.dispose();
  }

  Future<void> _animateTo(
    double target, {
    Curve curve = AppTheme.motionEaseOut,
  }) {
    // Reduced motion: duration collapses to zero, so this jumps.
    _controller.duration = AppTheme.motionDuration(
      context,
      AppTheme.motionPage,
    );
    // A held-open demonstration always returns to fully open.
    final clamped = widget.forceOpen
        ? 1.0
        : target.clamp(0.0, _controller.upperBound).toDouble();
    return _controller.animateTo(clamped, curve: curve);
  }

  // The tour's swipe demonstration: a short rehearsal of the gesture, then
  // the settled state. Any release, new demonstration, or real drag bumps
  // the token so an in-flight beat can't fight the newer intent.
  int _demoToken = 0;

  void _playSwipeDemo() {
    final token = ++_demoToken;
    // Reduced motion shows the result, not the motion.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
      return;
    }
    unawaited(_runSwipeDemo(token));
  }

  Future<void> _runSwipeDemo(int token) async {
    bool live() => mounted && token == _demoToken && widget.forceOpen;

    // Let the tour's tooltip land before the card moves: two entrances on the
    // same frame read as one blur, and the gesture is the thing to follow.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!live()) return;

    // Beat 1: the finger starts left, revealing the plane. Slower than a real
    // swipe: this is a demonstration, and the eye has to read the reveal.
    _controller.duration = const Duration(milliseconds: 300);
    await _controller.animateTo(0.26, curve: Curves.easeInOutCubic);
    if (!live()) return;

    // Hold the plane open. Without this pause the reveal is a flicker.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!live()) return;

    // Beat 2: released short of the snap — the row comes back.
    _controller.duration = const Duration(milliseconds: 320);
    await _controller.animateTo(0, curve: Curves.easeInOutCubic);
    if (!live()) return;

    // A breath at rest so the cancel reads as "didn't take", not a stutter.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!live()) return;

    // Beat 3: the real swipe lands and the plane settles open — long and
    // deliberate, because this is the beat the step is explaining.
    _controller.duration = const Duration(milliseconds: 620);
    await _controller.animateTo(1, curve: AppTheme.motionEaseOut);
    _controller.duration = AppTheme.motionPage;
  }

  /// Rubber band: inside the plane the drag is 1:1; past it, each extra
  /// pixel fights increasing resistance (asymptote at one extra plane).
  double _translateFor(double raw) {
    if (raw > 0) return 0;
    if (raw >= -SwipeActions.planeWidth) return raw;
    final excess = -raw - SwipeActions.planeWidth;
    final damped = excess / (1 + excess / SwipeActions.planeWidth);
    return -(SwipeActions.planeWidth + damped);
  }

  void _onDragStart(DragStartDetails details) {
    // A real drag takes over from the tour's rehearsal immediately.
    _demoToken++;
    // Haptics re-arm every drag, like the mockup's per-pointerdown reset.
    _snapHapticFired = false;
    _deleteArmed = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final raw = _translate + details.delta.dx;
    _controller.value = (-_translateFor(raw)) / SwipeActions.planeWidth;
    _hapticOnCross(raw);
  }

  void _hapticOnCross(double raw) {
    if (!_snapHapticFired && raw <= -SwipeActions.planeWidth * 0.5) {
      _snapHapticFired = true;
      HapticFeedback.lightImpact();
    }
    if (!_deleteArmed &&
        raw <= -SwipeActions.planeWidth * SwipeActions._fullSwipeFactor) {
      _deleteArmed = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final value = _controller.value;
    final fling = details.velocity.pixelsPerSecond.dx;
    if (value > 0.15) widget.onSwipe?.call();
    if (value >= SwipeActions._fullSwipeFactor &&
        !widget.forceOpen &&
        widget.onDelete != null) {
      _runDelete();
      return;
    }
    // The mockup's release rule: past halfway, or a fast leftward fling
    // from anywhere, snaps open; anything else closes.
    if (value >= 0.5 || fling < SwipeActions._flingOpenVelocity) {
      _animateTo(1.0);
    } else {
      _animateTo(0.0);
    }
  }

  Future<void> _runDelete() async {
    HapticFeedback.mediumImpact();
    // Capture the motion durations before the first await (context reads
    // across async gaps are a lint, and there's no rebuild between here and
    // the collapse, so hoisting changes nothing).
    final collapseDuration = AppTheme.motionDuration(
      context,
      AppTheme.motionStandard,
    );
    // 1. Card and plane fly off together, viewport-relative so wide rows
    //    still fully exit (the mockup's render(W + PLANE, ...)).
    await _animateTo(_flyOffTarget, curve: AppTheme.motionEaseOut);
    // 2. The row's footprint collapses so the rows below glide up (the
    //    mockup's height collapse). The padding — including the inter-card
    //    gap — collapses with it.
    _collapse.duration = collapseDuration;
    await _collapse.animateTo(0.0, curve: AppTheme.motionEaseOut);
    // 3. Hand over: the call site deletes (the 5-second undo snackbar
    //    shows) and the list rebuild drops the row.
    final deleted = await widget.onDelete?.call() ?? false;
    // 4. A failed delete brings the row back, closed and full height. On
    //    success the rebuild disposes this state before anything else is
    //    needed; a reused slot is reset in didUpdateWidget.
    if (!deleted && mounted) {
      _collapse.value = 1;
      _controller.value = 0;
    }
  }

  void _close() => _animateTo(0.0);

  void _runEdit() {
    _animateTo(0.0);
    widget.onEdit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shapeRadius = widget.borderRadius ??
        BorderRadius.circular(widget.radius ?? AppTheme.cardRadius);
    return Padding(
      padding: widget.padding,
      child: SizeTransition(
        sizeFactor: _collapse,
        // Same alignment the deprecated axisAlignment: -1 produced for a
        // vertical axis: AlignmentDirectional(-1.0, -1.0).
        alignment: AlignmentDirectional.topStart,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _rowWidth = constraints.maxWidth;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, card) {
                final value = _controller.value;
                // Reveal progress (0..1): drives icon scale + opacity and
                // the card's corner squaring. Past the open position the
                // icons stay fully grown — the value then only feeds the
                // armed state below.
                final reveal = value.clamp(0.0, 1.0);
                // Armed progress (0..1) across the 1.0..1.15 band: collapses
                // Edit to zero width and lets Delete take the full plane,
                // matching the mockup's `flex-basis` tween past the
                // full-swipe point.
                final armed = ((value - 1.0) / 0.15).clamp(0.0, 1.0);
                return ClipRRect(
                  key: widget.targetKey,
                  // The row clip (`.swipe { overflow: hidden;
                  // border-radius }`): hides the plane while it travels in
                  // and rounds whatever is visible at the row edges. Off at
                  // rest so the card's own shadow renders unclipped.
                  clipBehavior: _rowClip,
                  borderRadius: shapeRadius,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        // The plane is anchored to the card's trailing edge,
                        // not to the row: its right inset grows with the
                        // translation, so it travels with the card at the
                        // same speed. Closed (value 0) it sits entirely past
                        // the trailing edge, clipped away; armed (value >
                        // 1) it has slid inside the row, exposing background
                        // to its right.
                        top: 0,
                        bottom: 0,
                        right: (value - 1) * SwipeActions.planeWidth,
                        width: SwipeActions.planeWidth,
                        child: ExcludeSemantics(
                          // The plane is only real to screen readers while
                          // revealed; closed, the card covers it and the ⋮
                          // menu carries the same actions.
                          excluding: !_revealed,
                          // The reveal fade hides the plane surface while the
                          // row clip is off (closed and the first 2% of the
                          // drag), so no action color leaks past the row.
                          child: Opacity(
                            opacity: reveal,
                            child: IgnorePointer(
                              ignoring: !_revealed,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // The mockup's gaps: 8px between the card
                                  // and Edit, 4px between the pills. Both
                                  // stay fixed, so the armed composition
                                  // keeps its spacing while Delete absorbs
                                  // Edit's width.
                                  const SizedBox(
                                    width: SwipeActions._actionGapEdge,
                                  ),
                                  SizedBox(
                                    width:
                                        SwipeActions.actionExtent * (1 - armed),
                                    child: _ActionPlane(
                                      icon: Icons.edit_outlined,
                                      label: 'Edit class',
                                      reveal: reveal,
                                      background: scheme.primaryContainer,
                                      foreground: scheme.onPrimaryContainer,
                                      onTap: widget.onEdit == null
                                          ? null
                                          : _runEdit,
                                    ),
                                  ),
                                  const SizedBox(
                                    width: SwipeActions._actionGapInner,
                                  ),
                                  SizedBox(
                                    width:
                                        SwipeActions.actionExtent * (1 + armed),
                                    child: _ActionPlane(
                                      icon: Icons.delete_outline_rounded,
                                      label: 'Delete class',
                                      reveal: reveal,
                                      background: scheme.error,
                                      foreground: scheme.onError,
                                      onTap: widget.onDelete == null
                                          ? null
                                          : _runDelete,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(-value * SwipeActions.planeWidth, 0),
                        child: GestureDetector(
                          // While the plane is open a tap on the card closes
                          // it instead of falling through to the card's own
                          // handler. Opaque, because with the card under
                          // IgnorePointer a deferToChild detector would
                          // never see the tap at all.
                          behavior: HitTestBehavior.opaque,
                          onTap: _opened ? _close : null,
                          onHorizontalDragStart: _onDragStart,
                          onHorizontalDragUpdate: _onDragUpdate,
                          onHorizontalDragEnd: _onDragEnd,
                          child: IgnorePointer(
                            // The card keeps its own shadow and uniform
                            // rounding at every drag position — the mockup
                            // narrows it without squaring the corners.
                            ignoring: _opened || widget.forceOpen,
                            child: card,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}

/// One full-height icon-only action pill behind the card.
///
/// Mirrors the v5 mockup's plane button: a 44px-wide, full-height pill
/// clipped to its own 16px rounding on all four corners, showing a bare
/// 20px icon — the mockup carries no text label, the [Semantics] label
/// carries the "Edit class" / "Delete class" name. The icon scales in with
/// the reveal (0.6 -> 1.0) and fades in (0 -> 1), so it grows with the plane
/// instead of sitting still.
class _ActionPlane extends StatelessWidget {
  const _ActionPlane({
    required this.icon,
    required this.label,
    required this.reveal,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;

  /// Screen-reader name for the pill (the mockup's aria-label).
  final String label;

  /// 0..1 reveal of the plane: drives icon scale (0.6 -> 1.0) and opacity
  /// (0 -> 1). Past the open position the icons stay fully grown.
  final double reveal;

  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: ClipRRect(
          // The pill rounds all four corners itself (the mockup's
          // border-radius: 16px) instead of relying on the row's clip.
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: background,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Opacity(
                  opacity: reveal,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * reveal,
                    child: Icon(icon, size: 20, color: foreground),
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
