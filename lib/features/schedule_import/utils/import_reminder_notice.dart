import '../../../widgets/app_notification.dart';
import '../services/import_save_service.dart';

/// The reminder follow-up shown after an import save.
class ImportReminderNotice {
  const ImportReminderNotice({required this.message, required this.kind});

  final String message;
  final AppNotificationKind kind;
}

/// The notice [result] still needs, or null when reminders are healthy.
///
/// Keeping the choice pure lets every combination be checked without a
/// notification plugin or a fake service.
ImportReminderNotice? importReminderNotice(ImportSaveResult result) {
  if (!result.remindersUpdated) {
    return const ImportReminderNotice(
      message:
          'Classes saved, but reminders could not be updated. '
          'Check notification permission.',
      kind: AppNotificationKind.warning,
    );
  }
  if (!result.remindersEnabled) {
    return const ImportReminderNotice(
      message:
          'Turn on class reminders in Settings to get notifications when '
          'the app is closed.',
      kind: AppNotificationKind.info,
    );
  }
  return null;
}
