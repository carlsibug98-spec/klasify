import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// One day in the week strip: abbreviation, date in a circle, and class count label.
class WeekdayTile extends StatelessWidget {
  const WeekdayTile({
    super.key,
    required this.date,
    required this.name,
    required this.classCount,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final String name;
  final int classCount;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label:
          '$name, ${MaterialLocalizations.of(context).formatFullDate(date)}${isToday ? ', today' : ''}, $classCount ${classCount == 1 ? 'class' : 'classes'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.substring(0, 3),
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: AppTheme.motionDuration(context, AppTheme.motionFast),
                curve: AppTheme.motionEaseOut,
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: isToday && !selected
                      ? Border.all(color: scheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${date.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
