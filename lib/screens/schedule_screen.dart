import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database_helper.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../utils/next_class.dart';
import '../widgets/day_status_sheet.dart';
import '../routes/app_routes.dart';
import '../services/widget_data_actions.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_state_transition.dart';
import '../widgets/class_delete_undo.dart';
import '../widgets/error_view.dart';
import '../widgets/week_agenda_view.dart';

/// Screen coordinating the student's weekly schedule.
///
/// Displays the single-day agenda view with a week strip, sticky day header,
/// time-ordered class cards, and campus break dividers.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.onSelectedDayChanged, this.dayRequest});

  final ValueChanged<int>? onSelectedDayChanged;

  /// Optional jump channel: another surface (the Today celebration teaser)
  /// sets a weekday 1..7 here; this screen selects it and clears the value.
  final ValueNotifier<int?>? dayRequest;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver {
  final _db = DatabaseHelper.instance;
  List<ClassItem> _classes = [];
  ClassStatuses _statuses = {};
  bool _loading = true;
  String? _error;
  int _selectedDay = DateTime.now().weekday;

  /// +1 when the user moved to a later day, -1 for an earlier one. The
  /// agenda content slides in from that side so the switch reads as direction.
  int _dayDirection = 1;
  int _loadVersion = 0;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db.addListener(_onScheduleChanged);
    widget.dayRequest?.addListener(_onDayRequested);
    _load();
    _startMinuteTimer();
  }

  @override
  void didUpdateWidget(covariant ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dayRequest != oldWidget.dayRequest) {
      oldWidget.dayRequest?.removeListener(_onDayRequested);
      widget.dayRequest?.addListener(_onDayRequested);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _db.removeListener(_onScheduleChanged);
    widget.dayRequest?.removeListener(_onDayRequested);
    _minuteTimer?.cancel();
    super.dispose();
  }

  /// Consume an external day jump (teaser tap): select that day and reset
  /// the channel so the same day can be requested again later.
  void _onDayRequested() {
    final day = widget.dayRequest?.value;
    if (day == null || !mounted) return;
    widget.dayRequest?.value = null;
    if (day < 1 || day > 7) return;
    _selectDay(day);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() {});
        _load();
      }
    }
  }

  void _startMinuteTimer() {
    _minuteTimer?.cancel();
    final now = DateTime.now();
    final untilNextMinute =
        const Duration(minutes: 1) -
        Duration(seconds: now.second, milliseconds: now.millisecond);
    _minuteTimer = Timer(untilNextMinute, () {
      if (!mounted) return;
      if (!_loading && _error == null) setState(() {});
      _startMinuteTimer();
    });
  }

  void _onScheduleChanged() {
    if (mounted) _load();
  }

  /// The class the hero focuses on, when it is today's. The week view highlights it.
  int? _focusClassId() {
    final now = DateTime.now();
    final next = findNextClass(_classes, now, statuses: _statuses);
    if (next == null || next.item.day != now.weekday) return null;
    return next.item.id;
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final classes = await _db.getAll();
      final statuses = await _db.getClassStatuses().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        // Statuses are secondary. If they can't be read, show the schedule without them.
        debugPrint('Class statuses failed to load: $error\n$stackTrace');
        if (mounted) {
          showAppNotification(
            context,
            'Your class marks could not be loaded. Showing classes without them.',
            kind: AppNotificationKind.warning,
          );
        }
        return <int, List<ClassStatusEntry>>{};
      });
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _classes = classes;
        _statuses = statuses;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Schedule load failed: $error\n$stackTrace');
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load your classes. Your saved data wasn\'t changed.';
      });
    }
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  Future<void> _open(ClassItem item) async {
    await Navigator.pushNamed(context, AppRoutes.classForm, arguments: item);
    _load();
  }

  Future<void> _openAddClassForDay(int day) async {
    await Navigator.pushNamed(context, AppRoutes.classForm, arguments: day);
    _load();
  }

  Future<bool> _deleteClass(ClassItem item) => deleteClassWithUndo(
    context,
    item,
    actions: ClassDeleteActions.database,
  );

  void _selectDay(int day) {
    if (day == _selectedDay) return;
    HapticFeedback.selectionClick();
    setState(() {
      _dayDirection = day > _selectedDay ? 1 : -1;
      _selectedDay = day;
    });
    widget.onSelectedDayChanged?.call(day);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = now.weekday;
    final nowMinutes = now.hour * 60 + now.minute;
    final classesByDay = <int, List<ClassItem>>{
      for (var day = 1; day <= 7; day++)
        day: _classes.where((item) => item.day == day).toList()
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes)),
    };

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Weekly schedule'),
      ),
      body: AppStateTransition(
        stateKey: ValueKey(
          _loading
              ? 'loading'
              : _error != null
              ? 'error'
              : 'schedule',
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ErrorView(message: _error!, onRetry: _retry)
            : RefreshIndicator(
                onRefresh: _load,
                child: WeekAgendaView(
                  classesByDay: classesByDay,
                  allClassesEmpty: _classes.isEmpty,
                  today: today,
                  nowMinutes: nowMinutes,
                  selectedDay: _selectedDay,
                  dayDirection: _dayDirection,
                  onSelectDay: _selectDay,
                  focusClassId: _focusClassId(),
                  statusFor: (item) => activeStatusEntry(
                    _statuses,
                    item.id,
                    dateForWeekday(DateTime.now(), item.day),
                  ),
                  onTap: (item) async {
                    final date = dateForWeekday(DateTime.now(), item.day);
                    await showDayStatusSheet(
                      context,
                      item: item,
                      date: date,
                      current: activeStatusEntry(_statuses, item.id, date),
                      actions: DayStatusActions.database,
                    );
                  },
                  onEdit: (item) => _open(item),
                  onLongPress: _deleteClass,
                  onAddClassForDay: _openAddClassForDay,
                ),
              ),
      ),
    );
  }
}
