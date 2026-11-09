import 'dart:async';

import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_banner.dart';
import '../widgets/app_state_transition.dart';
import 'profile/profile_shared.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _loading = true;
  bool _enabled = false;
  int _leadMinutes = ReminderService.defaultLeadMinutes;
  bool _eventsEnabled = true;
  bool _exactAlarmsAvailable = true;
  String? _status;
  _StatusKind _statusKind = _StatusKind.neutral;

  @override
  void initState() {
    super.initState();
    ReminderService.instance.addListener(_onReminderSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    ReminderService.instance.removeListener(_onReminderSettingsChanged);
    super.dispose();
  }

  void _onReminderSettingsChanged() {
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final enabled = await ReminderService.instance.isEnabled;
      final leadMinutes = await ReminderService.instance.leadMinutes;
      final eventsEnabled = await ReminderService.instance.eventsEnabled;
      final exactAlarmsAvailable =
          await ReminderService.instance.exactAlarmsAvailable;
      if (!mounted) return;
      if (enabled == _enabled &&
          leadMinutes == _leadMinutes &&
          eventsEnabled == _eventsEnabled &&
          exactAlarmsAvailable == _exactAlarmsAvailable &&
          !_loading) {
        return;
      }
      setState(() {
        _enabled = enabled;
        _leadMinutes = leadMinutes;
        _eventsEnabled = eventsEnabled;
        _exactAlarmsAvailable = exactAlarmsAvailable;
        _loading = false;
        if (enabled && !exactAlarmsAvailable) {
          _statusKind = _StatusKind.warning;
          _status =
              'Reminders are on, but Android may delay them. Allow “Alarms & reminders” for on-time alerts.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusKind = _StatusKind.error;
          _status = 'Could not read reminder settings.';
        });
      }
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      if (value) {
        final granted = await ReminderService.instance.enable();
        if (!granted) {
          if (mounted) {
            setState(() {
              _loading = false;
              _enabled = false;
              _statusKind = _StatusKind.error;
              _status =
                  'Notification permission was not granted. Enable notifications in Android settings and try again.';
            });
          }
          return;
        }
        if (mounted) {
          final exactAlarmsAvailable =
              await ReminderService.instance.exactAlarmsAvailable;
          final leadMinutes = await ReminderService.instance.leadMinutes;
          if (!mounted) return;
          setState(() {
            _loading = false;
            _enabled = true;
            _leadMinutes = leadMinutes;
            _exactAlarmsAvailable = exactAlarmsAvailable;
            _statusKind = exactAlarmsAvailable
                ? _StatusKind.neutral
                : _StatusKind.warning;
            _status = exactAlarmsAvailable
                ? 'System notifications are enabled for your saved classes.'
                : 'Notifications are on, but Android may delay them. Allow “Alarms & reminders” in system settings for on-time alerts.';
          });
        }
      } else {
        await ReminderService.instance.disable();
        if (mounted) {
          setState(() {
            _loading = false;
            _enabled = false;
            _statusKind = _StatusKind.neutral;
            _status = 'Class reminders are disabled.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusKind = _StatusKind.error;
          _status =
              'Could not update reminders. Check notification permission and try again.';
        });
      }
    }
  }

  Future<void> _setLeadMinutes(int minutes) async {
    setState(() => _leadMinutes = minutes);
    try {
      await ReminderService.instance.setLeadMinutes(minutes);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusKind = _StatusKind.error;
        _status = 'Could not save the reminder lead time.';
      });
      unawaited(_load());
    }
  }

  Future<void> _setEventsEnabled(bool value) async {
    // Turning events ON while class reminders are off requires the master
    // gate to be enabled first, then the events gate on top.
    if (value && !_enabled) {
      await _toggle(true);
      if (!mounted || !_enabled) return;
    }
    try {
      await ReminderService.instance.setEventsEnabled(value);
      if (!mounted) return;
      setState(() => _eventsEnabled = value);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusKind = _StatusKind.error;
        _status = 'Could not update event reminders.';
      });
      unawaited(_load());
    }
  }

  Future<void> _requestExactAlarmsAccess() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final allowed = await ReminderService.instance.requestExactAlarmsAccess();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _exactAlarmsAvailable = allowed;
        _statusKind = allowed ? _StatusKind.neutral : _StatusKind.warning;
        _status = allowed
            ? 'On-time class notifications are enabled.'
            : 'Exact alarms were not allowed. Android may delay notifications.';
      });
    } catch (error, stackTrace) {
      debugPrint('Exact alarm permission request failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusKind = _StatusKind.error;
        _status = 'Could not update the “Alarms & reminders” permission.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: const ProfileTitleBar(parent: 'Settings & privacy'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: AppTheme.pagePadding,
            children: [
              const ProfileSubhead(
                title: 'Notifications',
                tagline: 'How early you get warned before class.',
              ),
              ProfileGroup(
                label: 'CLASS REMINDERS',
                rows: [
                  ProfileRow(
                    icon: Icons.notifications_none_rounded,
                    title: 'Class reminders',
                    subtitle: switch (_enabled) {
                      true => 'Alerts before each class',
                      false => 'No alerts scheduled',
                    },
                    trailing: MiniSwitch(
                      value: _enabled,
                      semanticsLabel: 'Class reminders',
                      onChanged: _loading ? null : _toggle,
                    ),
                  ),
                  // Chips row: icon + full-width title, then chips below.
                  ProfileRow(
                    icon: Icons.schedule_rounded,
                    title: 'Remind me before class',
                    trailing: const SizedBox.shrink(),
                    footer: Padding(
                      padding: const EdgeInsets.only(left: 48, top: 8),
                      child: Opacity(
                        opacity: _enabled ? 1 : 0.45,
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final lead in const [10, 30, 60])
                              _LeadPill(
                                minutes: lead,
                                selected: _leadMinutes == lead,
                                enabled: _enabled,
                                scheme: scheme,
                                textTheme: theme.textTheme,
                                onTap: _enabled
                                    ? () => unawaited(_setLeadMinutes(lead))
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.sectionGap),
              ProfileGroup(
                label: 'EVENT REMINDERS',
                rows: [
                  ProfileRow(
                    icon: Icons.event_outlined,
                    title: 'Event reminders',
                    subtitle: 'Alerts before your added events',
                    trailing: MiniSwitch(
                      value: _eventsEnabled,
                      semanticsLabel: 'Event reminders',
                      onChanged: _loading
                          ? null
                          : (v) => unawaited(_setEventsEnabled(v)),
                    ),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              AppStateTransition(
                stateKey: ValueKey(_status ?? 'no-reminder-status'),
                child: _status == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: StatusBanner(
                          message: _status!,
                          kind: switch (_statusKind) {
                            _StatusKind.error => StatusKind.error,
                            _StatusKind.warning => StatusKind.warning,
                            _StatusKind.neutral => StatusKind.neutral,
                          },
                          onDismiss: () => setState(() => _status = null),
                        ),
                      ),
              ),
              if (_enabled && !_exactAlarmsAvailable) ...[
                const SizedBox(height: AppTheme.itemGap),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _requestExactAlarmsAccess,
                  icon: const Icon(Icons.alarm),
                  label: const Text('Allow Alarms & reminders'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _StatusKind { neutral, warning, error }

class _LeadPill extends StatelessWidget {
  const _LeadPill({
    required this.minutes,
    required this.selected,
    required this.enabled,
    required this.scheme,
    required this.textTheme,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final bool enabled;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final VoidCallback? onTap;

  String get _label {
    if (minutes == 60) return '1 hour';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$minutes minutes before class',
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              _label,
              style: textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
