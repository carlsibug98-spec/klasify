import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';

/// Shows which image or PDF is currently selected for import.
class ImportSelectedFileTile extends StatelessWidget {
  const ImportSelectedFileTile({super.key, required this.path});

  /// Absolute path of the selected file.
  final String path;

  @override
  Widget build(BuildContext context) {
    final isPdf = p.extension(path).toLowerCase() == '.pdf';
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      // Option-C edge (holdouts board §5): the file tile joins the card
      // family — card fill + hairline + ambient; the icon chip lifts one
      // step so it survives the new fill.
      decoration: BoxDecoration(
        color: AppTheme.cardFillColorOf(scheme),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.fromBorderSide(AppTheme.cardBorderSideOf(scheme)),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.brightness == Brightness.dark
                  ? scheme.surfaceContainerHigh
                  : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppTheme.controlRadius),
            ),
            child: Icon(
              isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected file',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
