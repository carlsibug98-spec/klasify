import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_notification.dart';

/// Shared add/rename office name sheet (super-admin office management).
/// Both the "Add office" row on Settings → Admin and the "Rename office" row
/// in the availability editor open this same sheet, so validation and the
/// save/failure contract can never drift.
///
/// The sheet owns the save interaction: the CTA spins and reads "Saving…"
/// while [onSave] runs, the sheet is not dismissible mid-save, a failure
/// keeps the sheet open with an error toast for an immediate retry, and a
/// success pops with `true`. `false` means the admin backed out.
Future<bool> showOfficeNameSheet(
  BuildContext context, {
  required String title,
  required String ctaLabel,
  String initialName = '',
  List<String> takenNames = const [],
  required Future<void> Function(String name) onSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _OfficeNameSheet(
      title: title,
      ctaLabel: ctaLabel,
      initialName: initialName,
      takenNames: takenNames,
      onSave: onSave,
    ),
  );
  return saved ?? false;
}

class _OfficeNameSheet extends StatefulWidget {
  const _OfficeNameSheet({
    required this.title,
    required this.ctaLabel,
    required this.initialName,
    required this.takenNames,
    required this.onSave,
  });

  final String title;
  final String ctaLabel;
  final String initialName;
  final List<String> takenNames;
  final Future<void> Function(String name) onSave;

  @override
  State<_OfficeNameSheet> createState() => _OfficeNameSheetState();
}

class _OfficeNameSheetState extends State<_OfficeNameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();

  bool get _isDuplicate {
    final value = _trimmed.toLowerCase();
    return widget.takenNames.any((n) => n.trim().toLowerCase() == value);
  }

  bool get _canSave => _trimmed.isNotEmpty && !_isDuplicate;

  Future<void> _save() async {
    if (_busy || !_canSave) return;
    setState(() => _busy = true);
    try {
      await widget.onSave(_trimmed);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotification(
        context,
        "Couldn't save the office. Nothing changed. Try again.",
        kind: AppNotificationKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duplicate = _trimmed.isNotEmpty && _isDuplicate;

    return PopScope(
      // A save is in flight: closing now would lose track of it (the admin
      // could tap away and never learn whether the change landed).
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(widget.title, style: theme.textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
                child: Text(
                  'Students see it on Today after the next sync.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Text(
                  'OFFICE NAME',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppTheme.groupLabelColorOf(scheme),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      TextField(
                        controller: _name,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.words,
                        enabled: !_busy,
                        autofocus: true,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                        decoration: const InputDecoration.collapsed(
                          hintText: 'e.g. Library',
                        ).copyWith(isCollapsed: true),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 15,
                          height: 1.3,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (duplicate)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'An office with this name already exists.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              height: 1.2,
                              color: scheme.error,
                            ),
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
                    onPressed: (_busy || !_canSave) ? null : _save,
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
                        : Text(widget.ctaLabel),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  height: 40,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
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
