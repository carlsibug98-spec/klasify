import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../models/class_item.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/compose_colors.dart';
import '../models/import_draft.dart';
import '../../../widgets/pill.dart';

enum ImportScanStage {
  idle('', '', 0),
  preparing('Preparing your timetable…', 'Preparing file', 1),
  detectingGrid('Detecting the timetable layout…', 'Detecting grid', 2),
  readingPdf('Scanning timetable pages…', 'Scanning PDF', 2),
  readingText('Reading timetable text…', 'Reading text', 3),
  assembling('Organizing classes for review…', 'Organizing results', 4),
  failed('Scan failed', 'Scan failed', 0);

  final String label;
  final String shortLabel;
  final int order;

  const ImportScanStage(this.label, this.shortLabel, this.order);
}

/// Shows a platform-adaptive confirmation before stopping the OCR scan.
Future<bool> showCancelScanConfirmation(BuildContext context) async {
  final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
  if (isIOS) {
    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Stop this scan?'),
        message: const Text(
          'Progress so far will be discarded. Your file stays selected, so you can scan again any time.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(sheetContext).pop(true),
            child: Semantics(
              label: 'Stop Scan',
              child: const Text('Stop Scan'),
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(false),
          child: Semantics(
            label: 'Keep Scanning',
            child: const Text('Keep Scanning'),
          ),
        ),
      ),
    );
    return result ?? false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => const _AndroidCancelConfirmationSheet(),
  );
  return result ?? false;
}

class _AndroidCancelConfirmationSheet extends StatelessWidget {
  const _AndroidCancelConfirmationSheet();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Adapts to the theme like every other sheet in the app: the scan screen
    // it appears over is adaptive (light in light mode), so an always-dark
    // sheet clashed there. The dark branch is the shared compose palette;
    // the light branch uses scheme roles, mirroring the scan card's mapping.
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? ComposeColors.of(context).bannerSurface
        : scheme.surfaceContainer;
    final grabberColor = isDark
        ? ComposeColors.of(context).raised
        : scheme.onSurfaceVariant;
    final iconCircle = isDark
        ? ComposeColors.of(context).errorContainer
        : scheme.errorContainer;
    final iconColor = isDark ? ComposeColors.of(context).error : scheme.onErrorContainer;
    final titleColor = isDark ? Colors.white : scheme.onSurface;
    final bodyColor = isDark ? ComposeColors.of(context).muted : scheme.onSurfaceVariant;
    final chipColor = isDark
        ? ComposeColors.of(context).field
        : scheme.surfaceContainerHigh;
    final confirmButton = isDark ? ComposeColors.of(context).error : scheme.error;
    final onConfirmButton = isDark ? ComposeColors.of(context).onError : scheme.onError;

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + media.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: grabberColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconCircle,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              color: iconColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Stop this scan?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: titleColor,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Progress so far will be discarded. Your file stays selected, so you can scan again any time.',
            style: TextStyle(fontSize: 15, color: bodyColor, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: chipColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.check_rounded, size: 18, color: bodyColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No classes will be added',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: chipColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.refresh_rounded, size: 18, color: bodyColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Scanning again starts from the beginning',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: confirmButton,
                foregroundColor: onConfirmButton,
                elevation: 0,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Semantics(
                label: 'Stop Scan',
                button: true,
                child: const Text('Stop Scan'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: bodyColor,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Semantics(
                label: 'Keep Scanning',
                button: true,
                child: const Text('Keep Scanning'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImportScanProgress extends StatefulWidget {
  final ImportScanStage stage;
  final double progress;
  final String detail;
  final VoidCallback? onCancel;
  final bool isPdf;
  final bool isCancelling;
  final String? filePath;

  const ImportScanProgress({
    super.key,
    required this.stage,
    required this.progress,
    required this.detail,
    this.onCancel,
    this.isPdf = false,
    this.isCancelling = false,
    this.filePath,
  });

  @override
  State<ImportScanProgress> createState() => _ImportScanProgressState();
}

class _ImportScanProgressState extends State<ImportScanProgress> {
  static const _visibleStages = [
    ImportScanStage.preparing,
    ImportScanStage.detectingGrid,
    ImportScanStage.readingText,
    ImportScanStage.assembling,
  ];
  static const _pdfStages = [
    ImportScanStage.preparing,
    ImportScanStage.readingPdf,
    ImportScanStage.assembling,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final progress = widget.progress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();
    final visibleStages = widget.isPdf ? _pdfStages : _visibleStages;
    final animationDuration = AppTheme.motionDuration(
      context,
      AppTheme.motionStandard,
    );
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? ComposeColors.of(context).surface : scheme.surfaceContainer;
    final fieldColor = isDark
        ? ComposeColors.of(context).field
        : scheme.surfaceContainerHigh;
    final raisedColor = isDark
        ? ComposeColors.of(context).raised
        : scheme.surfaceContainerHighest;
    final textColor = isDark ? Colors.white : scheme.onSurface;
    final secondaryTextColor = isDark
        ? ComposeColors.of(context).muted
        : scheme.onSurfaceVariant;
    // Skipped rows are text, not chrome: the old dark value (#6B6B6B) read
    // 3.09:1 on the field chips — below AA. hint is the dimmest token that
    // passes while keeping the de-emphasized hierarchy.
    final skippedColor = isDark ? ComposeColors.of(context).hint : scheme.outline;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.filePath != null) ...[
            _SelectedFileCard(
              filePath: widget.filePath!,
              isPdf: widget.isPdf,
              fieldColor: fieldColor,
              tileColor: raisedColor,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
            ),
            const SizedBox(height: 20),
          ],
          if (widget.isCancelling) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Semantics(
                      label: 'Cancelling scan',
                      liveRegion: true,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            // Follows the card's theme, like the progress
                            // bar below (this used to be hardcoded white
                            // and vanished on the light card).
                            isDark ? Colors.white : scheme.primary,
                          ),
                          backgroundColor: raisedColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Cancelling scan',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Stopping after the current step. No classes will be added.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: secondaryTextColor,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final step in visibleStages) ...[
                      _CancellingStepItem(
                        item: step,
                        current: widget.stage,
                        fieldColor: fieldColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                        skippedColor: skippedColor,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scanning',
                        style: textTheme.bodySmall?.copyWith(
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.stage.shortLabel,
                        style: textTheme.bodyLarge?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$percent%',
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 15,
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Scan progress',
              value: '$percent%',
              liveRegion: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: progress),
                  duration: animationDuration,
                  curve: AppTheme.motionLinear,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    color: isDark ? Colors.white : scheme.primary,
                    backgroundColor: raisedColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visibleStages.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 8,
                      height: 2,
                      margin: const EdgeInsets.only(top: 12),
                      color: widget.stage.order >= visibleStages[i].order
                          ? (isDark ? Colors.white : scheme.primary)
                          : raisedColor,
                    ),
                  Expanded(
                    child: _ScanStep(
                      item: visibleStages[i],
                      current: widget.stage,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.detail,
              style: textTheme.bodySmall?.copyWith(color: secondaryTextColor),
            ),
            if (widget.onCancel != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: widget.onCancel,
                    style: FilledButton.styleFrom(
                      backgroundColor: fieldColor,
                      foregroundColor: textColor,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: Semantics(
                      label: 'Cancel scan',
                      button: true,
                      child: const Text('Cancel scan'),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SelectedFileCard extends StatelessWidget {
  final String filePath;
  final bool isPdf;
  final Color fieldColor;
  final Color tileColor;
  final Color textColor;
  final Color secondaryTextColor;

  const _SelectedFileCard({
    required this.filePath,
    required this.isPdf,
    required this.fieldColor,
    required this.tileColor,
    required this.textColor,
    required this.secondaryTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              color: textColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected file',
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.basename(filePath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
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

class _CancellingStepItem extends StatelessWidget {
  final ImportScanStage item;
  final ImportScanStage current;
  final Color fieldColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color skippedColor;

  const _CancellingStepItem({
    required this.item,
    required this.current,
    required this.fieldColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.skippedColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = item.order < current.order;
    final isFinishing = item == current;

    final IconData icon;
    final Color iconColor;
    final Color titleColor;
    final String tagText;
    final Color tagColor;
    final FontWeight tagWeight;

    if (isDone) {
      icon = Icons.check_rounded;
      iconColor = secondaryTextColor;
      titleColor = textColor;
      tagText = 'Done';
      tagColor = skippedColor;
      tagWeight = FontWeight.w600;
    } else if (isFinishing) {
      icon = Icons.schedule_rounded;
      iconColor = textColor;
      titleColor = textColor;
      tagText = 'Finishing';
      tagColor = textColor;
      tagWeight = FontWeight.w700;
    } else {
      icon = Icons.close_rounded;
      iconColor = skippedColor;
      titleColor = skippedColor;
      tagText = 'Skipped';
      tagColor = skippedColor;
      tagWeight = FontWeight.w600;
    }

    return Semantics(
      label: '${item.shortLabel}, $tagText',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: fieldColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.shortLabel,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 15,
                  fontWeight: isFinishing ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              tagText,
              style: TextStyle(
                color: tagColor,
                fontSize: 13,
                fontWeight: tagWeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanStep extends StatelessWidget {
  final ImportScanStage item;
  final ImportScanStage current;

  const _ScanStep({required this.item, required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final complete = item.order < current.order;
    final active = item == current;
    final filled = complete || active;
    final isDark = theme.brightness == Brightness.dark;
    return Semantics(
      excludeSemantics: true,
      label:
          '${item.shortLabel}${active
              ? ', current step'
              : complete
              ? ', complete'
              : ''}',
      child: Column(
        children: [
          AnimatedContainer(
            duration: AppTheme.motionDuration(context, AppTheme.motionStandard),
            curve: AppTheme.motionEaseOut,
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (isDark ? Colors.white : scheme.primary)
                  : (isDark
                        ? ComposeColors.of(context).raised
                        : scheme.surfaceContainerHigh),
            ),
            child: Icon(
              complete
                  ? Icons.check_rounded
                  : active
                  ? Icons.document_scanner_outlined
                  : Icons.circle_outlined,
              size: 14,
              color: filled
                  ? (isDark ? Colors.black : scheme.onPrimary)
                  : (isDark ? ComposeColors.of(context).muted : scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.shortLabel,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: theme.textTheme.labelSmall?.copyWith(
              height: 1.25,
              color: active
                  ? (isDark ? Colors.white : scheme.onSurface)
                  : (isDark ? ComposeColors.of(context).muted : scheme.onSurfaceVariant),
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ImportAttentionBanner extends StatelessWidget {
  final String title;
  final String message;
  final bool blocking;
  final String? footer;
  final VoidCallback? onDismiss;
  final String dismissLabel;

  const ImportAttentionBanner({
    super.key,
    required this.title,
    required this.message,
    this.blocking = false,
    this.footer,
    this.onDismiss,
    this.dismissLabel = 'Dismiss',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final background = blocking
        ? scheme.errorContainer
        : AppTheme.warningBackgroundOf(context);
    final foreground = blocking
        ? scheme.onErrorContainer
        : AppTheme.warningForegroundOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      // Option-C edge (holdouts board §4): semantic fill stays, the banner
      // gains the same hairline + ambient as every content card.
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.fromBorderSide(AppTheme.cardBorderSideOf(scheme)),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Semantics(
        liveRegion: blocking,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  blocking
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        message,
                        style: textTheme.bodySmall?.copyWith(color: foreground),
                      ),
                      if (footer != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          footer!,
                          style: textTheme.bodySmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (onDismiss != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: foreground),
                  onPressed: onDismiss,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(dismissLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ImportStatCard extends StatelessWidget {
  final int value;
  final String label;
  final IconData icon;
  final bool attention;

  const ImportStatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final flagged = attention && value > 0;
    final foreground = flagged ? scheme.onTertiaryContainer : scheme.onSurface;
    final muted = flagged
        ? scheme.onTertiaryContainer
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(14),
      // Option-C edge (holdouts board §3): stat cards join the card
      // family; the flagged one keeps its amber fill under the hairline.
      decoration: BoxDecoration(
        color: flagged ? scheme.tertiaryContainer : AppTheme.cardFillColorOf(scheme),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.fromBorderSide(AppTheme.cardBorderSideOf(scheme)),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: flagged ? scheme.onTertiaryContainer : scheme.primary,
          ),
          const SizedBox(height: AppTheme.itemGap),
          Text(
            '$value',
            style: textTheme.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ImportDraftCard extends StatelessWidget {
  final ImportDraft draft;
  final ImportNote? note;
  final bool unknownRoom;
  final bool ocrReviewNeeded;
  final String? ocrReviewLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const ImportDraftCard({
    super.key,
    required this.draft,
    required this.note,
    required this.unknownRoom,
    required this.ocrReviewNeeded,
    this.ocrReviewLabel,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isOverlap = note?.kind == ImportNoteKind.conflict;
    final Color? flag = note != null
        ? isOverlap
              ? scheme.tertiary
              : scheme.error
        : (unknownRoom || ocrReviewNeeded ? scheme.tertiary : null);
    final invalid = note != null && !isOverlap;
    final flagged = flag != null;
    final background = invalid
        ? scheme.errorContainer
        : flagged
        ? scheme.tertiaryContainer
        : scheme.surfaceContainer;
    final foreground = invalid
        ? scheme.onErrorContainer
        : flagged
        ? scheme.onTertiaryContainer
        : scheme.onSurface;
    final muted = textTheme.bodySmall?.copyWith(
      color: flagged
          ? foreground.withValues(alpha: .86)
          : scheme.onSurfaceVariant,
    );
    final professor =
        draft.professor.trim().isEmpty ||
            draft.professor.trim() == unspecifiedProfessor
        ? ''
        : draft.professor.trim();
    return Card(
      // The vertical rhythm lives in the SwipeActions padding at the call
      // site, so the gap collapses together with the row on removal.
      margin: EdgeInsets.zero,
      color: background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        // Option-C hairline (holdouts board §3): the review cards are
        // content cards — they keep the themed Card fill and gain the
        // same edge the schedule cards carry.
        side: AppTheme.cardBorderSideOf(scheme),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                button: true,
                onTap: onTap,
                excludeSemantics: true,
                label:
                    'Edit ${draft.subject.isEmpty ? 'unnamed class' : draft.subject}, ${dayNames[draft.day - 1]}, ${formatMinutes(draft.start)} to ${formatMinutes(draft.end)}${note == null ? '' : ', ${note!.text}'}${unknownRoom ? ', room needs confirmation' : ''}${ocrReviewNeeded ? ', scanned text needs checking' : ''}',
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: foreground.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                dayNames[draft.day - 1].substring(0, 3),
                                style: textTheme.labelMedium?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${formatMinutes(draft.start)} – ${formatMinutes(draft.end)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelLarge?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              draft.subject.isEmpty
                                  ? 'Unnamed class'
                                  : draft.subject,
                              style: textTheme.titleMedium?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (ocrReviewNeeded)
                              Pill(
                                label: ocrReviewLabel ?? 'Check scanned text',
                                background: scheme.tertiaryContainer,
                                foreground: scheme.onTertiaryContainer,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _DraftMeta(
                              icon: Icons.location_on_outlined,
                              label: unknownRoom
                                  ? 'Room to confirm'
                                  : formatRoom(draft.room),
                              color: flagged
                                  ? foreground
                                  : scheme.onSurfaceVariant,
                              style: muted,
                            ),
                            if (professor.isNotEmpty)
                              _DraftMeta(
                                icon: Icons.person_outline_rounded,
                                label: professor,
                                color: flagged
                                    ? foreground
                                    : scheme.onSurfaceVariant,
                                style: muted,
                              ),
                          ],
                        ),
                        if (note != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            note!.text,
                            style: textTheme.bodySmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip:
                  'Remove ${draft.subject.isEmpty ? 'unnamed class' : draft.subject} from import',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: flagged ? foreground : scheme.onSurfaceVariant,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftMeta extends StatelessWidget {
  const _DraftMeta({
    required this.icon,
    required this.label,
    required this.color,
    required this.style,
  });

  final IconData icon;
  final String label;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    ],
  );
}
