import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database_helper.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../services/reminder_service.dart';
import 'app_notification.dart';

/// Deletes a single class immediately and offers a five-second undo action.
/// Undo uses the app-level messenger, so it survives route changes.
Future<bool> deleteClassWithUndo(BuildContext context, ClassItem item) async {
  final id = item.id;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (id == null || messenger == null) return false;
  final scheme = Theme.of(context).colorScheme;

  // Read the marks first: deleting the class also deletes them.
  List<ClassStatusEntry> marks = const [];
  try {
    marks = await DatabaseHelper.instance.statusesForClass(id);
    final deleted = await DatabaseHelper.instance.delete(id);
    if (deleted == 0) throw StateError('Class was not found.');
  } catch (error, stackTrace) {
    debugPrint('Class delete failed: $error\n$stackTrace');
    showAppNotificationOnMessenger(
      messenger,
      scheme,
      'Could not delete the class. Please try again.',
      kind: AppNotificationKind.error,
    );
    return false;
  }

  // The destructive action really happened — confirm it physically.
  HapticFeedback.mediumImpact();

  var remindersOk = true;
  try {
    await ReminderService.instance.sync();
  } catch (error, stackTrace) {
    remindersOk = false;
    debugPrint('Reminder sync after delete failed: $error\n$stackTrace');
  }

  showAppNotificationOnMessenger(
    messenger,
    scheme,
    remindersOk
        ? 'Class deleted'
        : 'Class deleted, but reminders could not be updated.',
    kind: remindersOk
        ? AppNotificationKind.info
        : AppNotificationKind.warning,
    duration: const Duration(seconds: 5),
    actionLabel: 'Undo',
    onAction: () async {
      try {
        await DatabaseHelper.instance.restoreDeleted(item);
        if (marks.isNotEmpty) {
          await DatabaseHelper.instance.restoreClassStatuses(id, marks);
        }
        var restoredRemindersOk = true;
        try {
          await ReminderService.instance.sync();
        } catch (error, stackTrace) {
          restoredRemindersOk = false;
          debugPrint('Reminder sync after restore failed: $error\n$stackTrace');
        }
        showAppNotificationOnMessenger(
          messenger,
          scheme,
          restoredRemindersOk
              ? 'Class restored'
              : 'Class restored, but reminders could not be updated.',
          kind: restoredRemindersOk
              ? AppNotificationKind.success
              : AppNotificationKind.warning,
          replaceCurrent: true,
        );
      } catch (error, stackTrace) {
        debugPrint('Class restore failed: $error\n$stackTrace');
        showAppNotificationOnMessenger(
          messenger,
          scheme,
          "Couldn't restore. Add it again.",
          kind: AppNotificationKind.error,
        );
      }
    },
  );
  return true;
}
