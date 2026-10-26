import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../services/reminder_service.dart';
import '../utils/schedule_rules.dart';
import '../widgets/app_notification.dart';
import '../widgets/edit_class_time_picker_sheet.dart';

/// Screen matching edit-class-v2.html for adding or editing a class.
class EditClassScreen extends StatefulWidget {
  final ClassItem? classItem;
  final int? initialDay;
  final bool returnDraft;
  final Future<bool> Function(ClassItem item)? onSave;
  final Future<bool> Function(ClassItem item)? onDelete;

  const EditClassScreen({
    super.key,
    this.classItem,
    this.initialDay,
    this.returnDraft = false,
    this.onSave,
    this.onDelete,
  });

  @override
  State<EditClassScreen> createState() => _EditClassScreenState();
}

class _EditClassScreenState extends State<EditClassScreen> {
  late final TextEditingController _subjectController;
  late final TextEditingController _roomController;
  late final TextEditingController _professorController;

  late final FocusNode _subjectFocusNode;
  late final FocusNode _roomFocusNode;
  late final FocusNode _professorFocusNode;

  int? _selectedDay; // 1 = Monday ... 7 = Sunday
  late int _startMinutes;
  late int _endMinutes;

  String? _subjectError;
  String? _roomError;
  String? _professorError;
  String? _dayError;
  String? _timeError;

  bool _deleteArmed = false;
  Timer? _deleteTimer;
  bool _isSaving = false;
  bool _isDeleting = false;

  ClassItem? _baselineClass;

  bool get _isEditing => widget.classItem != null;

  static const List<String> _dayShortNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.classItem;
    _baselineClass = item;

    _subjectController = TextEditingController(text: item?.subject ?? '');
    _roomController = TextEditingController(text: item?.room ?? '');
    _professorController = TextEditingController(
      text: item == null || item.professor == unspecifiedProfessor
          ? ''
          : item.professor,
    );

    _subjectFocusNode = FocusNode()..addListener(() => setState(() {}));
    _roomFocusNode = FocusNode()..addListener(() => setState(() {}));
    _professorFocusNode = FocusNode()..addListener(() => setState(() {}));

    _selectedDay =
        item?.day ??
        (widget.initialDay ?? DateTime.now().weekday).clamp(1, 7).toInt();
    _startMinutes = item?.startMinutes ?? (8 * 60); // 8:00 AM
    _endMinutes = item?.endMinutes ?? (9 * 60 + 30); // 9:30 AM
  }

  @override
  void dispose() {
    _deleteTimer?.cancel();
    _subjectController.dispose();
    _roomController.dispose();
    _professorController.dispose();
    _subjectFocusNode.dispose();
    _roomFocusNode.dispose();
    _professorFocusNode.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges {
    if (_isEditing) {
      final base = _baselineClass!;
      final prof = base.professor == unspecifiedProfessor ? '' : base.professor;
      return _subjectController.text != base.subject ||
          _roomController.text != base.room ||
          _professorController.text != prof ||
          _selectedDay != base.day ||
          _startMinutes != base.startMinutes ||
          _endMinutes != base.endMinutes;
    } else {
      final defaultDay = (widget.initialDay ?? DateTime.now().weekday)
          .clamp(1, 7)
          .toInt();
      return _subjectController.text.trim().isNotEmpty ||
          _roomController.text.trim().isNotEmpty ||
          _professorController.text.trim().isNotEmpty ||
          _selectedDay != defaultDay ||
          _startMinutes != (8 * 60) ||
          _endMinutes != (9 * 60 + 30);
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _EditorColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Discard changes?',
          key: Key('discard_dialog_title'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'You have unsaved changes. Are you sure you want to discard them?',
          style: TextStyle(color: _EditorColors.muted),
        ),
        actions: [
          TextButton(
            key: const Key('discard_dialog_cancel_button'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Keep editing',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            key: const Key('discard_dialog_confirm_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Discard',
              style: TextStyle(color: _EditorColors.error),
            ),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _handleBack() async {
    if (_hasUnsavedChanges) {
      final discard = await _confirmDiscardChanges();
      if (!mounted) return;
      if (discard) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onDeleteTap() {
    if (_isDeleting || _isSaving || widget.classItem == null) return;

    if (!_deleteArmed) {
      // Arming a destructive action gets a warning-level tick.
      HapticFeedback.mediumImpact();
      setState(() => _deleteArmed = true);
      _deleteTimer?.cancel();
      _deleteTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _deleteArmed = false);
        }
      });
    } else {
      _deleteTimer?.cancel();
      setState(() => _deleteArmed = false);
      HapticFeedback.heavyImpact();
      _executeDelete();
    }
  }

  Future<void> _executeDelete() async {
    final item = widget.classItem;
    if (item == null) return;

    setState(() => _isDeleting = true);
    try {
      final success = widget.onDelete != null
          ? await widget.onDelete!(item)
          : await _defaultDelete(item);
      if (!mounted) return;
      if (success) {
        showAppNotification(
          context,
          'Class deleted',
          kind: AppNotificationKind.info,
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() => _isDeleting = false);
        showAppNotification(
          context,
          'Could not delete class. Please try again.',
          kind: AppNotificationKind.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Delete class failed: $e');
      setState(() => _isDeleting = false);
      showAppNotification(
        context,
        "Couldn't delete the class. Please try again.",
        kind: AppNotificationKind.error,
      );
    }
  }

  Future<bool> _defaultDelete(ClassItem item) async {
    final id = item.id;
    if (id == null) return false;
    final deleted = await DatabaseHelper.instance.delete(id);
    if (deleted > 0) {
      try {
        await ReminderService.instance.sync();
      } catch (_) {}
      return true;
    }
    return false;
  }

  Future<void> _onSave() async {
    if (_isSaving || _isDeleting) return;

    bool valid = true;
    FocusNode? firstInvalid;

    final subjectTrimmed = _subjectController.text.trim();
    if (subjectTrimmed.length < 2) {
      valid = false;
      _subjectError = subjectTrimmed.isEmpty
          ? 'Enter a subject.'
          : 'Subject must be at least 2 characters.';
      firstInvalid ??= _subjectFocusNode;
    } else {
      _subjectError = null;
    }

    final roomTrimmed = _roomController.text.trim();
    if (roomTrimmed.isEmpty) {
      valid = false;
      _roomError = 'Enter a room.';
      firstInvalid ??= _roomFocusNode;
    } else {
      _roomError = null;
    }

    // Matches the database rule: a professor entry shorter than two
    // characters cannot be saved, so catch it here instead of letting the
    // insert throw a raw error later.
    final profTrimmed = _professorController.text.trim();
    if (profTrimmed.length == 1) {
      valid = false;
      _professorError = 'Enter at least 2 characters, or leave it empty.';
    } else {
      _professorError = null;
    }

    if (_selectedDay == null) {
      valid = false;
      _dayError = 'Choose at least one day.';
    } else {
      _dayError = null;
    }

    if (_endMinutes <= _startMinutes) {
      valid = false;
      _timeError = 'End time must be after the start time.';
    } else {
      _timeError = null;
    }

    setState(() {});

    if (!valid) {
      firstInvalid?.requestFocus();
      return;
    }

    final itemToSave = ClassItem(
      id: widget.classItem?.id,
      subject: subjectTrimmed,
      room: roomTrimmed,
      professor: profTrimmed.isEmpty ? unspecifiedProfessor : profTrimmed,
      day: _selectedDay!,
      startMinutes: _startMinutes,
      endMinutes: _endMinutes,
    );

    if (widget.returnDraft) {
      Navigator.pop(context, itemToSave);
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (widget.onSave != null) {
        final success = await widget.onSave!(itemToSave);
        if (!mounted) return;
        setState(() => _isSaving = false);
        if (success) {
          _baselineClass = itemToSave;
          HapticFeedback.lightImpact();
          showAppNotification(
            context,
            _isEditing ? 'Class updated.' : 'Class added.',
            kind: AppNotificationKind.success,
          );
          Navigator.of(context).pop(true);
        }
        return;
      }

      // Check for overlap on the same day
      final sameDay = await DatabaseHelper.instance.getByDay(_selectedDay!);
      final overlap = findOverlappingClass(
        sameDay,
        day: _selectedDay!,
        startMinutes: _startMinutes,
        endMinutes: _endMinutes,
        excludeId: widget.classItem?.id,
      );
      if (overlap != null) {
        if (!mounted) return;
        setState(() {
          _timeError =
              'Overlaps with ${overlap.subject} (${overlap.timeRange})';
          _isSaving = false;
        });
        return;
      }

      if (_isEditing) {
        final changed = await DatabaseHelper.instance.update(itemToSave);
        if (!mounted) return;
        setState(() => _isSaving = false);
        if (changed > 0) {
          try {
            await ReminderService.instance.sync();
          } catch (_) {}
          if (!mounted) return;
          _baselineClass = itemToSave;
          showAppNotification(
            context,
            'Class updated.',
            kind: AppNotificationKind.success,
          );
          Navigator.of(context).pop(true);
        }
      } else {
        await DatabaseHelper.instance.insert(itemToSave);
        try {
          await ReminderService.instance.sync();
        } catch (_) {}
        if (!mounted) return;
        setState(() => _isSaving = false);
        HapticFeedback.lightImpact();
        showAppNotification(
          context,
          'Class added.',
          kind: AppNotificationKind.success,
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Save class failed: $e');
      setState(() => _isSaving = false);
      showAppNotification(
        context,
        "Couldn't save the class. Check the details and try again.",
        kind: AppNotificationKind.error,
      );
    }
  }

  Future<void> _openTimePicker({required bool isStart}) async {
    final title = isStart ? 'Start time' : 'End time';
    final initialMinutes = isStart ? _startMinutes : _endMinutes;

    final result = await showEditClassTimePickerSheet(
      context: context,
      title: title,
      initialMinutes: initialMinutes,
      isStart: isStart,
      currentStartMinutes: isStart ? null : _startMinutes,
      currentEndMinutes: isStart ? _endMinutes : null,
      previousDuration: _endMinutes - _startMinutes,
    );

    if (result != null && mounted) {
      setState(() {
        if (isStart) {
          _startMinutes = result.minutes;
          if (result.adjustedEndMinutes != null) {
            _endMinutes = result.adjustedEndMinutes!;
          }
        } else {
          _endMinutes = result.minutes;
        }
        if (_endMinutes > _startMinutes) {
          _timeError = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _confirmDiscardChanges();
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // The editor is always a dark surface, so the system status bar
        // must always use light (white) icons — a theme-colored dark bar
        // over the black scaffold becomes invisible (black on black).
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _EditorColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Cancel and go back',
                        excludeSemantics: true,
                        child: InkWell(
                          key: const Key('edit_class_back_button'),
                          borderRadius: BorderRadius.circular(24),
                          onTap: _handleBack,
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Icon(
                                Icons.arrow_back,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isEditing ? 'Edit class' : 'Add class',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Hint text
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 16),
                          child: Text(
                            'Fields marked * are required.',
                            style: TextStyle(
                              fontSize: 14,
                              color: _EditorColors.muted,
                            ),
                          ),
                        ),

                        // Section "Class"
                        _buildClassSection(),

                        const SizedBox(height: 16),

                        // Section "Weekly meeting time"
                        _buildScheduleSection(),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // Actions row pinned at the bottom: Delete on left, Save class on right
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: _buildActionsRow(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassSection() {
    return Container(
      decoration: BoxDecoration(
        color: _EditorColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Class',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _EditorColors.muted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 16),

          // Subject field
          _buildFieldLabel(label: 'Subject', isRequired: true),
          const SizedBox(height: 8),
          Semantics(
            label: 'Subject, required',
            child: TextField(
              key: const Key('edit_class_subject_field'),
              controller: _subjectController,
              focusNode: _subjectFocusNode,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 16, color: Colors.white),
              decoration: _inputDecoration(
                isFocused: _subjectFocusNode.hasFocus,
                hasError: _subjectError != null,
              ),
              onChanged: (_) {
                if (_subjectError != null) {
                  setState(() => _subjectError = null);
                }
              },
            ),
          ),
          if (_subjectError != null) ...[
            const SizedBox(height: 4),
            Text(
              _subjectError!,
              key: const Key('edit_class_subject_error'),
              style: const TextStyle(color: _EditorColors.error, fontSize: 13),
            ),
          ],

          const SizedBox(height: 16),

          // Two column row: Room and Professor
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Room (required)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel(label: 'Room', isRequired: true),
                    const SizedBox(height: 8),
                    Semantics(
                      label: 'Room, required',
                      child: TextField(
                        key: const Key('edit_class_room_field'),
                        controller: _roomController,
                        focusNode: _roomFocusNode,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        decoration: _inputDecoration(
                          isFocused: _roomFocusNode.hasFocus,
                          hasError: _roomError != null,
                        ),
                        onChanged: (_) {
                          if (_roomError != null) {
                            setState(() => _roomError = null);
                          }
                        },
                      ),
                    ),
                    if (_roomError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _roomError!,
                        key: const Key('edit_class_room_error'),
                        style: const TextStyle(
                          color: _EditorColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Professor (optional)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel(label: 'Professor', isRequired: false),
                    const SizedBox(height: 8),
                    Semantics(
                      label: 'Professor, optional',
                      child: TextField(
                        key: const Key('edit_class_professor_field'),
                        controller: _professorController,
                        focusNode: _professorFocusNode,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        decoration: _inputDecoration(
                          isFocused: _professorFocusNode.hasFocus,
                          hasError: _professorError != null,
                          hintText: 'Optional',
                        ),
                        onChanged: (_) {
                          if (_professorError != null) {
                            setState(() => _professorError = null);
                          }
                        },
                      ),
                    ),
                    if (_professorError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _professorError!,
                        key: const Key('edit_class_professor_error'),
                        style: const TextStyle(
                          color: _EditorColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    return Container(
      decoration: BoxDecoration(
        color: _EditorColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly meeting time',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _EditorColors.muted,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 16),

          // Day chips: 7 days in one row, equal width
          Row(
            children: List.generate(7, (index) {
              final dayIndex = index + 1;
              final isSelected = _selectedDay == dayIndex;
              final shortName = _dayShortNames[index];
              final fullName = dayNames[index];

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 3,
                    right: index == 6 ? 0 : 3,
                  ),
                  child: Semantics(
                    button: true,
                    selected: isSelected,
                    label: fullName,
                    excludeSemantics: true,
                    child: InkWell(
                      key: Key('edit_class_day_chip_$shortName'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() {
                          _selectedDay = dayIndex;
                          _dayError = null;
                        });
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : _EditorColors.field,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          shortName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? _EditorColors.background
                                : _EditorColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),

          if (_dayError != null) ...[
            const SizedBox(height: 8),
            Text(
              _dayError!,
              key: const Key('edit_class_day_error'),
              style: const TextStyle(color: _EditorColors.error, fontSize: 13),
            ),
          ],

          const SizedBox(height: 16),

          // Two time tiles: Starts and Ends
          Row(
            children: [
              Expanded(
                child: _buildTimeTile(
                  key: const Key('edit_class_start_tile'),
                  label: 'Starts',
                  minutes: _startMinutes,
                  isStart: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimeTile(
                  key: const Key('edit_class_end_tile'),
                  label: 'Ends',
                  minutes: _endMinutes,
                  isStart: false,
                ),
              ),
            ],
          ),

          if (_timeError != null) ...[
            const SizedBox(height: 8),
            Text(
              _timeError!,
              key: const Key('edit_class_time_error'),
              style: const TextStyle(color: _EditorColors.error, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeTile({
    required Key key,
    required String label,
    required int minutes,
    required bool isStart,
  }) {
    final timeStr = formatMinutes(minutes);

    return Semantics(
      button: true,
      label: '$label at $timeStr. Tap to edit $label time.',
      excludeSemantics: true,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTimePicker(isStart: isStart),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _EditorColors.field,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _EditorColors.muted,
                    ),
                  ),
                  const Icon(
                    Icons.access_time_rounded,
                    size: 16,
                    color: _EditorColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsRow() {
    final saveLabel = widget.returnDraft
        ? (_isEditing ? 'Save changes' : 'Add to review list')
        : 'Save class';

    if (!_isEditing || widget.returnDraft) {
      // Add mode, or a scanned draft being reviewed: only the save button.
      // Drafts are deleted from the import review card, not from this screen.
      return Semantics(
        button: true,
        label: saveLabel,
        excludeSemantics: true,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('edit_class_save_button'),
            onPressed: _isSaving || _isDeleting ? null : _onSave,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black54,
                    ),
                  )
                : const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: Colors.black,
                  ),
            label: Text(
              _isSaving ? 'Saving…' : saveLabel,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
      );
    }

    // Edit mode: Delete on left (flex 1), Save on right (flex 2)
    return Row(
      children: [
        // Delete button on the left (flex 1)
        Expanded(
          flex: 1,
          child: Semantics(
            button: true,
            label: _deleteArmed ? 'Tap to confirm deletion' : 'Delete class',
            excludeSemantics: true,
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('edit_class_delete_button'),
                onPressed: _isDeleting || _isSaving ? null : _onDeleteTap,
                icon: _isDeleting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white70,
                        ),
                      )
                    : _deleteArmed
                    ? const SizedBox.shrink()
                    : const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                label: Text(
                  _isDeleting
                      ? 'Deleting…'
                      : _deleteArmed
                      ? 'Tap to confirm'
                      : 'Delete',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _deleteArmed
                      ? _EditorColors.dangerArmed
                      : _EditorColors.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Save class button on the right (flex 2)
        Expanded(
          flex: 2,
          child: Semantics(
            button: true,
            label: saveLabel,
            excludeSemantics: true,
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('edit_class_save_button'),
                onPressed: _isSaving || _isDeleting ? null : _onSave,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black54,
                        ),
                      )
                    : const Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: Colors.black,
                      ),
                label: Text(
                  _isSaving ? 'Saving…' : saveLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel({required String label, required bool isRequired}) {
    return RichText(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 13, color: _EditorColors.muted),
        children: [
          if (isRequired)
            const TextSpan(
              text: '*',
              style: TextStyle(
                color: _EditorColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required bool isFocused,
    bool hasError = false,
    String? hintText,
  }) {
    final bgColor = hasError
        ? _EditorColors.fieldError
        : (isFocused ? _EditorColors.fieldFocused : _EditorColors.field);

    return InputDecoration(
      filled: true,
      fillColor: bgColor,
      hintText: hintText,
      hintStyle: const TextStyle(color: _EditorColors.outline, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }
}

/// The editor is an intentionally dark, focused surface regardless of the
/// app theme (a deliberate "compose mode" design). Every color it uses
/// lives here so the palette has a single source of truth.
abstract final class _EditorColors {
  /// Scaffold background (pure black).
  static const Color background = Color(0xFF000000);

  /// Section cards on the black scaffold.
  static const Color surface = Color(0xFF141414);

  /// Text fields and unselected day chips.
  static const Color field = Color(0xFF1F1F1F);

  /// Focused text field fill.
  static const Color fieldFocused = Color(0xFF2C2C2C);

  /// Field fill while showing a validation error.
  static const Color fieldError = Color(0xFF3A1D1D);

  /// Input outlines and hints.
  static const Color outline = Color(0xFF707070);

  /// Secondary text (labels, hints, non-critical copy).
  static const Color muted = Color(0xFFA3A3A3);

  /// Validation errors (soft red that reads on dark surfaces).
  static const Color error = Color(0xFFF28B82);

  /// Delete button.
  static const Color danger = Color(0xFFE53935);

  /// Delete button after the first tap (armed, waiting for confirmation).
  static const Color dangerArmed = Color(0xFFB71C1C);
}
