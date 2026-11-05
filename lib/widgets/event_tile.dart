import 'package:flutter/material.dart';

import '../models/class_item.dart' show formatMinutes, formatRoom;
import '../models/event_item.dart';
import '../theme/app_theme.dart';

/// One event row of the segmented Events list on Today.
///
/// A date block on the left ("SAT · 7") replaces the class row's clock —
/// events are one-off, so the day itself is the headline. The nearest
/// upcoming event wears the inverted (black) block; later events sit on the
/// raised grey block, the mockup's "closer first" hierarchy. Meta reads
/// "Gymnasium · 9:00 AM", and a reminder pill spells the alarm out
/// ("Reminder 8:30 AM") so no toggle needs opening to see it set. Turning
/// off or past reminders render the neutral "Reminder on" pill; a bare
/// (untouched) event shows none.
class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.event,
    required this.now,
    required this.radius,

    /// True for the nearest upcoming event: the inverted date block.
    required this.inverted,
    this.onTap,
    this.onLongPress,
  });

  final EventItem event;
  final DateTime now;
  final BorderRadius radius;
  final bool inverted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final day = event.day;
    final pill = _reminderPill(context, event, textTheme);
    // Mirror the visible pill in text; none when remind-me is off.
    String semanticReminder = '';
    if (event.remindMe) {
      semanticReminder = event.reminderStillFiresOn(now)
          ? 'Reminder ${event.reminderFireLabel}.'
          : 'Reminder on.';
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Material(
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: AppTheme.cardBorderSideOf(scheme),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          container: true,
          button: onTap != null,
          label:
              'Event. ${event.title}. '
              '${shortWeekdayLabel(day).toUpperCase()} ${day.day}. '
              '${event.whenAndWhereLabel}. '
              '$semanticReminder',
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _DateBlock(
                    weekday: shortWeekdayLabel(day).toUpperCase(),
                    dayOfMonth: '${day.day}',
                    inverted: inverted,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          event.whenAndWhereLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (pill != null) ...[
                          const SizedBox(height: 7),
                          ExcludeSemantics(child: pill),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The alarm chip: green with the concrete fire time while it still has
  /// a future ("Reminder 8:30 AM"), neutral "Reminder on" once the chosen
  /// lead time has already passed on the event's day (the reminder is set,
  /// but its moment is gone — the engine skips it). Nothing when remind-me
  /// is off.
  Widget? _reminderPill(
    BuildContext context,
    EventItem event,
    TextTheme textTheme,
  ) {
    if (!event.remindMe) return null;
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color foreground;
    String label;
    if (event.reminderStillFiresOn(now)) {
      background = AppTheme.successBackgroundOf(context);
      foreground = AppTheme.successForegroundOf(context);
      label = 'Reminder ${event.reminderFireLabel}';
    } else {
      background = scheme.surfaceContainerHigh;
      foreground = scheme.onSurfaceVariant;
      label = 'Reminder on';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 12,
            color: foreground,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: foreground,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The date block: 46×52, blockRadius corners, weekday caps over the day
/// number. Nearest event is inverted (primary on onPrimary); the rest stay
/// on surfaceContainerHigh with quiet foreground.
class _DateBlock extends StatelessWidget {
  const _DateBlock({
    required this.weekday,
    required this.dayOfMonth,
    required this.inverted,
  });

  final String weekday;
  final String dayOfMonth;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = inverted ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = inverted ? scheme.onPrimary : scheme.onSurface;
    return Container(
      width: 46,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppTheme.blockRadius),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekday,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.32,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            dayOfMonth,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: fg,
              fontSize: 16,
              height: 1,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// "9:00 AM · Gymnasium" — the raw minutes formatter exists on classes; the
/// venue ends up after the time so the sheet kicker ("Event · Sat, Nov 7")
/// and this line read in the same voice.
String formatEventWhen(EventItem event) {
  final time = formatMinutes(event.startMinutes);
  final venue = event.venue.trim();
  return venue.isEmpty ? time : '$time · ${formatRoom(venue)}';
}
