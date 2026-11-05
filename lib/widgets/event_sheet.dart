import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/class_item.dart' show formatMinutes;
import '../models/class_status.dart' show dateKey, shortDateLabel;
import '../models/event_item.dart'
    show EventItem, eventDefaultLeadMinutes, eventLeadChoices, eventKickLabel;
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import 'app_notification.dart';

/// Deletes one event immediately and offers a five-second undo action, the
/// same arrangement as deleteClassWithUndo. Events have no dependent rows,
/// so undo restores the row and the reminders resync around it.
Future<bool> deleteEventWithUndo(BuildContext context, EventItem event) async {
  final id = event.id;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (id == null || messenger == null) return false;
  final scheme = Theme.of(context).colorScheme;

  final deleted = await DatabaseHelper.instance.deleteEvent(id);
  if (deleted == 0) {
    debugPrint('Event delete failed: row ${event.id} was not found.');
    showAppNotificationOnMessenger(
      messenger,
      scheme,
      'Could not delete the event. Please try again.',
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
    debugPrint('Reminder sync after event delete failed: $error\n$stackTrace');
  }

  showAppNotificationOnMessenger(
    messenger,
    scheme,
    remindersOk
        ? 'Event deleted'
        : 'Event deleted, but reminders could not be updated.',
    kind: remindersOk ? AppNotificationKind.info : AppNotificationKind.warning,
    duration: const Duration(seconds: 5),
    actionLabel: 'Undo',
    onAction: () async {
      try {
        await DatabaseHelper.instance.restoreDeletedEvent(event);
        var restoredRemindersOk = true;
        try {
          await ReminderService.instance.sync();
        } catch (error) {
          restoredRemindersOk = false;
          debugPrint('Reminder sync after event restore failed: $error');
        }
        showAppNotificationOnMessenger(
          messenger,
          scheme,
          restoredRemindersOk
              ? 'Event restored'
              : 'Event restored, but reminders could not be updated.',
          kind: restoredRemindersOk
              ? AppNotificationKind.success
              : AppNotificationKind.warning,
          replaceCurrent: true,
        );
      } catch (error, stackTrace) {
        debugPrint('Event restore failed: $error\n$stackTrace');
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

/// Opens the add/edit event sheet. [initial] null = new event. Saving
/// happens inside the sheet; Today's list refreshes through the database
/// listener once the row lands.
Future<void> showEventSheet(
  BuildContext context, {
  EventItem? initial,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EventSheet(initial: initial),
    );

/// The one event form the mockups specify: name, when & where, and the
/// reminder ("Remind me" switch plus "Alert" picker). Everything saves to
/// the phone's local database — the footnote says exactly that, because the
/// account sync that will carry events to other devices does not exist yet.
class EventSheet extends StatefulWidget {
  const EventSheet({super.key, this.initial});

  /// The event being edited; null creates a new one.
  final EventItem? initial;

  @override
  State<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<EventSheet> {
  late final TextEditingController _title;
  late final TextEditingController _venue;
  late DateTime _date;
  late int _startMinutes;
  late bool _remindMe;
  late int _lead;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title);
    _venue = TextEditingController(text: initial?.venue);
    if (initial != null) {
      _date = initial.day;
      _startMinutes = initial.startMinutes;
      _remindMe = initial.remindMe;
      _lead = initial.leadMinutes;
    } else {
      // A fresh form never opens with a default already in the past:
      // today at 9:00 while morning, else the next half-hour, else
      // tomorrow at 9:00.
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      if (nowMinutes < 9 * 60) {
        _date = DateTime(now.year, now.month, now.day);
        _startMinutes = 9 * 60;
      } else if (nowMinutes < 22 * 60 + 30) {
        _date = DateTime(now.year, now.month, now.day);
        _startMinutes = (nowMinutes ~/ 30 + 1) * 30;
      } else {
        _date = DateTime(now.year, now.month, now.day + 1);
        _startMinutes = 9 * 60;
      }
      _remindMe = true;
      _lead = eventDefaultLeadMinutes;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _venue.dispose();
    super.dispose();
  }

  bool get _nameValid => _title.text.trim().length >= 2;

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    FocusScope.of(context).unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _startMinutes ~/ 60,
        minute: _startMinutes % 60,
      ),
    );
    if (picked != null) {
      setState(() => _startMinutes = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _pickLead() async {
    FocusScope.of(context).unfocus();
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final choice in eventLeadChoices)
              ListTile(
                title: Text('$choice minutes before'),
                trailing:
                    choice == _lead ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(sheetContext, choice),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _lead = picked);
  }

  /// Validates, writes, and resyncs reminders. Stays open on failure so
  /// nothing typed is lost.
  Future<void> _save() async {
    if (!_nameValid) {
      setState(() {});
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    final event = EventItem(
      id: widget.initial?.id,
      title: _title.text.trim(),
      venue: _venue.text.trim(),
      date: dateKey(_date),
      startMinutes: _startMinutes,
      remindMe: _remindMe,
      leadMinutes: _lead,
    );
    try {
      if (widget.initial == null) {
        await DatabaseHelper.instance.insertEvent(event);
      } else {
        await DatabaseHelper.instance.updateEvent(event);
      }
    } catch (error, stackTrace) {
      debugPrint('Event save failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showAppNotification(
        context,
        'Could not save the event. Please try again.',
        kind: AppNotificationKind.error,
      );
      return;
    }

    var remindersOk = true;
    try {
      await ReminderService.instance.sync();
    } catch (error, stackTrace) {
      remindersOk = false;
      debugPrint('Reminder sync after event save failed: $error\n$stackTrace');
    }
    if (!mounted) return;
    if (!remindersOk) {
      showAppNotification(
        context,
        'Saved, but reminders could not be updated.',
        kind: AppNotificationKind.warning,
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final ok = await deleteEventWithUndo(context, initial);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final editing = widget.initial != null;

    return Padding(
      // Keyboard clearance: the sheet scrolls above it instead of clipping.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        children: [
          Text(
            (editing
                    ? 'Event · ${eventKickLabel(widget.initial!.day)}'
                    : 'New event')
                .toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: AppTheme.groupLabelColorOf(scheme),
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          // The name is the sheet's headline: big, borderless, no counting
          // UI beyond the two-character floor.
          TextField(
            controller: _title,
            autofocus: !editing,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [
              // Newlines would break the title into two lines on tiles.
              FilteringTextInputFormatter.singleLineFormatter,
            ],
            style: textTheme.titleLarge?.copyWith(
              fontSize: 18,
              height: 1.25,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Event name',
              errorText: _nameValid ? null : '',
              errorStyle: const TextStyle(height: 0.05),
              border: InputBorder.none,
              filled: false,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (!_nameValid)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'At least 2 characters.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          const Divider(height: 20),
          _SheetRow(
            label: 'Date',
            value: shortDateLabel(_date),
            onTap: _pickDate,
          ),
          _SheetRow(
            label: 'Time',
            value: formatMinutes(_startMinutes),
            onTap: _pickTime,
          ),
          // A plain row: ListTile's trailing slot cannot host a full-width
          // editable field (Expanded is Flex-only), so the venue field lives
          // beside the label instead of inside a tile's trailing side.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(
                  'Where',
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface,
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _venue,
                    maxLength: 60,
                    textAlign: TextAlign.end,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.singleLineFormatter,
                    ],
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(color: scheme.outline),
                      errorStyle: const TextStyle(height: 0.05),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SheetRow(
            label: 'Remind me',
            child: Switch(
              value: _remindMe,
              onChanged: (value) => setState(() => _remindMe = value),
            ),
          ),
          _SheetRow(
            label: 'Alert',
            value: '$_lead minutes before',
            onTap: _remindMe ? _pickLead : null,
            disabled: !_remindMe,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save reminder'),
          ),
          if (editing) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: _delete,
              child: const Text('Delete event'),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Saved on this phone · syncs when account sync turns on',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// One settings-style segment row inside the sheet: label left, trailing
/// value text or widget right, a chevron when the row opens something.
class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, this.value, this.child, this.onTap, this.disabled = false});

  final String label;

  /// Trailing text; when null, [child] owns the trailing side.
  final String? value;
  final Widget? child;
  final VoidCallback? onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tappable = onTap != null && !disabled;
    final valueColor = disabled ? scheme.outline : scheme.onSurfaceVariant;

    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: ListTile(
        onTap: tappable ? onTap : null,
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 10,
        title: Text(
          label,
          style: textTheme.bodyLarge?.copyWith(
            color: scheme.onSurface,
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              )
            else if (child != null)
              child!,
            if (tappable)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: valueColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
