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
/// Visual contract (from the mockup's CSS):
/// - The card's right corners square off as the plane reveals, so its
///   trailing edge meets the Edit button in a straight line.
/// - Delete carries its own outer rounding, so it stays rounded once armed
///   and its right edge is no longer at the row's clipped boundary — the
///   armed composition is `[card][Delete][gap]`.
/// - Icons grow in with the reveal (scale 0.6 -> 1.0, opacity 0 -> 1) above
///   a 12px/600 label; past the full-swipe point Edit collapses to zero
///   width, Delete takes the whole plane, and its label swaps to "Release".
///
/// Motion rules: everything animates `transform` (and one layout collapse),
/// honors reduced motion (durations collapse to zero via
/// [AppTheme.motionDuration], so opens and closes jump), and fires a light
/// haptic when the snap threshold is crossed and a medium one when the
/// delete threshold arms — once per drag, reset on every drag start.
///
/// Fallbacks stay: the card's ⋮ menu keeps Edit/Delete for people who don't
/// discover the gesture, and the plane actions carry their own semantics
/// labels while revealed.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    this.onEdit,
    this.onDelete,
    this.onSwipe,
    this.padding = EdgeInsets.zero,
    this.forceOpen = false,
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

  /// Width of one action; the whole plane is two actions wide.
  static const double actionExtent = 72;

  /// The plane opens to this width.
  static const double planeWidth = actionExtent * 2;

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

  // Current card translation in px: 0 closed, -144 at one full plane.
  double get _translate => -_controller.value * SwipeActions.planeWidth;

  bool _snapHapticFired = false;
  bool _deleteArmed = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant SwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A demonstration starting later (the tour reaching this card) opens the
    // plane in motion; one ending leaves the snap to the animator below.
    if (widget.forceOpen && !oldWidget.forceOpen && _controller.value < 0.95) {
      _animateTo(1.0);
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
    // 1. Card and plane fly off together, viewport-relative so wide rows
    //    still fully exit (the mockup's render(W + PLANE, ...)).
    await _animateTo(_flyOffTarget, curve: Curves.easeIn);
    // 2. The row's footprint collapses so the rows below glide up (the
    //    mockup's height collapse). The padding — including the inter-card
    //    gap — collapses with it.
    _collapse.duration = AppTheme.motionDuration(
      context,
      AppTheme.motionStandard,
    );
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
    return Padding(
      padding: widget.padding,
      child: SizeTransition(
        sizeFactor: _collapse,
        axisAlignment: -1,
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
                  // The row clip (`.swipe { overflow: hidden;
                  // border-radius }`): hides the plane until the card pulls
                  // it in and rounds whatever is visible at the row edges.
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width:
                                    SwipeActions.actionExtent * (1 - armed),
                                child: _ActionPlane(
                                  icon: Icons.edit_outlined,
                                  label: 'Edit',
                                  reveal: reveal,
                                  background: scheme.primary,
                                  foreground: scheme.onPrimary,
                                  onTap:
                                      widget.onEdit == null
                                          ? null
                                          : _runEdit,
                                ),
                              ),
                              SizedBox(
                                width:
                                    SwipeActions.actionExtent * (1 + armed),
                                child: ClipRRect(
                                  // Delete rounds its own outer edge so it
                                  // doesn't rely on the row's clip — that
                                  // edge ends up inside the row once armed.
                                  borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(
                                      AppTheme.cardRadius,
                                    ),
                                  ),
                                  child: _ActionPlane(
                                    icon: Icons.delete_outline_rounded,
                                    // Binary swap the moment the plane
                                    // crosses the full-swipe point, matching
                                    // the mockup's `.swipe.armed .del
                                    // .lbl-armed` rule.
                                    label:
                                        armed >= 1.0 ? 'Release' : 'Delete',
                                    reveal: reveal,
                                    background: scheme.error,
                                    foreground: scheme.onError,
                                    onTap:
                                        widget.onDelete == null
                                            ? null
                                            : _runDelete,
                                  ),
                                ),
                              ),
                            ],
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
                            ignoring: _opened || widget.forceOpen,
                            child: ClipRRect(
                              // The card's right corners square off as it
                              // pulls open, so its trailing edge meets the
                              // Edit button in a straight line.
                              borderRadius: BorderRadius.horizontal(
                                left: const Radius.circular(
                                  AppTheme.cardRadius,
                                ),
                                right: Radius.circular(
                                  AppTheme.cardRadius * (1 - reveal),
                                ),
                              ),
                              child: card,
                            ),
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

/// One full-height action behind the card.
///
/// Mirrors the swipe-mockup.html plane button: a column with the icon on top
/// and a 12px/600 label underneath. The icon scales in with the reveal
/// (0.6 -> 1.0) and fades in (0 -> 1), so it grows with the plane instead
/// of sitting still, and the label sits 4px below it.
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
        child: Material(
          color: background,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Opacity(
                opacity: reveal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.6 + 0.4 * reveal,
                      child: Icon(icon, size: 24, color: foreground),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
