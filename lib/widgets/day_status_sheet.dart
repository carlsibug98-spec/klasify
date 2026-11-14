import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/class_item.dart';
import '../models/class_status.dart';
import '../services/reminder_service.dart';
import '../services/widget_data_actions.dart';
import '../theme/app_theme.dart';
import 'app_notification.dart';

class _SheetChoice {
  const _SheetChoice({
    this.status,
    this.span = StatusSpan.thisClass,
    this.customEndDate,
    this.clear = false,
  });

  final DayStatus? status;
  final StatusSpan span;
  final DateTime? customEndDate;
  final bool clear;
}

/// Opens "Mark class" for one occurrence on [date]. Saves, updates or clears its
/// status, and shows a short message.
///
/// The sheet follows the Mark class design: an eyebrow + class header with a
/// date pill, three colour-coded status tiles, a duration segmented control and
/// one full-width action. Everything is selected in place; nothing is nested.
Future<void> showDayStatusSheet(
  BuildContext context, {
  required ClassItem item,
  required DateTime date,
  ClassStatusEntry? current,
  required DayStatusActions actions,
}) async {
  final id = item.id;
  if (id == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final scheme = Theme.of(context).colorScheme;

  final choice = await showModalBottomSheet<_SheetChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: scheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.sheetRadius),
      ),
    ),
    builder: (_) => _DayStatusSheet(item: item, date: date, current: current),
  );
  if (choice == null) return;

  try {
    if (choice.clear) {
      final entry = current;
      if (entry == null) return;
      await actions.clearStatus(entry, day: dateKey(date));
      final synced = await _syncReminders();
      _notify(
        messenger,
        scheme,
        synced
            ? 'Status cleared for ${shortDateLabel(date)}'
            : 'Status cleared, but reminders could not be updated.',
        synced ? AppNotificationKind.info : AppNotificationKind.warning,
      );
      return;
    }

    final status = choice.status;
    if (status == null) return;
    final entry = ClassStatusEntry(
      classId: id,
      status: status,
      startDate: dateKey(date),
      endDate: _endFor(choice.span, date, customEnd: choice.customEndDate),
    );
    await actions.setStatus(entry);
    final synced = await _syncReminders();
    final summary =
        '${item.subject}: ${status.label} · '
        '${statusDurationLabel(entry, DateTime.now())}';
    _notify(
      messenger,
      scheme,
      synced ? summary : '$summary. Reminders could not be updated.',
      synced ? AppNotificationKind.success : AppNotificationKind.warning,
    );
  } catch (error, stackTrace) {
    debugPrint('Class status save failed: $error\n$stackTrace');
    if (messenger != null) {
      showAppNotificationOnMessenger(
        messenger,
        scheme,
        'Could not save. Please try again.',
        kind: AppNotificationKind.error,
      );
    }
  }
}

/// Marks change which reminders should exist, so reminders are rebuilt after
/// each change. Returns false if reminders could not be updated.
Future<bool> _syncReminders() async {
  try {
    await ReminderService.instance.sync();
    return true;
  } catch (error, stackTrace) {
    debugPrint('Reminder update after status change failed: $error\n$stackTrace');
    return false;
  }
}

String? _endFor(StatusSpan span, DateTime date, {DateTime? customEnd}) =>
    switch (span) {
      StatusSpan.thisClass => dateKey(date),
      StatusSpan.untilDate => customEnd != null ? dateKey(customEnd) : null,
      StatusSpan.untilCleared => null,
    };

/// A short result message. The mark is already saved, so there is no action.
void _notify(
  ScaffoldMessengerState? messenger,
  ColorScheme scheme,
  String message,
  AppNotificationKind kind,
) {
  if (messenger == null) return;
  showAppNotificationOnMessenger(
    messenger,
    scheme,
    message,
    kind: kind,
    duration: const Duration(seconds: 3),
  );
}

class _DayStatusSheet extends StatefulWidget {
  const _DayStatusSheet({
    required this.item,
    required this.date,
    required this.current,
  });

  final ClassItem item;
  final DateTime date;
  final ClassStatusEntry? current;

  @override
  State<_DayStatusSheet> createState() => _DayStatusSheetState();
}

class _DayStatusSheetState extends State<_DayStatusSheet> {
  DayStatus? _kind;
  StatusSpan _span = StatusSpan.thisClass;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _kind = current?.status;
    final preset = current?.presetSpan;
    if (preset != null) {
      _span = preset;
    } else if (current != null && current.endDate != null) {
      // Custom end date (not a preset) → "Until date".
      _span = StatusSpan.untilDate;
      _customEndDate = parseDateKey(current.endDate!);
    } else {
      _span = StatusSpan.thisClass;
    }
  }

  String get _description => switch (_kind) {
    DayStatus.finished => 'You finished this class.',
    DayStatus.notAttending => 'You’re skipping this class.',
    DayStatus.cancelled => 'The class won’t meet.',
    null => 'Pick what happened to this class.',
  };

  String get _spanSentence {
    final start = shortDateLabel(widget.date);
    return switch (_span) {
      StatusSpan.thisClass => 'Only $start.',
      StatusSpan.untilDate => _customEndDate == null
          ? 'Pick an end date.'
          : '$start through ${shortDateLabel(_customEndDate!)}.',
      StatusSpan.untilCleared => 'From $start until you clear it.',
    };
  }

  void _save() {
    Navigator.of(context).pop(
      _SheetChoice(
        status: _kind,
        span: _span,
        customEndDate: _customEndDate,
      ),
    );
  }

  bool get _canSave =>
      _kind != null &&
      (_span != StatusSpan.untilDate || _customEndDate != null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasKind = _kind != null;
    final isEditing = widget.current != null;
    final item = widget.item;
    final room = item.room.trim();
    final meta = [
      formatTimeRange(item.startMinutes, item.endMinutes),
      if (room.isNotEmpty) formatRoom(room),
    ].join(' · ');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pageInset,
        10,
        AppTheme.pageInset,
        28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.brightness == Brightness.dark
                    ? const Color(0xFF4A4A4A)
                    : const Color(0xFFC4C4C4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MARK CLASS',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.96,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                        fontSize: 24,
                        height: 28 / 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.24,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                ),
                child: Text(
                  shortDateLabel(widget.date),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (isEditing) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.warningBackgroundOf(context),
                borderRadius: BorderRadius.circular(AppTheme.chipRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusGlyph(
                    status: widget.current!.status,
                    size: 16,
                    color: AppTheme.warningForegroundOf(context),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Marked: ${widget.current!.status.label} · '
                      '${statusDurationLabel(widget.current!, DateTime.now())}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppTheme.warningForegroundOf(context),
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'What happened',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _StatusTiles(
            value: _kind,
            onChanged: (kind) {
              HapticFeedback.selectionClick();
              setState(() => _kind = kind);
            },
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: AppTheme.motionDuration(context, AppTheme.motionFast),
            switchInCurve: AppTheme.motionEaseOut,
            switchOutCurve: AppTheme.motionEaseOut,
            child: Text(
              _description,
              key: ValueKey(_description),
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'For how long',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          AnimatedOpacity(
            duration: AppTheme.motionDuration(context, AppTheme.motionFast),
            opacity: hasKind ? 1 : 0.5,
            child: _SpanTrack(
              value: _span,
              enabled: hasKind,
              onChanged: (span) {
                HapticFeedback.selectionClick();
                setState(() {
                  _span = span;
                  if (span == StatusSpan.untilDate && _customEndDate == null) {
                    _customEndDate = widget.date.add(const Duration(days: 7));
                  }
                });
              },
            ),
          ),
          if (_span == StatusSpan.untilDate) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: hasKind
                    ? () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _customEndDate ?? widget.date,
                          firstDate: widget.date,
                          lastDate: widget.date.add(const Duration(days: 365)),
                          builder: (context, child) {
                            // Match the sheet's surface so the picker reads as
                            // part of the same dark compose surface.
                            final scheme = Theme.of(context).colorScheme;
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: scheme,
                                dialogTheme: DialogThemeData(
                                  backgroundColor: scheme.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppTheme.sheetRadius,
                                    ),
                                  ),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          HapticFeedback.selectionClick();
                          setState(() => _customEndDate = picked);
                        }
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  ),
                  foregroundColor: scheme.onSurface,
                  backgroundColor: scheme.surfaceContainer,
                  side: BorderSide.none,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(
                  _customEndDate == null
                      ? 'Choose end date'
                      : shortDateLabel(_customEndDate!),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _spanSentence,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.25,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(
                !hasKind
                    ? 'Pick what happened'
                    : isEditing
                    ? 'Update'
                    : 'Mark as ${_kind!.label}',
              ),
            ),
          ),
          if (isEditing) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(const _SheetChoice(clear: true)),
                child: const Text('Clear status'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The three colour-coded "What happened" tiles.
class _StatusTiles extends StatelessWidget {
  const _StatusTiles({required this.value, required this.onChanged});

  final DayStatus? value;
  final ValueChanged<DayStatus> onChanged;

  static const _order = [
    DayStatus.finished,
    DayStatus.notAttending,
    DayStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'What happened',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, status) in _order.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: _StatusTile(
                status: status,
                selected: status == value,
                onTap: () => onChanged(status),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final DayStatus status;
  final bool selected;
  final VoidCallback onTap;

  /// Selected palette from the design: green for finished, amber for skipped,
  /// red for cancelled. Dark mode uses the same roles with dark surfaces.
  ({Color background, Color foreground, Color border}) _colors(
    ColorScheme scheme,
  ) {
    final dark = scheme.brightness == Brightness.dark;
    return switch (status) {
      DayStatus.finished => (
        background: AppTheme.successBackgroundFor(scheme),
        foreground: AppTheme.successForegroundFor(scheme),
        border: dark ? AppTheme.successForegroundFor(scheme) : AppTheme.success,
      ),
      DayStatus.notAttending => (
        background: AppTheme.warningBackgroundFor(scheme),
        foreground: AppTheme.warningForegroundFor(scheme),
        border: AppTheme.warningForegroundFor(scheme),
      ),
      DayStatus.cancelled => (
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        border: scheme.error,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final colors = selected
        ? _colors(scheme)
        : (
            background: scheme.surfaceContainer,
            foreground: scheme.onSurface,
            border: Colors.transparent,
          );
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: status.label,
      child: AnimatedContainer(
        duration: AppTheme.motionDuration(context, AppTheme.motionFast),
        curve: AppTheme.motionEaseOut,
        height: 88,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: colors.border, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatusGlyph(
                        status: status,
                        size: 24,
                        color: colors.foreground,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            status.label,
                            maxLines: 1,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.foreground,
                              fontSize: 13,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: AppTheme.motionDuration(
                      context,
                      AppTheme.motionFast,
                    ),
                    curve: AppTheme.motionEaseOut,
                    child: AnimatedScale(
                      scale: selected ? 1 : 0.9,
                      duration: AppTheme.motionDuration(
                        context,
                        AppTheme.motionFast,
                      ),
                      curve: AppTheme.motionEaseOut,
                      child: ExcludeSemantics(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: selected ? scheme.inverseSurface : null,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: _CheckMark(
                          size: 12,
                          color: scheme.onInverseSurface,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled segmented control for how long a status applies.
class _SpanTrack extends StatelessWidget {
  const _SpanTrack({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final StatusSpan value;
  final bool enabled;
  final ValueChanged<StatusSpan> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'For how long',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        ),
        child: Row(
          children: [
            for (final (index, span) in StatusSpan.values.indexed) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(
                child: _SpanSegment(
                  label: span.label,
                  selected: span == value,
                  enabled: enabled,
                  onTap: () => onChanged(span),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpanSegment extends StatelessWidget {
  const _SpanSegment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      label: label,
      child: AnimatedContainer(
        duration: AppTheme.motionDuration(context, AppTheme.motionFast),
        curve: AppTheme.motionEaseOut,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.chipRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: textTheme.bodySmall?.copyWith(
                      color: selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
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

/// Line glyphs copied from the design: check, calendar-x, circled-x.
class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({
    required this.status,
    required this.size,
    required this.color,
  });

  final DayStatus status;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StatusGlyphPainter(
          status: status,
          color: color,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _StatusGlyphPainter extends CustomPainter {
  _StatusGlyphPainter({
    required this.status,
    required this.color,
    required this.strokeWidth,
  });

  final DayStatus status;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;

    void path(void Function(Path p) build) {
      final p = Path();
      build(p);
      canvas.drawPath(p, paint);
    }

    switch (status) {
      case DayStatus.finished:
        path(
          (p) => p
            ..moveTo(5 * s, 12.5 * s)
            ..lineTo(9.5 * s, 17 * s)
            ..lineTo(19 * s, 7.5 * s),
        );
        break;
      case DayStatus.notAttending:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(4 * s, 5 * s, 16 * s, 15 * s),
            Radius.circular(3 * s),
          ),
          paint,
        );
        path(
          (p) => p
            ..moveTo(4 * s, 10 * s)
            ..lineTo(20 * s, 10 * s)
            ..moveTo(8 * s, 3 * s)
            ..lineTo(8 * s, 7 * s)
            ..moveTo(16 * s, 3 * s)
            ..lineTo(16 * s, 7 * s)
            ..moveTo(10 * s, 13.5 * s)
            ..lineTo(14 * s, 17.5 * s)
            ..moveTo(14 * s, 13.5 * s)
            ..lineTo(10 * s, 17.5 * s),
        );
        break;
      case DayStatus.cancelled:
        canvas.drawCircle(Offset(12 * s, 12 * s), 9 * s, paint);
        path(
          (p) => p
            ..moveTo(9 * s, 9 * s)
            ..lineTo(15 * s, 15 * s)
            ..moveTo(15 * s, 9 * s)
            ..lineTo(9 * s, 15 * s),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _StatusGlyphPainter oldDelegate) =>
      oldDelegate.status != status ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({
    required this.size,
    required this.color,
    required this.strokeWidth,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CheckMarkPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _CheckMarkPainter extends CustomPainter {
  const _CheckMarkPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;
    final path = Path()
      ..moveTo(5 * s, 12.5 * s)
      ..lineTo(9.5 * s, 17 * s)
      ..lineTo(19 * s, 7.5 * s);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
