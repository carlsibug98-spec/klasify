import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/class_item.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../utils/class_text_input_rules.dart';
import '../utils/schedule_rules.dart';
import '../widgets/app_notification.dart';
import '../widgets/class_delete_undo.dart';
import '../widgets/day_chips.dart';
import '../widgets/component_kit.dart';
import '../widgets/app_state_transition.dart';

class ClassFormScreen extends StatefulWidget {
  final ClassItem? item; // null = add, not null = edit
  final int? initialDay; // preselected weekday (1-7) when adding
  final bool returnDraft; // return a new class for timetable import review
  const ClassFormScreen({
    super.key,
    this.item,
    this.initialDay,
    this.returnDraft = false,
  });

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  late final TextEditingController _subject;
  late final TextEditingController _room;
  late final TextEditingController _professor;
  late int _day;
  TimeOfDay? _start;
  TimeOfDay? _end;
  String? _timeError;
  bool _saving = false;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _subject = TextEditingController(text: i?.subject ?? '');
    _room = TextEditingController(text: i?.room ?? '');
    _professor = TextEditingController(
      text: i == null || i.professor == unspecifiedProfessor ? '' : i.professor,
    );
    _day =
        i?.day ??
        (widget.initialDay ?? DateTime.now().weekday).clamp(1, 7).toInt();
    if (i != null) {
      _start = TimeOfDay(
        hour: i.startMinutes ~/ 60,
        minute: i.startMinutes % 60,
      );
      _end = TimeOfDay(hour: i.endMinutes ~/ 60, minute: i.endMinutes % 60);
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _room.dispose();
    _professor.dispose();
    super.dispose();
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  String _showTime(TimeOfDay? t) =>
      t == null ? 'Select' : formatMinutes(_toMinutes(t));

  Future<void> _pickTime(bool isStart) async {
    const fallback = TimeOfDay(hour: 8, minute: 0);
    final initial = isStart
        ? (_start ?? fallback)
        : (_end ?? _start ?? fallback);
    final picked = await showScheduleTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Select start time' : 'Select end time',
    );
    if (picked == null) return;
    final requireBothTimes = _timeError != null;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _timeError = _timeRangeError(requireBothTimes: requireBothTimes);
    });
  }

  String? _timeRangeError({bool requireBothTimes = false}) {
    if (_start == null || _end == null) {
      return requireBothTimes ? 'Please choose a start and end time' : null;
    }
    return _toMinutes(_end!) <= _toMinutes(_start!)
        ? 'End time must be after start time'
        : null;
  }

  String? _required(String? v, String label, {int min = 1}) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return '$label is required';
    if (t.length < min) return '$label must be at least $min characters';
    return null;
  }

  Future<void> _save() async {
    if (_saving) return; // ignore repeated taps while a save is running

    final formOk = _formKey.currentState!.validate();

    final timeErr = _timeRangeError(requireBothTimes: true);
    setState(() => _timeError = timeErr);
    if (!formOk || timeErr != null) return;

    final s = _toMinutes(_start!);
    final e = _toMinutes(_end!);

    final item = ClassItem(
      id: widget.item?.id,
      subject: _subject.text.trim(),
      room: _room.text.trim(),
      professor: _professor.text.trim().isEmpty
          ? unspecifiedProfessor
          : _professor.text.trim(),
      day: _day,
      startMinutes: s,
      endMinutes: e,
    );

    if (widget.returnDraft) {
      Navigator.pop(context, item);
      return;
    }

    setState(() => _saving = true);
    try {
      // Block overlapping classes on the same day
      final sameDay = await _db.getByDay(_day);
      final c = findOverlappingClass(
        sameDay,
        day: _day,
        startMinutes: s,
        endMinutes: e,
        excludeId: widget.item?.id,
      );
      if (c != null) {
        if (!mounted) return;
        setState(() {
          _timeError = 'Overlaps with ${c.subject} (${c.timeRange})';
          _saving = false;
        });
        return;
      }

      if (_isEditing) {
        final changed = await _db.update(item);
        if (changed == 0) {
          throw StateError(
            'This class no longer exists. Refresh the schedule and try again.',
          );
        }
      } else {
        await _db.insert(item);
      }

      var reminderSyncFailed = false;
      try {
        await ReminderService.instance.sync();
      } catch (error, stackTrace) {
        debugPrint(
          'Class saved, but reminder sync failed: $error\n$stackTrace',
        );
        reminderSyncFailed = true;
      }

      if (!mounted) return;
      showAppNotification(
        context,
        _isEditing ? 'Class updated.' : 'Class added.',
        kind: AppNotificationKind.success,
      );
      if (reminderSyncFailed) {
        // Shown as its own message, queued after the success toast.
        showAppNotification(
          context,
          'Saved, but reminders could not be refreshed.',
          kind: AppNotificationKind.warning,
        );
      }
      Navigator.pop(context);
    } catch (error, stackTrace) {
      // Keep everything the user typed so they can just try again.
      debugPrint('Save failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      showAppNotification(
        context,
        'Could not save the class. Please try again.',
        kind: AppNotificationKind.error,
      );
    }
  }

  Future<void> _delete() async {
    if (_saving || widget.item == null) return;
    setState(() => _saving = true);
    final deleted = await deleteClassWithUndo(context, widget.item!);
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit class' : 'Add class')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTheme.pageContentMaxWidth,
          ),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.pageInset,
                    8,
                    AppTheme.pageInset,
                    24,
                  ),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fields marked * are required. Instructor is optional.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Class',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _subject,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [
                            ClassTextInputRules.subjectFormatter,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Subject *',
                            hintText: 'e.g. Mobile Development',
                          ),
                          validator: (v) {
                            final required = _required(v, 'Subject', min: 2);
                            if (required != null) return required;
                            return ClassTextInputRules.isValidSubject(v!)
                                ? null
                                : 'Use letters, numbers, and standard course punctuation';
                          },
                        ),
                        const SizedBox(height: AppTheme.itemGap),
                        TextFormField(
                          controller: _room,
                          textInputAction: TextInputAction.next,
                          inputFormatters: [ClassTextInputRules.roomFormatter],
                          decoration: const InputDecoration(
                            labelText: 'Room *',
                            hintText: 'e.g. 301 or Computer Lab 2',
                          ),
                          validator: (v) {
                            final required = _required(v, 'Room');
                            if (required != null) return required;
                            return ClassTextInputRules.isValidRoom(v!)
                                ? null
                                : 'Use letters, numbers, and standard room punctuation';
                          },
                        ),
                        const SizedBox(height: AppTheme.itemGap),
                        TextFormField(
                          controller: _professor,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: [
                            ClassTextInputRules.professorFormatter,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Professor (optional)',
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isNotEmpty && t.length < 2) {
                              return 'Professor must be at least 2 characters';
                            }
                            if (t.isNotEmpty &&
                                !ClassTextInputRules.isValidProfessor(t)) {
                              return 'Use letters, numbers, and standard name punctuation';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppTheme.sectionGap),
                        Text(
                          'Weekly meeting time',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DayChips(
                          selected: _day,
                          onChanged: (d) => setState(() => _day = d),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TimeBox(
                                label: 'Start *',
                                value: _showTime(_start),
                                isPlaceholder: _start == null,
                                hasError: _timeError != null,
                                onTap: () => _pickTime(true),
                              ),
                            ),
                            const SizedBox(width: AppTheme.itemGap),
                            Expanded(
                              child: TimeBox(
                                label: 'End *',
                                value: _showTime(_end),
                                isPlaceholder: _end == null,
                                hasError: _timeError != null,
                                onTap: () => _pickTime(false),
                              ),
                            ),
                          ],
                        ),
                        AppStateTransition(
                          stateKey: ValueKey(_timeError ?? 'no-time-error'),
                          child: _timeError == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(
                                    top: 10,
                                    left: 4,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        size: 16,
                                        color: scheme.error,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _timeError!,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: scheme.error,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Pinned action bar.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  border: Border(top: BorderSide(color: scheme.outlineVariant)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (_isEditing) ...[
                          Expanded(
                            child: IconButton.filledTonal(
                              tooltip: 'Delete class',
                              onPressed: _saving ? null : _delete,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(64, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.controlRadius,
                                  ),
                                ),
                                backgroundColor: scheme.errorContainer,
                                foregroundColor: scheme.error,
                                disabledBackgroundColor:
                                    scheme.surfaceContainerHigh,
                                disabledForegroundColor:
                                    AppTheme.disabledSecondaryForegroundFor(
                                      scheme,
                                    ),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                          const SizedBox(width: AppTheme.tightGap),
                          Expanded(
                            flex: 2,
                            child: IconButton.filled(
                              tooltip: 'Save changes',
                              onPressed: _saving ? null : _save,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(64, 52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.controlRadius,
                                  ),
                                ),
                              ),
                              icon: AnimatedSwitcher(
                                duration: AppTheme.motionDuration(
                                  context,
                                  AppTheme.motionFast,
                                ),
                                switchInCurve: AppTheme.motionEaseOut,
                                switchOutCurve: AppTheme.motionEaseOut,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: .97,
                                          end: 1,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: _saving
                                    ? const SizedBox(
                                        key: ValueKey('saving'),
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.save_outlined,
                                        key: ValueKey('save-icon'),
                                      ),
                              ),
                            ),
                          ),
                        ] else
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: AnimatedSwitcher(
                                duration: AppTheme.motionDuration(
                                  context,
                                  AppTheme.motionFast,
                                ),
                                switchInCurve: AppTheme.motionEaseOut,
                                switchOutCurve: AppTheme.motionEaseOut,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(
                                          begin: .97,
                                          end: 1,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: _saving
                                    ? const SizedBox(
                                        key: ValueKey('saving'),
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        key: const ValueKey('save-label'),
                                        widget.returnDraft
                                            ? 'Add to review list'
                                            : 'Save class',
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
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
