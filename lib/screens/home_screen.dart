import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../routes/app_routes.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../models/event_item.dart';
import '../widgets/day_status_sheet.dart';
import '../utils/next_class.dart';
import '../widgets/app_notification.dart';
import '../widgets/campus_break_divider.dart';
import '../widgets/class_card.dart';
import '../widgets/class_delete_undo.dart';
import '../widgets/class_segment_row.dart';
import '../widgets/error_view.dart';
import '../widgets/event_sheet.dart';
import '../widgets/event_tile.dart';
import '../widgets/first_run_options.dart';
import '../widgets/next_class_card.dart';
import '../services/first_class_coach_store.dart';
import '../services/reminder_service.dart';
import '../services/coach_tour_store.dart';
import '../widgets/coach_tour_overlay.dart';
import '../widgets/swipe_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/app_state_transition.dart';
import '../widgets/empty_state_card.dart';
import '../widgets/week_agenda_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.heroKey,
    this.swipeTargetKey,
    this.firstRunTilesKey,
    this.tourSwipeDemo,
    this.onScheduleBecameNonEmpty,
    this.onPeekWeek,
    this.onJumpToDay,
  });

  /// Coach-tour anchors when the tour is active: the hero block and the first
  /// class card of Today. Null outside of MainNavigationScreen (tests).
  final Key? heroKey;
  final Key? swipeTargetKey;

  /// Key of the first-run Scan/Add tiles — the spotlight anchor for the
  /// one-time empty-schedule coach ("Explore first" path). Null outside of
  /// MainNavigationScreen, where the coach stays hidden (tests).
  final GlobalKey? firstRunTilesKey;

  /// True while the tour demonstrates the swipe gesture on the first card.
  final ValueListenable<bool>? tourSwipeDemo;

  /// Fires the moment the schedule goes from empty to having a first class —
  /// the approved trigger for the one-time coach tour.
  final VoidCallback? onScheduleBecameNonEmpty;

  /// The "2 of 4 done" counter taps through to the Week tab (peek).
  final VoidCallback? onPeekWeek;

  /// The celebration teaser taps through to the Week tab with a day (1..7)
  /// preselected.
  final ValueChanged<int>? onJumpToDay;

  /// Shared no-op listenable for callers that don't run the tour (tests).
  static final ValueNotifier<bool> swipeDemoOff = ValueNotifier<bool>(false);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _db = DatabaseHelper.instance;
  List<ClassItem> _classes = [];
  ClassStatuses _statuses = {};
  List<EventItem> _events = [];
  bool _loading = true;
  String? _error;
  int _loadVersion = 0;
  Timer? _heroRefreshTimer;
  bool _scheduleWasEmpty = true;

  // ---- First-run coach (one-time, on an empty schedule) ----
  /// The spotlight over the Scan/Add tiles for newcomers who came through
  /// "Explore first" or skipped onboarding, mounted on top of this Scaffold.
  bool _firstClassCoachActive = false;

  /// Set once the eligibility check has run: the overlay shows on the
  /// schedule load that finds zero classes, and later empty states (a user
  /// who deleted everything) stay coach-free rather than nagging again.
  bool _firstClassCoachDecided = false;

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
      if (mounted) {
        showAppNotification(
          context,
          'Class reminders could not be refreshed.',
          kind: AppNotificationKind.warning,
        );
      }
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
        if (mounted) {
          showAppNotification(
            context,
            'Your class marks could not be loaded. Showing classes without them.',
            kind: AppNotificationKind.warning,
          );
        }
        return <int, List<ClassStatusEntry>>{};
      });
      final events = await _db.getAllEvents().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        // Events are this section's own data; losing them shouldn't take
        // the schedule down with the failure.
        debugPrint('Events failed to load: $error\n$stackTrace');
        if (mounted) {
          showAppNotification(
            context,
            'Your events could not be loaded. Showing without them.',
            kind: AppNotificationKind.warning,
          );
        }
        return <EventItem>[];
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
        _events = events;
        _loading = false;
        _error = null;
      });
      // Post-frame: the empty state renders on this frame, and the coach's
      // own post-frame prune needs to find the tiles key laid out.
      if (list.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeStartFirstClassCoach(),
        );
      }
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

  /// The one-time empty-schedule coach: newcomers who explore without adding
  /// a class land on the bare Scan/Add tiles with no tour yet (the tour only
  /// fires after the first class exists). One shot, persisted, and never
  /// stacked on top of the full tour.
  Future<void> _maybeStartFirstClassCoach() async {
    if (widget.firstRunTilesKey == null) return;
    if (_firstClassCoachActive || _firstClassCoachDecided) return;
    _firstClassCoachDecided = true;
    // Whoever already took the full tour knows their way around.
    if (await CoachTourStore.isShown()) return;
    if (await FirstClassCoachStore.isDismissed()) return;
    if (!mounted) return;
    setState(() => _firstClassCoachActive = true);
  }

  /// Dismiss the empty-schedule coach and persist the one-shot, whether the
  /// user tapped Dismiss, Got it, or anywhere outside the tooltip.
  void _endFirstClassCoach() {
    if (!_firstClassCoachActive) return;
    unawaited(FirstClassCoachStore.markDismissed());
    setState(() => _firstClassCoachActive = false);
  }

  /// The free-time card: all done for today, a weekday with no classes, or a
  /// weekend. It shows only the status — plus, when the schedule has a next
  /// class coming up (e.g. Monday's first one), a tappable teaser shelf that
  /// jumps to that day on the Week tab.
  Widget _celebrationHero({
    required bool allDone,
    required DateTime now,
    NextClass? next,
  }) {
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

    final teaser = next;
    final hasTeaser = teaser != null && !teaser.isNow;
    return NextClassCard.celebration(
      key: const ValueKey('next-class-celebration'),
      title: title,
      subtitle: subtitle,
      icon: icon,
      dayPillText: hasTeaser ? teaser.dayPillText(now) : null,
      whenText: hasTeaser ? teaser.whenText : '',
      subject: hasTeaser ? teaser.item.subject : '',
      time: hasTeaser ? teaser.item.timeRange : '',
      room: hasTeaser ? formatRoom(teaser.item.room) : '',
      onTeaserTap: hasTeaser
          ? () => widget.onJumpToDay?.call(teaser.item.day)
          : null,
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
    // The Events list shows this moment forward; started and past events
    // drop out (the minute ticker re-renders the list exactly then).
    final upcomingEvents = _events.where((e) => e.isUpcomingOn(now)).toList();
    final today = _classes.where((c) => c.day == now.weekday).toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final hasTodayClasses = today.isNotEmpty;
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

    // The Today list renders as the same segmented stacks the Week tab
    // shows: consecutive classes (gap under the week view's break
    // threshold) merge into one rail — 16px group corners, 2px softened
    // meeting edges, 1px seams — and every stack boundary carries a
    // coffee chip.
    final stacks = <List<ClassItem>>[];
    for (final c in today) {
      final previous = stacks.isEmpty ? null : stacks.last.last;
      if (previous != null &&
          c.startMinutes - previous.endMinutes <
              WeekAgendaView.breakThreshold) {
        stacks.last.add(c);
      } else {
        stacks.add([c]);
      }
    }

    // The Today list is a QUEUE. Classes that already ended — or were
    // resolved on the day-status sheet — leave the Today screen entirely;
    // their done state lives on the weekly schedule instead. What remains
    // is what hasn't run yet: the live/next class is promoted into the
    // hero and the rest queue beneath it.
    bool resolvedForToday(ClassItem c) =>
        classStatusAt(c, nowMinutes) == ClassStatus.done ||
        activeDayStatus(_statuses, c.id, now) != null;
    final int promotedKey = next == null
        ? -1
        : (next.item.id ??
            Object.hash(next.item.subject, next.item.day, next.item.startMinutes));
    final remaining = today
        .where(
          (c) =>
              next == null ||
              (c.id ?? Object.hash(c.subject, c.day, c.startMinutes)) !=
                  promotedKey,
        )
        .where((c) => !resolvedForToday(c))
        .toList();
    final hasRemainingClasses = remaining.isNotEmpty;
    final remainingStacks = <List<ClassItem>>[];
    for (final c in remaining) {
      final previous = remainingStacks.isEmpty
          ? null
          : remainingStacks.last.last;
      if (previous != null &&
          c.startMinutes - previous.endMinutes <
              WeekAgendaView.breakThreshold) {
        remainingStacks.last.add(c);
      } else {
        remainingStacks.add([c]);
      }
    }
    // Under a live hero the first queued card is the next-up one. A
    // countdown hero already is the next-up class, so no row below wears
    // the tag then.
    int? nextRemainingKey;
    if (next != null && next.isNow && remaining.isNotEmpty) {
      nextRemainingKey = remaining.first.id ??
          Object.hash(remaining.first.subject, remaining.first.day,
              remaining.first.startMinutes);
    }

    // One slot of the Today list: the keyed segment row inside its swipe
    // plane, seams riding on the plane's padding so they collapse with the
    // row on delete. The first slot of the day is the coach tour's swipe
    // demo target: the tour holds its actions plane open while step 2 is
    // showing.
    Widget classRow(ClassItem c, int rowIndex, int stackLength) {
      final radius = AppTheme.segmentRadiusOf(rowIndex, stackLength);
      final isSeam = rowIndex < stackLength - 1;
      final padding = EdgeInsets.fromLTRB(
        AppTheme.pageInset,
        0,
        AppTheme.pageInset,
        isSeam ? AppTheme.segmentGap : 0,
      );
      final segment = ClassSegmentRow(
        item: c,
        radius: radius,
        status: classStatusAt(c, nowMinutes),
        statusEntry: activeStatusEntry(_statuses, c.id, now),
        // The orange time follows the hero: the class in progress, or the
        // next one once the current is marked.
        isFocus:
            nextRemainingKey != null &&
            (c.id ??
                    Object.hash(c.subject, c.day, c.startMinutes)) ==
                nextRemainingKey,
        onTap: () => showDayStatusSheet(
          context,
          item: c,
          date: now,
          current: activeStatusEntry(_statuses, c.id, now),
        ),
        onLongPress: () => _deleteClass(c),
      );
      final plane = identical(c, remainingStacks.first.first)
          ? ValueListenableBuilder<bool>(
              valueListenable: widget.tourSwipeDemo ?? HomeScreen.swipeDemoOff,
              builder: (context, demo, row) => SwipeActions(
                targetKey: widget.swipeTargetKey,
                forceOpen: demo,
                padding: padding,
                borderRadius: radius,
                onEdit: () => _open(AppRoutes.classForm, c),
                onDelete: () => _deleteClass(c),
                child: row!,
              ),
              child: segment,
            )
          : SwipeActions(
              padding: padding,
              borderRadius: radius,
              onEdit: () => _open(AppRoutes.classForm, c),
              onDelete: () => _deleteClass(c),
              child: segment,
            );
      // Per-class key: a list shift reuses slots by identity, so
      // SwipeActions never inherits another class's plane state.
      return KeyedSubtree(
        key: ValueKey(
          'today-class-${c.id ?? Object.hash(c.subject, c.day, c.startMinutes)}',
        ),
        child: plane,
      );
    }

    final scaffold = Scaffold(
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
                                    // crossfade between two solid tier
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
                                      next: next,
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
                                      targetKey: widget.heroKey,
                                      radius: 28,
                                      onEdit: () =>
                                          _open(AppRoutes.classForm, next.item),
                                      onDelete: () => _deleteClass(next.item),
                                      child: NextClassCard(
                                        label: next.isNow
                                            ? 'Live now'
                                            : 'Next up',
                                        subject: next.item.subject,
                                        // The room rides the status line in
                                        // both states, matching the widget.
                                        room: next.item.room.trim().isEmpty
                                            ? ''
                                            : formatRoom(next.item.room),
                                        countdown: next.isNow
                                            ? Duration(
                                                minutes: next.minutesToEnd,
                                              )
                                            : Duration(
                                                minutes: next.minutesUntil,
                                              ),
                                        // The live row's right side: "Ends in
                                        // 24m". The next-up state carries the
                                        // big countdown instead.
                                        whenText: next.isNow
                                            ? next.whenText
                                            : '',
                                        // A class on another day carries the
                                        // day pill in the header (TOMORROW,
                                        // or the weekday). Today's next-up
                                        // stays pill-free.
                                        dayPillText: !next.isNow &&
                                                next.item.day != now.weekday
                                            ? next.dayPillText(now)
                                            : null,
                                        // The elapsed bar sits inside the
                                        // live card now (6px rounded gradient
                                        // track), not on its bottom edge.
                                        liveProgress: next.isNow
                                            ? ((nowMinutes -
                                                          next
                                                              .item
                                                              .startMinutes) /
                                                      (next.item.endMinutes -
                                                          next
                                                              .item
                                                              .startMinutes))
                                                  .clamp(0.0, 1.0)
                                            : null,
                                        liveRemaining: next.isNow
                                            ? Duration(
                                                minutes:
                                                    (next.item.endMinutes -
                                                            nowMinutes)
                                                        .clamp(0, 24 * 60),
                                              )
                                            : null,
                                        onLongPress: () =>
                                            _deleteClass(next.item),
                                      ),
                                    ),
                            ),
                          ),
                        // Classes beneath the hero (moved up from below Events):
                        // the day's classes except the one promoted into the
                        // hero, segmented stacks with break chips. The first
                        // remaining card is marked "next up".
                        if (hasTodayClasses && hasRemainingClasses)
                          for (final (stackIndex, stack)
                              in remainingStacks.indexed) ...[
                            for (final (rowIndex, c) in stack.indexed)
                              classRow(c, rowIndex, stack.length),
                            if (stackIndex < remainingStacks.length - 1)
                              CampusBreakDivider(
                                breakMinutes:
                                    remainingStacks[stackIndex + 1]
                                            .first
                                            .startMinutes -
                                        stack.last.endMinutes,
                              ),
                          ],
                        if (!hasTodayClasses)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.pageInset,
                            ),
                            child: _TodayEmptyState(
                              hasSchedule: _classes.isNotEmpty,
                              tilesKey: widget.firstRunTilesKey,
                            ),
                          ),
                        // Whole-school events: a count chip, an Add entry, and
                        // date-block rows. The section header stays even with
                        // zero events so the entry point never disappears under
                        // updates.
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
                                  'Events',
                                  style:
                                      Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              if (upcomingEvents.isNotEmpty)
                                Semantics(
                                  button: false,
                                  label:
                                      '${upcomingEvents.length} upcoming '
                                      'event${upcomingEvents.length == 1 ? '' : 's'}',
                                  excludeSemantics: true,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${upcomingEvents.length}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Semantics(
                                  button: true,
                                  label: 'Add event',
                                excludeSemantics: true,
                                child: InkWell(
                                  key: const ValueKey('events-add'),
                                  onTap: () => showEventSheet(context),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Add',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimary,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // The events stack: segmented rows like the class
                        // stacks, nearest first wearing the inverted date
                        // block.
                        for (final (eventIndex, event)
                            in upcomingEvents.indexed)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              AppTheme.pageInset,
                              0,
                              AppTheme.pageInset,
                              eventIndex < upcomingEvents.length - 1
                                  ? AppTheme.segmentGap
                                  : 0,
                            ),
                            child: KeyedSubtree(
                              key: ValueKey(
                                'event-home-${event.id ?? Object.hash(event.title, event.date, event.startMinutes)}',
                              ),
                              child: EventTile(
                                event: event,
                                now: now,
                                radius: AppTheme.segmentRadiusOf(
                                  eventIndex,
                                  upcomingEvents.length,
                                ),
                                inverted: eventIndex == 0,
                                onTap: () =>
                                    showEventSheet(context, initial: event),
                                onLongPress: () =>
                                    deleteEventWithUndo(context, event),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );

    // The end of the stack is the empty-schedule coach: positioned.fill over
    // the shell, the same arrangement as the shell's full coach tour.
    if (_firstClassCoachActive) {
      return Stack(
        children: [
          Positioned.fill(child: scaffold),
          CoachTourOverlay(
            keys: CoachTargetKeys.single(widget.firstRunTilesKey!),
            steps: CoachTourOverlay.firstRunSteps,
            onDone: _endFirstClassCoach,
          ),
        ],
      );
    }
    return scaffold;
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
  const _TodayEmptyState({required this.hasSchedule, this.tilesKey});

  final bool hasSchedule;

  /// Spotlight anchor for the empty-schedule coach; null hides the coach.
  final Key? tilesKey;

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
      key: tilesKey,
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
