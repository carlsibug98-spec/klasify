import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tone of an inline status message on a settings-style screen.
enum StatusKind { neutral, success, warning, error }

/// Inline status message. Screens use this for results of an action that
/// stays on the page (reminder toggles, backup results). Transient results
/// that do not stay on the page use showAppNotification instead.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    required this.kind,
    required this.onDismiss,
  });

  final String message;
  final StatusKind kind;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground, icon) = switch (kind) {
      StatusKind.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
      StatusKind.warning => (
        AppTheme.warningBackgroundOf(context),
        AppTheme.warningForegroundOf(context),
        Icons.warning_amber_rounded,
      ),
      StatusKind.success => (
        AppTheme.successBackgroundOf(context),
        AppTheme.successForegroundOf(context),
        Icons.check_circle_outline_rounded,
      ),
      StatusKind.neutral => (
        scheme.surfaceContainerHigh,
        scheme.onSurface,
        Icons.info_outline_rounded,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, color: foreground, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Dismiss message',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  Icons.close_rounded,
                  color: foreground.withValues(alpha: 0.7),
                  size: 18,
                ),
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
