import 'package:flutter/material.dart';

import '../models/class_item.dart';
import '../models/class_status.dart';
import '../theme/app_theme.dart';
import 'class_card.dart' show ClassStatus;
import 'class_tags.dart';
import 'live_pulse.dart';

/// One class rendered as a segment of the weekly schedule's segmented
/// stacks (approved mockup C): the settings' A₂ language applied to the
/// day list. Each row carries the approved option-C edge — hairline plus
/// ambient shadow in light mode, raised fill in dark — but its corners
/// follow its position inside the stack via [AppTheme.segmentRadiusOf]:
/// group corners stay 16px, meeting edges soften to 2px, and consecutive
/// classes read as one block through the 2px seams.
///
/// The row is deliberately slimmer than the Today screen's [ClassCard]:
/// the time moves into a fixed left column (start time only), the details
/// collapse to one tracked meta line, and the status tags anchor the right
/// edge. The full range stays in the semantics label and the day-status
/// sheet a tap opens.
///
/// Pass [status] only when the list is for today. A class the user has
/// marked is never shown as live, because the mark says it is not
/// happening for them.
class ClassSegmentRow extends StatelessWidget {
  const ClassSegmentRow({
    super.key,
    required this.item,
    required this.radius,
    this.onTap,
    this.onLongPress,
    this.status,
    this.statusEntry,
    this.isFocus = false,
  });

  final ClassItem item;

  /// This row's corners inside its stack ([AppTheme.segmentRadiusOf]).
  final BorderRadius radius;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Where the class sits relative to now, when the list is for today.
  final ClassStatus? status;

  /// The status the user set for this occurrence, with its duration.
  final ClassStatusEntry? statusEntry;

  /// True for the class the hero is focused on (in progress, or the next
  /// one). Its time takes the live color, so the orange moves to the next
  /// class when the current one is marked finished. The NOW tag still
  /// shows only when live.
  final bool isFocus;

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

    // The meta line keeps the Today cards' pin/person icons: room and
    // professor stay scannable at a glance instead of dissolving into one
    // grey string. Built as a single Text.rich so the ellipsis still bites
    // the last run — the room survives truncation, the professor yields
    // first, matching the old cards' priority.
    final metaIconColor = scheme.onSurfaceVariant;
    final metaSpans = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(Icons.location_on_outlined, size: 13, color: metaIconColor),
      ),
      const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SizedBox(width: 3),
      ),
      TextSpan(text: room),
      if (hasProfessor) ...[
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(width: 10),
        ),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(
            Icons.person_outline_rounded,
            size: 13,
            color: metaIconColor,
          ),
        ),
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(width: 3),
        ),
        TextSpan(text: item.professor.trim()),
      ],
    ];

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
        if (isFocus && !isLive && !isDone && mark == null) 'next class',
        ?markLabel,
      ].join(', '),
      child: AnimatedOpacity(
        opacity: (isDone || mark != null) ? 0.5 : 1.0,
        duration: AppTheme.motionDuration(context, AppTheme.motionStandard),
        curve: AppTheme.motionEaseOut,
        // Option C edge: the ambient shadow wraps the Material (it paints
        // behind the row and must not be clipped); the hairline rides on
        // the Material's own shape so it follows the segment corners.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: AppTheme.cardShadowsOf(scheme),
          ),
          child: Material(
            color: AppTheme.cardFillColorOf(scheme),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: AppTheme.cardBorderSideOf(scheme),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    // The slim left time column. Fixed width so every start
                    // time in the day lines up into one quiet rail; the
                    // fitted box keeps large text scales inside it.
                    SizedBox(
                      width: 62,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          formatMinutes(item.startMinutes),
                          maxLines: 1,
                          style: textTheme.labelLarge?.copyWith(
                            fontSize: 12.5,
                            color: timeColor,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.subject,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 15,
                              color: subjectColor,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(children: metaSpans),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status tags anchor the right edge, outside the text
                    // column so long subjects never push them around.
                    if (isLive) ...[
                      const SizedBox(width: 10),
                      NowTag(
                        color: live,
                        pulse: LivePulse(
                          size: 7,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                    if (isFocus && !isLive && !isDone && mark == null) ...[
                      const SizedBox(width: 10),
                      const NextUpTag(),
                    ],
                    if (mark != null) ...[
                      const SizedBox(width: 10),
                      ClassStatusPill(status: mark, label: mark.label),
                    ],
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
