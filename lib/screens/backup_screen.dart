import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../services/auto_backup_service.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../utils/schedule_backup_codec.dart';
import '../widgets/app_notification.dart';

/// Offline JSON backup/restore. Restore validates the entire file and replaces
/// the schedule atomically only after the user confirms the destructive action.
///
/// The automatic backup writes the same payload format as the manual export,
/// so every restore path accepts both files interchangeably.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

enum _BackupStatus { success, warning }

class _BackupScreenState extends State<BackupScreen> {
  bool _working = false;

  Future<void> _export() async {
    if (_working) return;
    setState(() {
      _working = true;
    });
    try {
      final classes = await DatabaseHelper.instance.getAll();
      final events = await DatabaseHelper.instance.getAllEvents();
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save class schedule backup',
        fileName: 'klasify_backup.json',
        mimeType: 'application/json',
        bytes: ScheduleBackupCodec.encode(classes, events: events),
      );
      if (mounted) {
        if (saved == null) {
          showAppNotification(
            context,
            'Export cancelled. Your schedule was not changed.',
            kind: AppNotificationKind.info,
          );
        } else {
          showAppNotification(
            context,
            'Backup exported (${classes.length} ${classes.length == 1 ? 'class' : 'classes'}, ${events.length} ${events.length == 1 ? 'event' : 'events'}).',
            kind: AppNotificationKind.success,
          );
        }
      }
    } catch (e, st) {
      debugPrint('Schedule export failed: $e\n$st');
      if (mounted) {
        showAppNotification(
          context,
          'Could not export the backup. Please try again.',
          kind: AppNotificationKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreFromFile() async {
    if (_working) return;
    setState(() {
      _working = true;
    });
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted || picked == null) return;
      final size = picked.lengthSync() ?? await picked.length() ?? 0;
      if (size > ScheduleBackupCodec.maxBytes) {
        throw const FormatException('Backup file exceeds the 2 MB limit.');
      }
      final data = await picked.readAsBytes();
      final backup = ScheduleBackupCodec.decode(data);
      if (!mounted) return;
      await _confirmAndRestore(backup, source: 'backup file');
    } catch (e, st) {
      debugPrint('Schedule restore failed: $e\n$st');
      if (mounted) {
        showAppNotification(
          context,
          e is FormatException
              ? '${e.message} Your schedule was not changed.'
              : 'Could not restore the backup. Your schedule wasn\'t changed.',
          kind: AppNotificationKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreFromAutoBackup() async {
    if (_working) return;
    setState(() {
      _working = true;
    });
    try {
      final file = await AutoBackupService.instance.loadMainBackupFile();
      if (!mounted) return;
      if (file == null) {
        showAppNotification(
          context,
          'No automatic backup has been saved yet.',
          kind: AppNotificationKind.info,
        );
        return;
      }
      final backup = ScheduleBackupCodec.decode(await file.readAsBytes());
      if (!mounted) return;
      await _confirmAndRestore(backup, source: 'automatic backup');
    } catch (e, st) {
      debugPrint('Automatic backup restore failed: $e\n$st');
      if (mounted) {
        showAppNotification(
          context,
          e is FormatException
              ? '${e.message} Your schedule was not changed.'
              : 'Could not restore the backup. Your schedule wasn\'t changed.',
          kind: AppNotificationKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Shared destructive path for both restore sources: confirm, replace the
  /// schedule atomically, then refresh reminders.
  Future<void> _confirmAndRestore(
    ScheduleBackup backup, {
    required String source,
  }) async {
    final classes = backup.classes;
    final events = backup.events;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace current schedule?'),
        content: Text(
          'This $source contains ${classes.length} ${classes.length == 1 ? 'class' : 'classes'} and ${events.length} ${events.length == 1 ? 'event' : 'events'}. Restoring it replaces all currently saved classes and events. Export a backup first if you want to keep them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace schedule'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      showAppNotification(
        context,
        'Restore cancelled. Your schedule was not changed.',
        kind: AppNotificationKind.info,
      );
      return;
    }
    final count = await DatabaseHelper.instance.replaceAll(classes);
    await DatabaseHelper.instance.replaceAllEvents(events);
    var status = 'Restored $count ${count == 1 ? 'class' : 'classes'} and ${events.length} ${events.length == 1 ? 'event' : 'events'}.';
    var kind = _BackupStatus.success;
    try {
      await ReminderService.instance.sync();
    } catch (error, stackTrace) {
      debugPrint(
        'Backup restored, but reminder sync failed: $error\n$stackTrace',
      );
      status += ' Class reminders could not be refreshed.';
      kind = _BackupStatus.warning;
    }
    if (mounted) {
      showAppNotification(
        context,
        status,
        kind: kind == _BackupStatus.warning
            ? AppNotificationKind.warning
            : AppNotificationKind.success,
      );
    }
  }

  Future<void> _toggleAutoBackup(bool value) async {
    await AutoBackupService.instance.setEnabled(value);
    if (mounted) setState(() {});
  }

  /// One-line status under the toggle, covering every service state.
  String _autoStatusLine(AutoBackupService auto) {
    if (!auto.enabled) {
      return 'Backups are paused. Turn them on to keep a fresh copy.';
    }
    if (auto.lastError != null) {
      return 'The last attempt failed. Klasify retries on the next change.';
    }
    if (auto.busy) return 'Saving a fresh backup…';
    final at = auto.lastBackupAt;
    if (at == null) return 'Klasify saves a copy after your next change.';
    final count = auto.lastClassCount ?? 0;
    return 'Last saved ${_formatStamp(at)} · $count '
        '${count == 1 ? 'class' : 'classes'}.';
  }

  /// `Today 14:32`, `Yesterday 14:32`, or `Mar 7, 14:32` — no intl needed.
  String _formatStamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final clock = '${two(t.hour)}:${two(t.minute)}';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return 'Today $clock';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $clock';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, $clock';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auto = AutoBackupService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.pageContentMaxWidth,
          ),
          child: ListView(
            padding: AppTheme.pagePadding,
            children: [
              Text('Protect your week', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Klasify saves a fresh backup after every change — no button '
                'to press. The copy stays on this device and rides with your '
                "phone's Google backup when device backup is on. A file "
                'export is here for moving to a new phone.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: auto,
                builder: (context, _) => _ActionPanel(
                  icon: Icons.backup_outlined,
                  title: 'Automatic backups',
                  message:
                      'A fresh backup is saved after every schedule change.',
                  child: Row(
                    children: [
                      Switch(value: auto.enabled, onChanged: _toggleAutoBackup),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Save after every change',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _autoStatusLine(auto),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                color: auto.lastError != null && auto.enabled
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.itemGap),
              _ActionPanel(
                icon: Icons.download_rounded,
                title: 'Export a backup',
                message: 'Save your classes as a backup file.',
                child: FilledButton.icon(
                  onPressed: _working ? null : _export,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export backup file'),
                ),
              ),
              const SizedBox(height: AppTheme.itemGap),
              _ActionPanel(
                icon: Icons.upload_file_outlined,
                title: 'Restore a backup',
                message: 'Choose a backup file or the automatic copy.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _working ? null : _restoreFromFile,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Restore from backup file'),
                    ),
                    ListenableBuilder(
                      listenable: auto,
                      builder: (context, _) {
                        final hasAuto = auto.enabled && auto.lastBackupAt != null;
                        if (!hasAuto) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(
                            top: AppTheme.itemGap,
                          ),
                          child: OutlinedButton.icon(
                            onPressed: _working ? null : _restoreFromAutoBackup,
                            icon: const Icon(Icons.restore),
                            label: const Text('Restore last automatic backup'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppTheme.itemGap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your current schedule is replaced only after validation and your confirmation.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_working)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled panel for one backup action. Each panel carries one primary action.
class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Option-C edge, same primitive as the class card: fill + hairline +
    // tight ambient shadow (holdouts board §1).
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardFillColorOf(scheme),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.fromBorderSide(AppTheme.cardBorderSideOf(scheme)),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary, size: 26),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
