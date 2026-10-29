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
  final effectiveDuration = duration ?? defaultDuration;
  final hasAction = actionLabel != null && onAction != null;
  // SnackBarAction carries its own 48px tap target, which makes action toasts
  // taller than the rest. Embedding the action in the content row keeps the
  // padding and height identical to every other notification.
  final actionButton = hasAction
      ? TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 20),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            foregroundColor: kind == AppNotificationKind.info
                ? AppTheme.toastActionFor(scheme)
                : foregroundColor,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
            unawaited(onAction());
          },
          child: Text(
            actionLabel,
            style: TextStyle(
              color: kind == AppNotificationKind.info
                  ? AppTheme.toastActionFor(scheme)
                  : foregroundColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        )
      : null;
  final action = null;
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
      if (actionButton != null) ...[
        const SizedBox(width: 8),
        actionButton,
      ],
    ],
  );
  // Replacing an in-flight toast drops it instantly: after the user has
  // acted (e.g. tapped Undo), the confirmation should snap in, not wait
  // behind the previous toast's remaining dwell time.
  if (replaceCurrent) {
    messenger.removeCurrentSnackBar();
  }
  messenger.showSnackBar(
    SnackBar(
      content: notificationContent,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      // Flutter makes action snackbars persist forever by default, so an
      // Undo toast would never leave the screen. Every notification here is
      // finite and follows its duration.
      persist: false,
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
