import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../routes/app_routes.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../widgets/day_status_sheet.dart';
import '../utils/next_class.dart';
import '../widgets/class_card.dart';
import '../widgets/class_delete_undo.dart';
import '../widgets/error_view.dart';
import '../widgets/first_run_options.dart';
import '../widgets/next_class_card.dart';
import '../services/reminder_service.dart';
import '../widgets/swipe_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/app_state_transition.dart';
import '../widgets/empty_state_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.heroKey,
    this.swipeTargetKey,
    this.tourSwipeDemo,
    this.onScheduleBecameNonEmpty,
  });

  /// Coach-tour anchors when the tour is active: the hero block and the first
  /// class card of Today. Null outside of MainNavigationScreen (tests).
  final Key? heroKey;
  final Key? swipeTargetKey;

  /// True while the tour demonstrates the swipe gesture on the first card.
  final ValueListenable<bool>? tourSwipeDemo;

  /// Fires the moment the schedule goes from empty to having a first class —
  /// the approved trigger for the one-time coach tour.
  final VoidCallback? onScheduleBecameNonEmpty;

  /// Shared no-op listenable for callers that don't run the tour (tests).
  static final ValueNotifier<bool> swipeDemoOff = ValueNotifier<bool>(false);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _db = DatabaseHelper.instance;
  List<ClassItem> _classes = [];
  ClassStatuses _statuses = {};
  bool _loading = true;
  String? _error;
  int _loadVersion = 0;
  Timer? _heroRefreshTimer;
  bool _scheduleWasEmpty = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db.addListener(_onScheduleChanged);
    _load();
    unawaited(_syncRemindersOnLaunch());
    _scheduleHeroRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _db.removeListener(_onScheduleChanged);
    _heroRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
      _scheduleHeroRefresh();
    } else {
      _heroRefreshTimer?.cancel();
    }
  }

  void _scheduleHeroRefresh() {
    _heroRefreshTimer?.cancel();
    final now = DateTime.now();
    final untilNextMinute =
        const Duration(minutes: 1) -
        Duration(seconds: now.second, milliseconds: now.millisecond);
    _heroRefreshTimer = Timer(untilNextMinute, () {
      if (!mounted) return;
      if (!_loading && _error == null) setState(() {});
      _scheduleHeroRefresh();
    });
  }

  void _onScheduleChanged() {
    if (mounted) _load();
  }

  Future<void> _syncRemindersOnLaunch() async {
    try {
      await ReminderService.instance.sync();
    } catch (error) {
      debugPrint('Reminder sync failed: $error');
    }
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final list = await _db.getAll();
      final statuses = await _db.getClassStatuses().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        // Statuses are secondary. If they can't be read, show the schedule without them.
        debugPrint('Class statuses failed to load: $error\n$stackTrace');
        return <int, List<ClassStatusEntry>>{};
      });
      if (!mounted || version != _loadVersion) return;
      // First class lands: the one-time coach tour trigger.
      final scheduleWasEmpty = _scheduleWasEmpty;
      _scheduleWasEmpty = list.isEmpty;
      if (list.isNotEmpty && scheduleWasEmpty) {
        widget.onScheduleBecameNonEmpty?.call();
      }
      setState(() {
        _classes = list;
        _statuses = statuses;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Home load failed: $error\n$stackTrace');
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

  /// The free-time card: all done for today, a weekday with no classes, or a
  /// weekend. It shows only the status, never the next class.
  Widget _celebrationHero({required bool allDone, required DateTime now}) {
    final isWeekend = now.weekday >= DateTime.saturday;
    final String title;
    final String subtitle;
    final IconData icon;
    if (allDone) {
      title = 'All done for today';
      subtitle = 'Enjoy the rest of your ${_weekdayName(now.weekday)}.';
      icon = Icons.check_circle_outline_rounded;
    } else if (isWeekend) {
      title = 'Weekend off';
      subtitle = 'No classes today. Enjoy your break.';
      icon = Icons.weekend_outlined;
    } else {
      title = 'No classes today';
      subtitle = 'Nothing scheduled. Enjoy the open time.';
      icon = Icons.wb_sunny_outlined;
    }

    return NextClassCard.celebration(
      key: const ValueKey('next-class-celebration'),
      title: title,
      subtitle: subtitle,
      icon: icon,
    );
  }

  Future<void> _open(String route, [Object? args]) async {
    await Navigator.pushNamed(context, route, arguments: args);
    _load();
  }

  Future<bool> _deleteClass(ClassItem item) =>
      deleteClassWithUndo(context, item);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final next = findNextClass(_classes, now, statuses: _statuses);
    final today = _classes.where((c) => c.day == now.weekday).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final hasTodayClasses = today.isNotEmpty;
    final nextId = next?.item.id;
    final doneCount = today
        .where(
          (c) =>
              classStatusAt(c, nowMinutes) == ClassStatus.done ||
              activeDayStatus(_statuses, c.id, now) != null,
        )
        .length;
    final allDoneForToday = hasTodayClasses && doneCount == today.length;
    final isFreeDay = !hasTodayClasses && _classes.isNotEmpty;
    final isCelebration =
        (allDoneForToday || isFreeDay) && (next == null || !next.isNow);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Klasify'),
            Text(
              'Today · ${MaterialLocalizations.of(context).formatShortDate(now)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppTheme.pageContentMaxWidth,
                    ),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        _DateHeader(date: now),
                        if (next != null || _classes.isEmpty)
                          Padding(
                            key: widget.heroKey,
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.pageInset,
                              4,
                              AppTheme.pageInset,
                              10,
                            ),
                            child: AnimatedSwitcher(
                              duration: AppTheme.motionDuration(
                                context,
                                AppTheme.motionStandard,
                              ),
                              switchInCurve: AppTheme.motionEaseOut,
                              switchOutCurve: AppTheme.motionEaseOut,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    // The 2% vertical slide masks the
                                    // crossfade between two solid black
                                    // cards so they don't ghost into each
                                    // other (same pattern as
                                    // app_state_transition.dart).
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, .02),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: isCelebration
                                  ? _celebrationHero(
                                      allDone: allDoneForToday,
                                      now: now,
                                    )
                                  : next == null
                                  ? const NextClassCard.empty(
                                      key: ValueKey('next-class-empty'),
                                    )
                                  // The hero row carries the same swipe
                                  // plane as the list rows: full-swipe
                                  // deletes with the 5-second undo, the
                                  // plane's Edit opens the class form. The
                                  // celebration and empty variants stay
                                  // unwrapped — there is no class to act on.
                                  : SwipeActions(
                                      key: ValueKey(
                                        '${next.item.day}:${next.item.startMinutes}:${next.item.subject}:${next.isNow}',
                                      ),
                                      radius: 28,
                                      onEdit: () =>
                                          _open(AppRoutes.classForm, next.item),
                                      onDelete: () => _deleteClass(next.item),
                                      child: NextClassCard(
                                        label: next.isNow
                                            ? 'In class'
                                            : 'Upcoming',
                                        subject: next.item.subject,
                                        room: next.item.room.trim().isEmpty
                                            ? ''
                                            : formatRoom(next.item.room),
                                        professor:
                                            next.item.professor
                                                    .trim()
                                                    .toLowerCase() ==
                                                'not specified'
                                            ? ''
                                            : next.item.professor.trim(),
                                        time: next.item.timeRange,
                                        // The scheduling widget's copy: live
                                        // classes count down ("Ends in 1h
                                        // 12m"), upcoming ones give the
                                        // start clock ("Starts 4:00 PM").
                                        whenText: next.whenText,
                                        onLongPress: () =>
                                            _deleteClass(next.item),
                                      ),
                                    ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.pageInset,
                            AppTheme.sectionGap,
                            AppTheme.pageInset,
                            12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Text(
                                  "Today's classes",
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              if (hasTodayClasses)
                                Text(
                                  '$doneCount of ${today.length} done',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                            ],
                          ),
                        ),
                        if (!hasTodayClasses)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.pageInset,
                            ),
                            child: _TodayEmptyState(
                              hasSchedule: _classes.isNotEmpty,
                            ),
                          )
                        else
                          for (final (index, c) in today.indexed)
                            if (index == 0)
                              // The first card is the coach tour's swipe
                              // demo target: the tour holds its actions
                              // plane open while step 2 is showing.
                              ValueListenableBuilder<bool>(
                                key: widget.swipeTargetKey,
                                valueListenable:
                                    widget.tourSwipeDemo ??
                                    HomeScreen.swipeDemoOff,
                                builder: (context, demo, card) => SwipeActions(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppTheme.pageInset,
                                    0,
                                    AppTheme.pageInset,
                                    10,
                                  ),
                                  forceOpen: demo,
                                  onEdit: () => _open(AppRoutes.classForm, c),
                                  onDelete: () => _deleteClass(c),
                                  child: card!,
                                ),
                                child: ClassCard(
                                  item: c,
                                  insetHorizontally: false,
                                  trailingGap: false,
                                  status: classStatusAt(c, nowMinutes),
                                  statusEntry: activeStatusEntry(
                                    _statuses,
                                    c.id,
                                    now,
                                  ),
                                  onTap: () => showDayStatusSheet(
                                    context,
                                    item: c,
                                    date: now,
                                    current: activeStatusEntry(
                                      _statuses,
                                      c.id,
                                      now,
                                    ),
                                  ),
                                  // The next class in the list gets the same accent
                                  // as the hero, so the list links back to it.
                                  isNext:
                                      nextId != null &&
                                      c.id == nextId &&
                                      !next!.isNow,
                                  // The orange time follows the hero: the class in
                                  // progress, or the next one once the current is marked.
                                  isFocus:
                                      nextId != null &&
                                      c.id == nextId &&
                                      !isCelebration,
                                  onEdit: () => _open(AppRoutes.classForm, c),
                                  onDelete: () => _deleteClass(c),
                                  onLongPress: () => _deleteClass(c),
                                ),
                              )
                            else
                              SwipeActions(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTheme.pageInset,
                                  0,
                                  AppTheme.pageInset,
                                  10,
                                ),
                                onEdit: () => _open(AppRoutes.classForm, c),
                                onDelete: () => _deleteClass(c),
                                child: ClassCard(
                                  item: c,
                                  insetHorizontally: false,
                                  trailingGap: false,
                                  status: classStatusAt(c, nowMinutes),
                                  statusEntry: activeStatusEntry(
                                    _statuses,
                                    c.id,
                                    now,
                                  ),
                                  onTap: () => showDayStatusSheet(
                                    context,
                                    item: c,
                                    date: now,
                                    current: activeStatusEntry(
                                      _statuses,
                                      c.id,
                                      now,
                                    ),
                                  ),
                                  // The next class in the list gets the same accent
                                  // as the hero, so the list links back to it.
                                  isNext:
                                      nextId != null &&
                                      c.id == nextId &&
                                      !next!.isNow,
                                  // The orange time follows the hero: the class in
                                  // progress, or the next one once the current is marked.
                                  isFocus:
                                      nextId != null &&
                                      c.id == nextId &&
                                      !isCelebration,
                                  onEdit: () => _open(AppRoutes.classForm, c),
                                  onDelete: () => _deleteClass(c),
                                  onLongPress: () => _deleteClass(c),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// "Tuesday" with the date beneath. The page title stays the app name.
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pageInset,
        8,
        AppTheme.pageInset,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dayNames[date.weekday - 1],
            style: theme.textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}

class _TodayEmptyState extends StatelessWidget {
  const _TodayEmptyState({required this.hasSchedule});

  final bool hasSchedule;

  @override
  Widget build(BuildContext context) {
    if (hasSchedule) {
      return const EmptyStateCard(
        icon: Icons.event_available_outlined,
        title: 'Nothing scheduled today',
        // Same line the Week agenda shows, in the app's second-person voice.
        message: 'Enjoy your open space.',
      );
    }
    return FirstRunOptions(
      onScan: () => Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamed<void>(AppRoutes.importSchedule),
      onAdd: () => Navigator.pushNamed(context, AppRoutes.classForm),
    );
  }
}

/// Weekday name for the celebration subtitle, matching the design's
/// "Enjoy the rest of your Saturday." voice.
String _weekdayName(int weekday) => switch (weekday) {
  DateTime.monday => 'Monday',
  DateTime.tuesday => 'Tuesday',
  DateTime.wednesday => 'Wednesday',
  DateTime.thursday => 'Thursday',
  DateTime.friday => 'Friday',
  DateTime.saturday => 'Saturday',
  _ => 'Sunday',
};
