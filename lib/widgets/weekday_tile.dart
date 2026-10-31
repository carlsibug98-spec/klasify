import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One segment of the weekly schedule's segmented day bar (approved mockup
/// C): abbreviation, date and class-count dots on their own mini-segment.
/// Corners follow the segment position via [AppTheme.segmentRadiusHOf] —
/// 16px on the bar's outer ends, 2px where segments meet.
///
/// States follow the app language: the selected day fills with the primary
/// ink; today (unselected) keeps a transparent fill with a 1.5px primary
/// ring; every other day carries the option-C card edge (fill, hairline,
/// ambient shadow).
class WeekdayTile extends StatelessWidget {
  const WeekdayTile({
    super.key,
    required this.date,
    required this.name,
    required this.classCount,
    required this.isToday,
    required this.selected,
    required this.onTap,
    this.borderRadius,
  });

  final DateTime date;
  final String name;
  final int classCount;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  /// This segment's corners inside the bar. Defaults to the full card
  /// radius so a standalone tile (tests, previews) still reads as a card.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = borderRadius ?? BorderRadius.circular(AppTheme.cardRadius);
    final filled = selected;

    final side = filled
        // The filled segment's border disappears into its fill.
        ? BorderSide(color: scheme.primary)
        : isToday
        ? BorderSide(color: scheme.primary, width: 1.5)
        : AppTheme.cardBorderSideOf(scheme);

    final abbrColor = filled
        ? scheme.onPrimary.withValues(alpha: 0.75)
        : AppTheme.groupLabelColorOf(scheme);
    final dateColor = filled ? scheme.onPrimary : scheme.onSurface;
    final dotColor = filled
        ? scheme.onPrimary.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant.withValues(alpha: 0.38);

    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label:
          '$name, ${MaterialLocalizations.of(context).formatFullDate(date)}${isToday ? ', today' : ''}, $classCount ${classCount == 1 ? 'class' : 'classes'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: filled || isToday
              ? const []
              : AppTheme.cardShadowsOf(scheme),
        ),
        child: Material(
          // Selected fills with the primary ink; today keeps a transparent
          // fill under its ring; every other day carries the card fill.
          color: filled
              ? scheme.primary
              : isToday
              ? Colors.transparent
              : AppTheme.cardFillColorOf(scheme),
          shape: RoundedRectangleBorder(borderRadius: radius, side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.substring(0, 3).toUpperCase(),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: abbrColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.day}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      color: dateColor,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Class-count dots: one per class up to four, on a fixed
                  // 4px band so empty and busy days stay aligned.
                  SizedBox(
                    height: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var i = 0;
                          i < classCount.clamp(0, 4);
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(width: 3),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
