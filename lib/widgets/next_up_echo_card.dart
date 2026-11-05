import 'package:flutter/material.dart';

import '../models/class_item.dart';
import '../theme/app_theme.dart';

/// The "next up" echo card under a live hero: the class that follows the one
/// in progress, so a student mid-class can see if they can stand up now or
/// should start moving. The hero carries the live state alone; this card is
/// the mockup's one quiet addition beneath it — time on the left in the
/// signal orange, subject and room in the middle, a tracked-caps tag on the
/// right.
///
/// A class on another day says so in the room line ("Tomorrow · Computer
/// Lab 1"); same-day echoes stay plain.
class NextUpEchoCard extends StatelessWidget {
  const NextUpEchoCard({super.key, required this.item, required this.now});

  final ClassItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tomorrow = (now.weekday % 7) + 1;
    final String roomLabel;
    if (item.day == now.weekday) {
      roomLabel = '';
    } else if (item.day == tomorrow) {
      roomLabel = 'Tomorrow · ';
    } else {
      roomLabel = '${item.dayName} · ';
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Material(
        color: AppTheme.cardFillColorOf(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: AppTheme.cardBorderSideOf(scheme),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  formatMinutes(item.startMinutes),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppTheme.liveOf(context),
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$roomLabel${formatRoom(item.room)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Text(
                  'Next up'.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    color: AppTheme.groupLabelColorOf(scheme),
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      label:
          'Next up. ${formatMinutes(item.startMinutes)}. '
          '${item.subject}. $roomLabel${formatRoom(item.room)}.',
      child: card,
    );
  }
}
