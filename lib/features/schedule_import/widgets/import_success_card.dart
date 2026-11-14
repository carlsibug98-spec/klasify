import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Confirms a completed import and offers the two follow-up actions.
class ImportSuccessCard extends StatelessWidget {
  const ImportSuccessCard({
    super.key,
    required this.message,
    required this.onViewSchedule,
    required this.onImportAnother,
  });

  /// Success copy built by `ImportSaveService.successMessage`.
  final String message;

  /// Returns to the app shell and opens the Week tab.
  final VoidCallback onViewSchedule;

  /// Clears the completed message so a new file can be picked.
  final VoidCallback onImportAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.onSecondaryContainer,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Import complete',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: AppTheme.itemGap,
              runSpacing: AppTheme.itemGap,
              children: [
                FilledButton.icon(
                  onPressed: onViewSchedule,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: const Text('View schedule'),
                ),
                OutlinedButton.icon(
                  onPressed: onImportAnother,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Import another'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
