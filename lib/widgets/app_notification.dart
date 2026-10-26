import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

enum AppNotificationKind { success, info, warning, error, loading }

void showAppNotification(
  BuildContext context,
  String message, {
  AppNotificationKind kind = AppNotificationKind.info,
  Duration? duration,
  bool persistent = false,
  String? actionLabel,
  Future<void> Function()? onAction,
  bool replaceCurrent = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  showAppNotificationOnMessenger(
    messenger,
    Theme.of(context).colorScheme,
    message,
    kind: kind,
    duration: duration,
    persistent: persistent,
    actionLabel: actionLabel,
    onAction: onAction,
    replaceCurrent: replaceCurrent,
  );
}

/// Uses the app-level messenger so feedback and Undo survive route changes.
void showAppNotificationOnMessenger(
  ScaffoldMessengerState messenger,
  ColorScheme scheme,
  String message, {
  AppNotificationKind kind = AppNotificationKind.info,
  Duration? duration,
  bool persistent = false,
  String? actionLabel,
  Future<void> Function()? onAction,
  bool replaceCurrent = false,
}) {
  final (backgroundColor, foregroundColor, icon) = switch (kind) {
    AppNotificationKind.success => (
      AppTheme.success,
      AppTheme.onSuccess,
      Icons.check_rounded,
    ),
    AppNotificationKind.error => (
      scheme.errorContainer,
      scheme.onErrorContainer,
      Icons.error_outline_rounded,
    ),
    AppNotificationKind.warning => (
      AppTheme.warningBackgroundFor(scheme),
      AppTheme.warningForegroundFor(scheme),
      Icons.warning_amber_rounded,
    ),
    AppNotificationKind.info || AppNotificationKind.loading => (
      scheme.inverseSurface,
      scheme.onInverseSurface,
      Icons.info_outline_rounded,
    ),
  };
  final defaultDuration = switch (kind) {
    AppNotificationKind.error => const Duration(seconds: 6),
    AppNotificationKind.warning => const Duration(seconds: 5),
    _ => const Duration(seconds: 3),
  };
  final effectiveDuration =
      duration ?? (persistent ? const Duration(days: 1) : defaultDuration);
  final action = actionLabel != null && onAction != null
      ? SnackBarAction(
          label: actionLabel,
          textColor: kind == AppNotificationKind.info
              ? AppTheme.toastActionFor(scheme)
              : foregroundColor,
          onPressed: () {
            HapticFeedback.lightImpact();
            // Acting on a toast dismisses it: the message has done its job,
            // and any follow-up toast (e.g. "Class restored") replaces it.
            messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
            unawaited(onAction());
          },
        )
      : null;
  final leading = kind == AppNotificationKind.loading
      ? SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
          ),
        )
      : Icon(icon, color: foregroundColor, size: 20);
  final notificationContent = Row(
    children: [
      leading,
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
  final content = action == null
      ? notificationContent
      : Builder(
          builder: (context) {
            // Reduced motion: keep the message and the Undo action (they
            // carry the information), drop the ticking bar and per-frame
            // countdown, like every other animation in the app.
            if (MediaQuery.of(context).disableAnimations) {
              return notificationContent;
            }
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: effectiveDuration.inMilliseconds.toDouble(),
                end: 0,
              ),
              duration: effectiveDuration,
              builder: (context, remainingMilliseconds, _) {
                final durationMilliseconds = effectiveDuration.inMilliseconds
                    .toDouble();
                final remainingSeconds = (remainingMilliseconds / 1000)
                    .ceil()
                    .clamp(0, 999);
                final progress = durationMilliseconds <= 0
                    ? 0.0
                    : (remainingMilliseconds / durationMilliseconds).clamp(
                        0.0,
                        1.0,
                      );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    notificationContent,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$actionLabel available',
                            style: TextStyle(
                              color: foregroundColor.withAlpha(210),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${remainingSeconds}s left',
                          style: TextStyle(
                            color: foregroundColor.withAlpha(210),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: foregroundColor.withAlpha(55),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          foregroundColor,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );

  // Replacing an in-flight toast drops it instantly: after the user has
  // acted (e.g. tapped Undo), the confirmation should snap in, not wait
  // behind the previous toast's remaining dwell time.
  if (replaceCurrent) {
    messenger.removeCurrentSnackBar();
  }
  messenger.showSnackBar(
    SnackBar(
      content: content,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      duration: effectiveDuration,
      elevation: 4,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      ),
      action: action,
      showCloseIcon: false,
      dismissDirection: DismissDirection.down,
    ),
  );
}

void dismissAppNotification(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.hideCurrentSnackBar();
}
