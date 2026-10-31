import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Sticky header delegate displaying the selected day name, full date,
/// and the daily workload (e.g. "3 CLASSES · 4.5H").
///
/// Follows the approved weekly redesign (mockup C): the workload badge
/// becomes quiet tracked caps — the settings group-label treatment — so
/// the row reads as one calm caption instead of a chip competing with
/// the day name.
class SelectedDayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const SelectedDayHeaderDelegate({
    required this.dayName,
    required this.formattedDate,
    required this.classCount,
    required this.totalHours,
  });

  final String dayName;
  final String formattedDate;
  final int classCount;
  final double totalHours;

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final badgeText = classCount == 0
        ? 'No classes'
        : '$classCount ${classCount == 1 ? 'class' : 'classes'} · ${totalHours.toStringAsFixed(1)}h';

    return Material(
      color: scheme.surface,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pageInset),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: overlapsContent
                  ? scheme.outlineVariant
                  : Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flexible so a long day name + date can never push the
            // workload badge off-screen (RenderFlex overflow).
            Flexible(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                  children: [
                    TextSpan(text: dayName),
                    TextSpan(
                      text: ' · $formattedDate',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Quiet tracked caps (the settings group-label treatment):
            // uppercase, wide tracking, faint ink — no chip behind it.
            Text(
              badgeText.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                color: AppTheme.groupLabelColorOf(scheme),
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(SelectedDayHeaderDelegate oldDelegate) =>
      oldDelegate.dayName != dayName ||
      oldDelegate.formattedDate != formattedDate ||
      oldDelegate.classCount != classCount ||
      oldDelegate.totalHours != totalHours;
}
