import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_notification.dart';

/// Availability choices, in sheet order. Keys match the server's
/// office_statuses.status values.
const _availabilityOptions = [
  ('open', 'Open'),
  ('break', 'On break'),
  ('closed', 'Closed'),
];

/// The shared office-availability editor (design C bottom sheet). Both
/// entry points — the ✎ chip on Today's office strip and Settings → Admin →
/// Office availability — open this same sheet, so they can never drift.
///
/// The sheet owns the save interaction: the CTA spins and reads "Saving…"
/// while [onSave] runs, the sheet is not dismissible mid-save, a failure
/// keeps the sheet open with an error toast for an immediate retry, and a
/// success pops with `true`. `false` means the admin backed out.
Future<bool> showOfficeStatusEditorSheet(
  BuildContext context, {
  required String displayName,
  required String initialStatus,
  String? initialNote,
  required Future<void> Function(String status, String? note) onSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OfficeStatusEditorSheet(
      displayName: displayName,
      initialStatus: initialStatus,
      initialNote: initialNote,
      onSave: onSave,
    ),
  );
  return saved ?? false;
}

class _OfficeStatusEditorSheet extends StatefulWidget {
  const _OfficeStatusEditorSheet({
    required this.displayName,
    required this.initialStatus,
    required this.initialNote,
    required this.onSave,
  });

  final String displayName;
  final String initialStatus;
  final String? initialNote;
  final Future<void> Function(String status, String? note) onSave;

  @override
  State<_OfficeStatusEditorSheet> createState() =>
      _OfficeStatusEditorSheetState();
}

class _OfficeStatusEditorSheetState extends State<_OfficeStatusEditorSheet> {
  late String _status = widget.initialStatus;
  late final TextEditingController _note = TextEditingController(
    text: widget.initialNote ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSave(_status, _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotification(
        context,
        "Couldn't update ${widget.displayName}. Nothing changed. Try again.",
        kind: AppNotificationKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      // A save is in flight: closing now would lose track of it (the admin
      // could tap away and never learn whether the change landed).
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(widget.displayName, style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
                child: Text(
                  'Students see this on Today, updated at the next sync.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  'AVAILABILITY',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppTheme.groupLabelColorOf(scheme),
                  ),
                ),
              ),
              // Stacked segmented group: one surface, 1px seams, rounded
              // outer corners; the selected row lifts to the high fill.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.fromBorderSide(
                      AppTheme.cardBorderSideOf(scheme),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (index, option) in _availabilityOptions.indexed) ...[
                        if (index > 0)
                          Container(
                            height: 1,
                            color: AppTheme.cardBorderSideOf(scheme).color,
                          ),
                        _AvailabilityOption(
                          label: option.$2,
                          selected: _status == option.$1,
                          onTap: _busy ? null : () => setState(() => _status = option.$1),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
                  decoration: BoxDecoration(
                    color: AppTheme.cardFillColorOf(scheme),
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    border: Border.fromBorderSide(
                      AppTheme.cardBorderSideOf(scheme),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Note (optional)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.placeholderFor(scheme),
                        ),
                      ),
                      TextField(
                        controller: _note,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.sentences,
                        enabled: !_busy,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                        decoration: const InputDecoration.collapsed(
                          hintText: 'Back at 2pm',
                        ).copyWith(isCollapsed: true),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.controlRadius,
                        ),
                      ),
                    ),
                    child: _busy
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: scheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Saving…'),
                            ],
                          )
                        : const Text('Update availability'),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      textStyle: theme.textTheme.labelLarge?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvailabilityOption extends StatelessWidget {
  const _AvailabilityOption({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        color: selected ? scheme.surfaceContainerHigh : AppTheme.cardFillColorOf(scheme),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            // Radio check: filled primary disc with a check when selected,
            // a thin outline ring when not — mirrors the mockup's radio.
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? scheme.primary : Colors.transparent,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outline,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
