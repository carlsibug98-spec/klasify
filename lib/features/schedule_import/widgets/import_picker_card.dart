import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'import_selected_file_tile.dart';

/// The empty-state card that lets the user choose a timetable file or enter
/// classes manually.
class ImportPickerCard extends StatelessWidget {
  const ImportPickerCard({
    super.key,
    required this.selectedFilePath,
    required this.working,
    required this.onScan,
    required this.onChooseFile,
    required this.onManual,
  });

  /// Path shown in the selected-file tile, or null before a file is picked.
  final String? selectedFilePath;

  /// True while an import is being saved; the picker disables file actions.
  final bool working;

  /// Opens the current file in the scanner.
  final VoidCallback onScan;

  /// Opens the file picker.
  final VoidCallback onChooseFile;

  /// Leaves the import flow for manual class entry.
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      color: scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  ),
                  child: Icon(
                    Icons.table_view_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.offline_bolt_outlined,
                        size: 16,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Works offline',
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Bring in your timetable',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a schedule image or PDF, then review every class before saving.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final format in ['PDF', 'JPG', 'PNG', 'WEBP'])
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                    ),
                    child: Text(
                      format,
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                  ),
                  child: Text(
                    'Up to 20 MB',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (selectedFilePath != null) ...[
              const SizedBox(height: 16),
              ImportSelectedFileTile(path: selectedFilePath!),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: working ? null : onScan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan timetable'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: selectedFilePath != null
                  ? OutlinedButton.icon(
                      onPressed: working ? null : onChooseFile,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Choose another file'),
                    )
                  : FilledButton.icon(
                      onPressed: working ? null : onChooseFile,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Choose a timetable'),
                    ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onManual,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(
                  working ? 'Enter manually instead' : 'Enter classes manually',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your timetable stays on your device. No internet connection '
              'is needed.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
