import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import 'app_notification.dart';

class _SheetChoice {
  const _SheetChoice({
    this.status,
    this.span = StatusSpan.thisClass,
    this.clear = false,
  });

  final DayStatus? status;
  final StatusSpan span;
  final bool clear;
}

/// Opens "Mark class" for one occurrence on [date]. Saves, updates or clears its status,
/// and shows a short message.
Future<void> showDayStatusSheet(
  BuildContext context, {
  required ClassItem item,
  required DateTime date,
  ClassStatusEntry? current,
}) async {
  final id = item.id;
  if (id == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final scheme = Theme.of(context).colorScheme;

  final choice = await showModalBottomSheet<_SheetChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.sheetRadius),
      ),
    ),
    builder: (_) => _DayStatusSheet(item: item, date: date, current: current),
  );
  if (choice == null) return;

  final db = DatabaseHelper.instance;
  try {
    if (choice.clear) {
      final entry = current;
      if (entry == null) return;
      await db.clearClassStatus(entry, day: dateKey(date));
      await _syncReminders();
      _notify(
        messenger,
        scheme,
        'Status cleared for ${shortDateLabel(date)}',
        AppNotificationKind.info,
      );
      return;
    }

    final status = choice.status;
    if (status == null) return;
    final entry = ClassStatusEntry(
      classId: id,
      status: status,
      startDate: dateKey(date),
      endDate: _endFor(choice.span, date),
    );
    await db.setClassStatus(entry);
    await _syncReminders();
    _notify(
      messenger,
      scheme,
      '${item.subject}: ${status.label} · '
      '${statusDurationLabel(entry, DateTime.now())}',
      AppNotificationKind.success,
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

/// Marks change which reminders should exist, so reminders are rebuilt after each change.
Future<void> _syncReminders() async {
  try {
    await ReminderService.instance.sync();
  } catch (error, stackTrace) {
    debugPrint('Reminder sync after status change failed: $error\n$stackTrace');
  }
}

String? _endFor(StatusSpan span, DateTime date) => switch (span) {
  StatusSpan.thisClass => dateKey(date),
  StatusSpan.untilSunday => dateKey(endOfWeekOf(date)),
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
  static const _options = <(DayStatus, IconData, String)>[
    (DayStatus.finished, Icons.check_rounded, 'Done before the class ends'),
    (
      DayStatus.notAttending,
      Icons.event_busy_outlined,
      "I'm skipping this class",
    ),
    (DayStatus.cancelled, Icons.cancel_outlined, "The class won't meet"),
  ];

  DayStatus? _kind;
  StatusSpan _span = StatusSpan.thisClass;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    _kind = current?.status;
    _span = current?.presetSpan ?? StatusSpan.thisClass;
  }

  String get _note => switch (_span) {
    StatusSpan.thisClass => 'Applies only to ${shortDateLabel(widget.date)}.',
    StatusSpan.untilSunday =>
      'Applies ${shortDateLabel(widget.date)} through '
          '${shortDateLabel(endOfWeekOf(widget.date))}.',
    StatusSpan.untilCleared =>
      'Applies from ${shortDateLabel(widget.date)} until you clear it.',
  };

  /// The description of the picked choice, or a prompt before anything is picked.
  void _save() {
    Navigator.of(context).pop(_SheetChoice(status: _kind, span: _span));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasKind = _kind != null;
    final isEditing = widget.current != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pageInset,
        6,
        AppTheme.pageInset,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppTheme.itemGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mark class',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.item.subject} · ${widget.item.timeRange}',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _StepHeader(
            number: 1,
            title: 'What happened',
            hint: hasKind ? 'Picked' : 'Required',
            done: hasKind,
          ),
          const SizedBox(height: 10),
          _KindSegments(
            options: _options,
            value: _kind,
            onChanged: (kind) {
              HapticFeedback.selectionClick();
              setState(() => _kind = kind);
            },
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StepHeader(number: 2, title: 'How long it applies'),
              const SizedBox(height: 10),
              _SpanSegments(
                value: _span,
                enabled: hasKind,
                onChanged: (span) {
                  HapticFeedback.selectionClick();
                  setState(() => _span = span);
                },
              ),
              const SizedBox(height: 8),
              _InfoNote(text: _note),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: hasKind ? _save : null,
              child: Text(
                hasKind ? (isEditing ? 'Update' : 'Save') : 'Choose an option',
              ),
            ),
          ),
          if (isEditing)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () =>
                    Navigator.of(context).pop(const _SheetChoice(clear: true)),
                child: const Text('Clear status'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.number,
    required this.title,
    this.hint,
    this.done = false,
  });

  final int number;
  final String title;
  final String? hint;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        AnimatedContainer(
          duration: AppTheme.motionDuration(context, AppTheme.motionFast),
          curve: AppTheme.motionEaseOut,
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? scheme.surfaceContainerHighest : scheme.primary,
            shape: BoxShape.circle,
          ),
          child: done
              ? Icon(Icons.check_rounded, size: 13, color: scheme.onSurface)
              : Text(
                  '$number',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (hint != null) ...[
          const Spacer(),
          Text(
            hint!,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The three "What happened" choices, as one segmented track like the duration control.
class _KindSegments extends StatelessWidget {
  const _KindSegments({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(DayStatus, IconData, String)> options;
  final DayStatus? value;
  final ValueChanged<DayStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'What happened',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (status, icon, hint) in options)
            // Animated container carries the tweened fill; a transparent
            // Material inside keeps the InkWell splash working.
            AnimatedContainer(
              duration: AppTheme.motionDuration(context, AppTheme.motionFast),
              curve: AppTheme.motionEaseOut,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: status == value
                    ? scheme.primaryContainer
                    : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Semantics(
                  button: true,
                  selected: status == value,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(status);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: status == value
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status.label,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: status == value
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hint,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: status == value
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Filled segmented control for how long a status applies.
class _SpanSegments extends StatelessWidget {
  const _SpanSegments({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final StatusSpan value;
  final bool enabled;
  final ValueChanged<StatusSpan> onChanged;

  static const _icons = {
    StatusSpan.thisClass: Icons.event_outlined,
    StatusSpan.untilSunday: Icons.view_week_outlined,
    StatusSpan.untilCleared: Icons.all_inclusive_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        // White while locked (until "What happened" is picked), grey once unlocked.
        color: enabled
            ? scheme.surfaceContainer
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      ),
      child: Row(
        children: [
          for (final (i, span) in StatusSpan.values.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _SpanSegment(
                icon: _icons[span]!,
                label: span.label,
                selected: span == value,
                enabled: enabled,
                onTap: () => onChanged(span),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpanSegment extends StatelessWidget {
  const _SpanSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.chipRadius),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
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

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
