import 'package:flutter/material.dart';

import '../models/class_item.dart';
import '../theme/app_theme.dart';

/// Single-row weekday selector (Mon … Sun) used by the add/edit form and the
/// onboarding preview. Pass a null [onChanged] for a read-only preview.
class DayChips extends StatelessWidget {
  /// 1 = Monday … 7 = Sunday.
  final int selected;
  final ValueChanged<int>? onChanged;

  /// How many days to show (7 = Mon–Sun).
  final int count;

  const DayChips({
    super.key,
    required this.selected,
    this.onChanged,
    this.count = 7,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const chipWidth = 48.0;
        const gap = 6.0;
        final fits = constraints.maxWidth >= count * (chipWidth + gap) - gap;
        final chips = [
          for (var day = 1; day <= count; day++)
            Semantics(
              button: onChanged != null,
              selected: day == selected,
              label: dayNames[day - 1],
              child: AnimatedContainer(
                duration: AppTheme.motionDuration(context, AppTheme.motionFast),
                curve: AppTheme.motionEaseOut,
                // Unselected days are muted so the selected day stands out.
                decoration: BoxDecoration(
                  color: day == selected
                      ? scheme.primary
                      : scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                    onTap: onChanged == null ? null : () => onChanged!(day),
                    child: SizedBox(
                      // In the scrollable layout, keep each touch target at
                      // least 48×48 logical pixels. In the fitting layout,
                      // Expanded distributes the available width evenly.
                      width: fits ? null : chipWidth,
                      height: 48,
                      child: Center(
                        child: Text(
                          dayNames[day - 1].substring(0, 3),
                          maxLines: 1,
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: day == selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: day == selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ];

        if (fits) {
          return Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(child: chips[i]),
              ],
            ],
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                chips[i],
              ],
            ],
          ),
        );
      },
    );
  }
}
