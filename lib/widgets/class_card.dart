import 'package:flutter/material.dart';

import '../models/class_item.dart';
import '../models/class_status.dart';
import '../theme/app_theme.dart';
import 'live_pulse.dart';
import 'pressable_scale.dart';
import 'pill.dart';

/// Where a class sits relative to the current time. Only used on today.
enum ClassStatus { done, live, upcoming }

/// Returns the status of [item] at [nowMinutes] (minutes since midnight).
ClassStatus classStatusAt(ClassItem item, int nowMinutes) {
  if (item.startMinutes <= nowMinutes && nowMinutes < item.endMinutes) {
    return ClassStatus.live;
  }
  if (item.endMinutes <= nowMinutes) return ClassStatus.done;
  return ClassStatus.upcoming;
}

/// One class: a filled card with the time, subject and details.
///
/// The card carries the approved option-C edge (depth study mockup): a 1px
/// hairline plus a two-layer ambient shadow in light mode, and a raised fill
/// with the same hairline in dark mode — see
/// [AppTheme.cardBorderSideOf]/[AppTheme.cardShadowsOf]/[AppTheme.cardFillColorOf].
/// The hero stays the only floating surface; these shadows are ambient only.
///
/// Pass [status] only when the list is for today. A class the user has marked
/// is never shown as live, because the mark says it is not happening for them.
class ClassCard extends StatelessWidget {
  final ClassItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showDay;
  final ClassStatus? status;

  /// The status the user set for this occurrence, with its duration.
  final ClassStatusEntry? statusEntry;

  /// True for the class the hero block is showing as "Next up".
  final bool isNext;

  /// True for the class the hero is focused on (in progress, or the next one).
  /// Its time takes the live color, so the orange moves to the next class when
  /// the current one is marked finished. The NOW tag still shows only when live.
  final bool isFocus;

  /// The card applies the standard page inset itself. SwipeActions owns the
  /// horizontal padding for its cards, so it passes false and applies the
  /// inset around the whole swipe area instead.
  final bool insetHorizontally;

  /// The 10px gap below the card. SwipeActions puts the gap on its own outer
  /// padding so the action plane lines up with the card exactly.
  final bool trailingGap;

  const ClassCard({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.showDay = false,
    this.status,
    this.statusEntry,
    this.isNext = false,
    this.isFocus = false,
    this.insetHorizontally = true,
    this.trailingGap = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final live = AppTheme.liveOf(context);
    final hasProfessor =
        item.professor.trim().isNotEmpty &&
        item.professor.trim() != unspecifiedProfessor;
    final room = formatRoom(item.room);
    final mark = statusEntry?.status;
    final timeEnded = status == ClassStatus.done;
    final isLive = status == ClassStatus.live && mark == null;
    final isDone = timeEnded || mark == DayStatus.finished;

    final timeColor = (isLive || (isFocus && !isDone && mark == null))
        ? live
        : isDone
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final subjectColor = isDone ? scheme.onSurfaceVariant : scheme.onSurface;
    final detailStyle = textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final cardFill = AppTheme.cardFillColorOf(scheme, isNext: isNext);

    final markLabel = mark == null || statusEntry == null
        ? null
        : '${mark.label} · ${statusDurationLabel(statusEntry!, DateTime.now())}';

    return Semantics(
      container: true,
      label: [
        item.subject,
        item.timeRange,
        room,
        if (hasProfessor) item.professor.trim(),
        if (isLive) 'in progress',
        if (isDone) 'finished',
        if (isNext) 'next class',
        ?markLabel,
      ].join(', '),
      child: Padding(
        padding: insetHorizontally
            ? const EdgeInsets.symmetric(horizontal: AppTheme.pageInset)
            : EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    PressableScale(
                      enabled: onTap != null,
                      child: AnimatedOpacity(
                        opacity: (isDone || mark != null) ? 0.5 : 1.0,
                        duration: AppTheme.motionDuration(
                          context,
                          AppTheme.motionStandard,
                        ),
                        curve: AppTheme.motionEaseOut,
                        // Option C edge: the ambient shadow wraps the Material
                        // (it paints behind the card and must not be clipped);
                        // the hairline rides on the Material's own shape so it
                        // follows the same rounded rect.
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppTheme.cardRadius,
                            ),
                            boxShadow: AppTheme.cardShadowsOf(scheme),
                          ),
                          child: Material(
                            color: cardFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.cardRadius,
                              ),
                              side: AppTheme.cardBorderSideOf(scheme),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: onTap,
                              onLongPress: onLongPress,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Time, NOW tag and status pill share one
                                          // line. The pill shows only the status name
                                          // so it fits beside the time; the duration
                                          // ("until Sun", "until cleared") lives in
                                          // the mark sheet and the semantics label.
                                          // The Wrap stays as a fallback for very
                                          // narrow cards and large text scales.
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                item.timeRange,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: textTheme.labelLarge
                                                    ?.copyWith(
                                                      color: timeColor,
                                                      fontWeight: FontWeight.w700,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                              ),
                                              if (isLive)
                                                _NowTag(
                                                  color: live,
                                                  pulse: LivePulse(
                                                    size: 7,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.95),
                                                  ),
                                                ),
                                              if (isNext &&
                                                  !isLive &&
                                                  !isDone &&
                                                  mark == null)
                                                const _NextUpTag(),
                                              if (mark != null)
                                                _StatusPill(
                                                  status: mark,
                                                  label: mark.label,
                                                ),
                                              if (showDay)
                                                Text(
                                                  item.dayName.substring(0, 3),
                                                  style: textTheme.labelMedium
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            item.subject,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: textTheme.titleMedium
                                                ?.copyWith(
                                                  color: subjectColor,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              _ClassMeta(
                                                icon: Icons.location_on_outlined,
                                                label: room,
                                                style: detailStyle,
                                              ),
                                              if (hasProfessor)
                                                _ClassMeta(
                                                  icon: Icons
                                                      .person_outline_rounded,
                                                  label: item.professor.trim(),
                                                  style: detailStyle,
                                                ),
                                            ],
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
                    ),
                    // Gap below each card. It sits inside the row, so the rail
                    // runs continuously from one class to the next.
                    if (trailingGap) const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The NOW label: a small pill in the app's live color, with text in the
/// theme's inverse ink so it reads on both light and dark schemes.
class _NowTag extends StatelessWidget {
  const _NowTag({required this.color, this.pulse});

  final Color color;
  final Widget? pulse;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse != null) ...[pulse!, const SizedBox(width: 5)],
          Text(
            'NOW',
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Next up" pill on the class the hero is showing as next. Filled with the
/// inverse ink, like the hero block, so it matches the hero's label.
class _NextUpTag extends StatelessWidget {
  const _NextUpTag();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Text(
        'Next up',
        style: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ClassMeta extends StatelessWidget {
  const _ClassMeta({required this.icon, required this.label, this.style});

  final IconData icon;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(label, style: style, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// Status pill with the app's theme colors: green for finished, amber for
/// cancelled, neutral for not attending.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.label});

  final DayStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      DayStatus.finished => (
        AppTheme.successBackgroundOf(context),
        AppTheme.successForegroundOf(context),
      ),
      DayStatus.cancelled => (
        AppTheme.warningBackgroundOf(context),
        AppTheme.warningForegroundOf(context),
      ),
      DayStatus.notAttending => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
    };
    return Pill(label: label, background: background, foreground: foreground);
  }
}
