import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../utils/schedule_backup_codec.dart';
import '../widgets/app_notification.dart';

/// Offline JSON backup/restore. Restore validates the entire file and replaces
/// the schedule atomically only after the user confirms the destructive action.
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
      final payload = <String, Object?>{
        'format': ScheduleBackupCodec.klasifyBackupFormat,
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'classes': classes
            .map(
              (c) => {
                'subject': c.subject,
                'room': c.room,
                'professor': c.professor,
                'day': c.day,
                'start_minutes': c.startMinutes,
                'end_minutes': c.endMinutes,
              },
            )
            .toList(),
      };
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save class schedule backup',
        fileName: 'klasify_backup.json',
        mimeType: 'application/json',
        bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
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
            'Backup exported (${classes.length} ${classes.length == 1 ? 'class' : 'classes'}).',
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

  Future<void> _restore() async {
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
      final classes = ScheduleBackupCodec.decode(data);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace current schedule?'),
          content: Text(
            'This backup contains ${classes.length} ${classes.length == 1 ? 'class' : 'classes'}. Restoring it replaces all currently saved classes. Export a backup first if you want to keep them.',
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
      if (confirmed != true) {
        if (mounted) {
          showAppNotification(
            context,
            'Restore cancelled. Your schedule was not changed.',
            kind: AppNotificationKind.info,
          );
        }
        return;
      }
      if (!mounted) return;
      final count = await DatabaseHelper.instance.replaceAll(classes);
      var status = 'Restored $count ${count == 1 ? 'class' : 'classes'}.';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                'Keep a copy before changing phones or reinstalling. Everything stays on this device until you choose a backup file.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
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
                message: 'Choose a backup file to replace the saved schedule.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _working ? null : _restore,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Restore from backup file'),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
