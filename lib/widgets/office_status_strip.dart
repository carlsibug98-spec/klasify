import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/office_status.dart';
import '../theme/app_theme.dart';

/// The Today screen's campus-office strip (design C): one card, a column
/// per office — a 4px status bar over the name, the state ("Open" / "On
/// break" / "Closed") and the admin's optional note. Up to three offices
/// share the card's width exactly as in the approved v12 design.
///
/// With a fourth or later office the strip becomes a swipe pager: one
/// office per swipe, each column 2/7 of the card so half of the next office
/// peeks out, dissolved by a soft edge blur at the card's edge. Values come
/// from the local cache, so the strip keeps showing the last synced state
/// offline.
///
/// Admins get a 24px edit chip (✎) on each column; tapping opens the same
/// bottom sheet as Settings → Admin. An office whose change is still
/// syncing shows "Syncing…" in place of its note; one whose PATCH is in
/// flight is dimmed.
class OfficeStatusStrip extends StatefulWidget {
  const OfficeStatusStrip({
    super.key,
    required this.offices,
    this.isAdmin = false,
    this.pendingOffices = const {},
    this.savingOffice,
    this.onEditOffice,
  });

  final List<OfficeStatus> offices;

  /// Show edit chips and make the columns tappable.
  final bool isAdmin;

  /// Offices whose change saved on the server but has not finished syncing
  /// to this phone yet; their sub line reads "Syncing…".
  final Set<String> pendingOffices;

  /// The office whose PATCH is currently in flight; its column dims.
  final String? savingOffice;

  final ValueChanged<OfficeStatus>? onEditOffice;

  @override
  State<OfficeStatusStrip> createState() => _OfficeStatusStripState();
}

class _OfficeStatusStripState extends State<OfficeStatusStrip>
    with SingleTickerProviderStateMixin {
  /// Fixed pager tile height: 24 (top row) + 4 + 14.4 (name line) + 2 +
  /// 19.2 (state line) + 13 (sub line) + 28 (vertical padding) ≈ 104.6.
  /// The two text lines use fixed fontSize/height in the tile, so the sum
  /// is deterministic; the ≤3 row keeps IntrinsicHeight and needs no
  /// constant. (Large text scale can clip the sub line — known trade-off.)
  static const double _kPagerTileHeight = 106.0;

  double _offset = 0;
  double _maxOffset = 0;
  double _colWidth = 0;
  List<double> _snaps = const [0];

  double _dragStartOffset = 0;
  double _dragStartX = 0;
  double _lastDx = 0;
  bool _dragging = false;

  late final AnimationController _snapController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Animation<double>? _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapController.addListener(() {
      final value = _snapAnim?.value;
      if (value != null) setState(() => _offset = value);
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OfficeStatusStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.offices.length != oldWidget.offices.length) {
      // Offices were added or removed (e.g. a retire landed): recompute and
      // clamp — the pager must never rest past its new end.
      _computeMetrics(_colWidth * 7 / 2);
      _offset = _offset.clamp(0.0, _maxOffset).toDouble();
      _snapAnim = null;
      _snapController.stop();
    }
  }

  /// Recomputes the column width, the furthest scroll offset and the snap
  /// positions. Snap positions are column multiples, with the clamped end
  /// (the track's real maximum) appended when it is not itself a multiple —
  /// so the last office can always be brought fully into view. Deliberately
  /// does not clamp [_offset]: a rubber-banded drag rests past the end and
  /// must survive the rebuild it triggers; the clamp happens on drag end and
  /// on office-count changes.
  void _computeMetrics(double viewportWidth) {
    if (viewportWidth <= 0) return;
    _colWidth = viewportWidth * 2 / 7;
    _maxOffset = math.max(0, widget.offices.length * _colWidth - viewportWidth);
    _snaps = [0];
    if (_maxOffset > 4) {
      for (double p = _colWidth; p < _maxOffset - 4; p += _colWidth) {
        _snaps.add(p);
      }
      _snaps.add(_maxOffset);
    }
  }

  int _nearestSnapIndex(double offset) {
    var best = 0;
    for (var i = 0; i < _snaps.length; i++) {
      if ((_snaps[i] - offset).abs() < (_snaps[best] - offset).abs()) best = i;
    }
    return best;
  }

  void _animateTo(double target) {
    final clamped = target.clamp(0.0, _maxOffset).toDouble();
    _snapAnim = Tween<double>(begin: _offset, end: clamped).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.forward(from: 0);
  }

  void _onDragStart(DragStartDetails details) {
    _dragging = true;
    _lastDx = 0;
    _dragStartOffset = _offset;
    _dragStartX = details.globalPosition.dx;
    _snapAnim = null;
    _snapController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _lastDx = _dragStartX - details.globalPosition.dx;
    final target = _dragStartOffset + _lastDx;
    // Rubber-band past either end, like the approved mockup.
    final banded = target < 0
        ? target * 0.35
        : target > _maxOffset
        ? _maxOffset + (target - _maxOffset) * 0.35
        : target;
    if (banded != _offset) setState(() => _offset = banded);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final threshold = math.max(24.0, _colWidth * 0.18);
    var index = _nearestSnapIndex(_dragStartOffset);
    if (_lastDx.abs() > threshold) {
      // Exactly one office per swipe: advance or retreat a single snap.
      index = math.max(
        0,
        math.min(_snaps.length - 1, index + (_lastDx > 0 ? 1 : -1)),
      );
    } else {
      index = _nearestSnapIndex(_offset.clamp(0.0, _maxOffset).toDouble());
    }
    _animateTo(_snaps[index]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.offices.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = widget.offices
        .map((o) => o.updatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    final hintBits = <String>[
      if (widget.isAdmin) 'Tap an office to change it. Students see the change after sync.',
      if (widget.offices.length > 3) 'Swipe sideways to see all offices.',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pageInset,
        AppTheme.sectionGap,
        AppTheme.pageInset,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    'CAMPUS OFFICES',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: AppTheme.groupLabelColorOf(scheme),
                    ),
                  ),
                ),
                if (latest != null)
                  Text(
                    'Updated ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(latest.toLocal()), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.2,
                      color: AppTheme.placeholderFor(scheme),
                    ),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardDecoration = BoxDecoration(
                color: AppTheme.cardFillColorOf(scheme),
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                border: Border.fromBorderSide(
                  AppTheme.cardBorderSideOf(scheme),
                ),
                boxShadow: AppTheme.cardShadowsOf(scheme),
              );

              // ≤3 offices: the approved v12 row, unchanged.
              if (widget.offices.length <= 3) {
                final tileWidth = (constraints.maxWidth / 3).clamp(
                  110.0,
                  double.infinity,
                );
                return Container(
                  decoration: cardDecoration,
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, office) in widget.offices.indexed) ...[
                            if (index > 0)
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: AppTheme.cardBorderSideOf(scheme).color,
                              ),
                            SizedBox(
                              width: tileWidth,
                              child: _OfficeTile(
                                office: office,
                                isAdmin: widget.isAdmin,
                                pending: widget.pendingOffices.contains(office.office),
                                saving: widget.savingOffice == office.office,
                                onTap:
                                    widget.isAdmin && widget.onEditOffice != null
                                    ? () => widget.onEditOffice!(office)
                                    : null,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }

              // 4+ offices: the pager. Metrics are recomputed on every
              // layout; the drag handlers read them without triggering
              // rebuilds of their own.
              _computeMetrics(constraints.maxWidth);
              // Rest outside a drag (rotation, office added) must clamp; a
              // rubber-banded drag keeps its overshoot until release.
              if (!_dragging) {
                _offset = _offset.clamp(0.0, _maxOffset).toDouble();
              }
              final showRightEdge = _maxOffset > 4 && _offset < _maxOffset - 4;
              final showLeftEdge = _offset > 4;

              return Container(
                decoration: cardDecoration,
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  key: const Key('office_strip_pager'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  onHorizontalDragCancel: () {
                    if (_dragging) _onDragEnd(DragEndDetails());
                  },
                  child: SizedBox(
                    height: _kPagerTileHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRect(
                            child: OverflowBox(
                              maxWidth: double.infinity,
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: Offset(-_offset, 0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final (index, office)
                                        in widget.offices.indexed) ...[
                                      if (index > 0)
                                        VerticalDivider(
                                          width: 1,
                                          thickness: 1,
                                          color: AppTheme.cardBorderSideOf(
                                            scheme,
                                          ).color,
                                        ),
                                      SizedBox(
                                        width: _colWidth,
                                        height: _kPagerTileHeight,
                                        child: _OfficeTile(
                                          office: office,
                                          isAdmin: widget.isAdmin,
                                          pending: widget.pendingOffices.contains(
                                            office.office,
                                          ),
                                          saving:
                                              widget.savingOffice == office.office,
                                          onTap:
                                              widget.isAdmin &&
                                                  widget.onEditOffice != null
                                              ? () => widget.onEditOffice!(office)
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (showRightEdge)
                          const _EdgeBlur(side: _EdgeSide.right),
                        if (showLeftEdge) const _EdgeBlur(side: _EdgeSide.left),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (hintBits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 6),
              child: Text(
                hintBits.join(' '),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: AppTheme.placeholderFor(scheme),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _EdgeSide { left, right }

/// A 52px sliver at one edge of the pager: blurs whatever peeks underneath
/// and dissolves it into the card's own colour, fading out toward the
/// card's middle (the multi-stop ramp from the approved mockup). The blur
/// and the tint share one ShaderMask so they fade in together.
class _EdgeBlur extends StatelessWidget {
  const _EdgeBlur({required this.side});

  final _EdgeSide side;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRight = side == _EdgeSide.right;

    return Positioned(
      top: 0,
      bottom: 0,
      width: 52,
      right: isRight ? 0 : null,
      left: isRight ? null : 0,
      child: IgnorePointer(
        child: ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
              end: isRight ? Alignment.centerRight : Alignment.centerLeft,
              colors: const [
                Color(0x00000000),
                Color(0x73000000),
                Color(0xD1000000),
                Color(0xFF000000),
              ],
              stops: const [0.0, 0.4, 0.74, 1.0],
            ).createShader(bounds),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: AppTheme.cardFillColorOf(scheme).withValues(
                  alpha: 0.26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfficeTile extends StatelessWidget {
  const _OfficeTile({
    required this.office,
    required this.isAdmin,
    required this.pending,
    required this.saving,
    this.onTap,
  });

  final OfficeStatus office;
  final bool isAdmin;
  final bool pending;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (foreground, bar) = switch (office.status) {
      'open' => (AppTheme.successForegroundOf(context), AppTheme.success),
      'break' => (
        AppTheme.warningForegroundOf(context),
        const Color(0xFFB07800),
      ),
      _ => (scheme.onSurfaceVariant, scheme.outline.withValues(alpha: 0.5)),
    };

    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fixed 24px top row in both views, so student and admin columns
          // are the same height: the status bar sits on its centre line,
          // level with the edit chip. The tile's width is fixed by the
          // strip (a third of the card), so the Expanded bar here is safe.
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: bar,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.fromBorderSide(
                        AppTheme.cardBorderSideOf(scheme),
                      ),
                    ),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            office.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            office.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: foreground,
            ),
          ),
          // Fixed-height sub line keeps every column the same height whether
          // or not there is a note; pending replaces the note with "Syncing…".
          SizedBox(
            height: 13,
            child: Align(
              alignment: Alignment.centerLeft,
              child: pending
                  ? Text(
                      'Syncing…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.liveOf(context),
                      ),
                    )
                  : (office.message != null && office.message!.isNotEmpty)
                  ? Text(
                      office.message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        color: AppTheme.placeholderFor(scheme),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );

    final dimmed = saving ? Opacity(opacity: 0.55, child: tile) : tile;
    if (isAdmin && onTap != null) {
      return InkWell(onTap: onTap, child: dimmed);
    }
    return dimmed;
  }
}
