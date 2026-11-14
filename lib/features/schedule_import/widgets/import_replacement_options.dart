import 'package:flutter/material.dart';

import '../../../models/class_item.dart';
import '../../../theme/app_theme.dart';
import '../models/import_mode.dart';

/// Lets the user choose how the reviewed import updates the saved schedule.
class ImportReplacementOptions extends StatelessWidget {
  const ImportReplacementOptions({
    super.key,
    required this.existing,
    required this.mode,
    required this.selectedIds,
    required this.working,
    required this.onModeChanged,
    required this.onToggle,
  });

  /// Saved classes offered for replacement.
  final List<ClassItem> existing;

  /// Current import mode.
  final ImportMode mode;

  /// Ids of saved classes checked for replacement.
  final Set<int> selectedIds;

  /// True while an import is being saved; all controls are disabled.
  final bool working;

  /// Called when the user picks a different mode.
  final ValueChanged<ImportMode> onModeChanged;

  /// Called when the user checks or unchecks a saved class.
  final void Function(ClassItem item, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    if (existing.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    Widget option(ImportMode value, String title, String subtitle) {
      final selected = mode == value;
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: InkWell(
          onTap: working ? null : () => onModeChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Radio<ImportMode>(value: value),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (value == ImportMode.add) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Recommended',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RadioGroup<ImportMode>(
      groupValue: mode,
      onChanged: (value) {
        if (!working && value != null) onModeChanged(value);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import options',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Choose how these classes should update your saved schedule.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          option(
            ImportMode.add,
            'Add to schedule',
            'Keep saved classes and add these classes.',
          ),
          option(
            ImportMode.replaceAll,
            'Replace entire schedule',
            'Remove every saved class and use this import.',
          ),
          if (mode == ImportMode.replaceAll)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All saved classes will be removed after you confirm.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          option(
            ImportMode.replaceSelected,
            'Choose classes to replace',
            'Select saved classes to remove before importing.',
          ),
          if (mode == ImportMode.replaceSelected) ...[
            const Divider(height: 16),
            for (final item in existing)
              CheckboxListTile(
                value: item.id != null && selectedIds.contains(item.id),
                onChanged: working || item.id == null
                    ? null
                    : (value) => onToggle(item, value ?? false),
                title: Text(
                  item.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${item.dayName} · ${item.timeRange} · ${formatRoom(item.room)}',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            if (selectedIds.isEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                ),
                child: Text(
                  'Select at least one saved class, or switch to Add to schedule.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                ),
                child: Text(
                  '${selectedIds.length} saved ${selectedIds.length == 1 ? 'class' : 'classes'} will be removed after confirmation.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
