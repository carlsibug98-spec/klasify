import 'dart:async';

import 'package:flutter/material.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_banner.dart';
import '../widgets/app_state_transition.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

enum _StatusKind { neutral, warning, error }

class _RemindersScreenState extends State<RemindersScreen> {
  bool _loading = true;
  bool _enabled = false;
  int _leadMinutes = ReminderService.defaultLeadMinutes;
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

  /// The service notifies when reminders are enabled, disabled, or their
  /// lead time changes; reload everything from the source of truth.
  void _onReminderSettingsChanged() {
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final enabled = await ReminderService.instance.isEnabled;
      final leadMinutes = await ReminderService.instance.leadMinutes;
      final exactAlarmsAvailable =
          await ReminderService.instance.exactAlarmsAvailable;
      if (!mounted) return;
      if (enabled == _enabled &&
          leadMinutes == _leadMinutes &&
          exactAlarmsAvailable == _exactAlarmsAvailable &&
          !_loading) {
        return;
      }
      setState(() {
        _enabled = enabled;
        _leadMinutes = leadMinutes;
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
      appBar: AppBar(title: const Text('Class reminders')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.pageContentMaxWidth,
          ),
          child: ListView(
            padding: AppTheme.pagePadding,
            children: [
              Text('Leave on time', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Get a reminder $_leadMinutes minutes before each class, every week, even when the app is closed.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.itemGap),
              Text(
                'Allow notifications and “Alarms & reminders” on your phone. Do Not Disturb still applies.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _ReminderSettings(
                scheme: scheme,
                textTheme: theme.textTheme,
                enabled: _enabled,
                leadMinutes: _leadMinutes,
                loading: _loading,
                onToggle: _toggle,
                onLeadSelected: _setLeadMinutes,
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

/// The live reminder settings: the toggle row and the 5/10/15/30-minute
/// chips, rendered directly on the page with no card or tray behind them.
class _ReminderSettings extends StatelessWidget {
  const _ReminderSettings({
    required this.scheme,
    required this.textTheme,
    required this.enabled,
    required this.leadMinutes,
    required this.loading,
    required this.onToggle,
    required this.onLeadSelected,
  });

  final ColorScheme scheme;
  final TextTheme textTheme;
  final bool enabled;
  final int leadMinutes;
  final bool loading;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onLeadSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 24,
              color: scheme.onSurface,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remind me before class',
                    style: textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Weekly, on your class days',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.38,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            _ReminderToggle(
              value: enabled,
              onChanged: loading ? null : onToggle,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final (i, lead) in const [5, 10, 15, 30].indexed)
              _LeadChip(
                minutes: lead,
                isLast: i == 3,
                selected: leadMinutes == lead,
                scheme: scheme,
                textTheme: textTheme,
                onTap: () => onLeadSelected(lead),
              ),
          ],
        ),
      ],
    );
  }
}

/// The 48×28 switch from the design. Material's Switch is 52×32 with a
/// 60×48 tap target, which pushes the card's first row taller than the mock;
/// this keeps the exact visual size while the InkWell box carries the full
/// 48×48 Material minimum target (the visual rides centered inside it) and
/// supplies focus and keyboard activation.
class _ReminderToggle extends StatelessWidget {
  const _ReminderToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final duration = AppTheme.motionDuration(
      context,
      AppTheme.motionToggle,
    );
    final trackColor = value ? scheme.primary : scheme.surfaceContainerHighest;
    final knobColor = value ? scheme.onPrimary : scheme.surface;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: 'Remind me before class',
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          excludeFromSemantics: true,
          customBorder: const StadiumBorder(),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          focusColor: scheme.primary.withValues(alpha: 0.12),
          hoverColor: scheme.primary.withValues(alpha: 0.08),
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            // 48×48 hit area (Material minimum); the 48×28 visual is
            // centered so the mock's row silhouette is preserved.
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 48,
                  height: 28,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: AppTheme.motionEaseOut,
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: AnimatedAlign(
                      duration: duration,
                      curve: AppTheme.motionEaseOut,
                      alignment: value
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: knobColor,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 22),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One lead-time chip: 36px tall, equal width, black when selected.
class _LeadChip extends StatelessWidget {
  const _LeadChip({
    required this.minutes,
    required this.isLast,
    required this.selected,
    required this.scheme,
    required this.textTheme,
    required this.onTap,
  });

  final int minutes;
  final bool isLast;
  final bool selected;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(right: isLast ? 0 : 8),
        child: Semantics(
          button: true,
          selected: selected,
          label: '$minutes minutes before class',
          child: Material(
            color: selected ? scheme.primary : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 36,
                child: Center(
                  child: Text(
                    '$minutes min',
                    style: textTheme.bodySmall?.copyWith(
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
