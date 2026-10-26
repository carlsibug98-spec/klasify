import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pill.dart';

class FirstRunOptions extends StatelessWidget {
  const FirstRunOptions({
    super.key,
    required this.onScan,
    required this.onAdd,
    this.showExample = false,
  });

  final VoidCallback onScan;
  final VoidCallback onAdd;

  /// Preview mode used by the onboarding tour: the tiles sit on a quiet
  /// panel with the detected-class example card beneath — what a scan
  /// produces at review time. The real first-run home keeps the bare tiles.
  final bool showExample;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _OptionTile(
              icon: Icons.photo_camera_outlined,
              title: 'Scan it',
              subtitle: 'Photo or PDF',
              background: scheme.primary,
              foreground: scheme.onPrimary,
              subtitleColor: scheme.onPrimary.withValues(alpha: 0.78),
              onTap: onScan,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _OptionTile(
              icon: Icons.add,
              title: 'Add by hand',
              subtitle: 'One class at a time',
              background: scheme.surface,
              foreground: scheme.onSurface,
              subtitleColor: scheme.onSurfaceVariant,
              border: scheme.outlineVariant,
              onTap: onAdd,
            ),
          ),
        ],
      ),
    );
    if (!showExample) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [tiles],
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [tiles, const SizedBox(height: 12), const _ExampleCard()],
      ),
    );
  }
}

/// The detected-class example card of the preview mode: what a scanned
/// class looks like at review time — the subject with a "Check room"
/// review pill, then the parsed day/time/room meta.
class _ExampleCard extends StatelessWidget {
  const _ExampleCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Expanded keeps the pill pinned to the card's far edge; at
          // extreme text scale the subject wraps instead of overflowing.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Data Structures',
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pill(
                label: 'Check room',
                background: scheme.tertiaryContainer,
                foreground: scheme.onTertiaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Mon · 10:30 AM - 12:00 PM · Room 211',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two first-run tiles: an icon block over the label pair, decked
/// in black (Scan it) or white with a hairline border (Add by hand).
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.foreground,
    required this.subtitleColor,
    required this.onTap,
    this.border,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color background;
  final Color foreground;
  final Color subtitleColor;
  final Color? border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      side: border == null ? BorderSide.none : BorderSide(color: border!),
    );
    return Semantics(
      button: true,
      child: Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 26, color: foreground),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.bodyLarge?.copyWith(
                          color: foreground,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: subtitleColor,
                          fontSize: 13,
                          height: 1.38,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
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
