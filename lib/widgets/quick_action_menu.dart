import 'package:flutter/material.dart';

/// Floating quick action menu offering Add Class and Import Timetable options.
class QuickActionMenu extends StatelessWidget {
  const QuickActionMenu({
    super.key,
    required this.onAddClass,
    required this.importLabel,
    required this.onImportClass,
  });

  final VoidCallback onAddClass;
  final String importLabel;
  final VoidCallback onImportClass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 4,
      shadowColor: scheme.shadow.withValues(alpha: .16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 188,
              height: 48,
              child: QuickActionMenuItem(
                icon: Icons.add_rounded,
                label: 'Add class',
                onPressed: onAddClass,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 188,
              height: 48,
              child: QuickActionMenuItem(
                icon: Icons.upload_file_outlined,
                label: importLabel,
                onPressed: onImportClass,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single item within the QuickActionMenu.
class QuickActionMenuItem extends StatelessWidget {
  const QuickActionMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurface),
            const SizedBox(width: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
