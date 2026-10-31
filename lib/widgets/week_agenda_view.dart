import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../theme/app_theme.dart';
import 'campus_break_divider.dart';
import 'class_card.dart';
import 'class_segment_row.dart';
import 'empty_state_card.dart';
import 'first_run_options.dart';
import 'selected_day_header.dart';
import 'swipe_actions.dart';
import 'weekday_tile.dart';

/// Single-day agenda view showing the segmented day bar, sticky day header,
/// and the day's classes as segmented stacks (approved mockup C) with
/// campus break chips between the stacks.
///
/// The stacks follow the settings' A₂ language: classes with less than a
/// [breakThreshold]-minute gap merge into one stack — first row takes the
/// 16px top corners, meeting edges soften to 2px, and a 2px seam separates
/// the rows — while a gap of [breakThreshold] minutes or more starts a new
/// stack with a [CampusBreakDivider] between.
class WeekAgendaView extends StatelessWidget {
  const WeekAgendaView({
    super.key,
    required this.classesByDay,
    required this.allClassesEmpty,
    required this.today,
    required this.nowMinutes,
    required this.selectedDay,
    required this.dayDirection,
    required this.onSelectDay,
    this.onTap,
    this.statusFor,
    this.focusClassId,
    required this.onEdit,
    required this.onLongPress,
    required this.onAddClassForDay,
  });

  final Map<int, List<ClassItem>> classesByDay;
  final bool allClassesEmpty;
  final int today;
  final int nowMinutes;
  final int selectedDay;

  /// +1 when the selected day moved later, -1 for earlier. The day content
  /// slides in from that side so the switch reads as direction.
  final int dayDirection;
  final ValueChanged<int> onSelectDay;
  final ValueChanged<ClassItem>? onTap;
  final ClassStatusEntry? Function(ClassItem item)? statusFor;

  /// The class the hero focuses on, when it is today's. Its time takes the live color.
  final int? focusClassId;
  final ValueChanged<ClassItem> onEdit;

  /// Deletes the class. Reports whether the delete happened, so the swipe
  /// plane can restore the row when it fails.
  final Future<bool> Function(ClassItem) onLongPress;
  final ValueChanged<int> onAddClassForDay;

  /// The gap (in minutes) from which two classes are separate stacks with a
  /// break chip between, matching the divider rule this view always used.
  static const int breakThreshold = 15;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Normalize to date-only to eliminate Daylight Saving Time and hour boundary drift
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final monday = todayMidnight.subtract(Duration(days: today - 1));
    final selectedDate = monday.add(Duration(days: selectedDay - 1));
    final selectedClasses = classesByDay[selectedDay]!;
    final isToday = selectedDay == today;

    // Calculate total hours scheduled for the selected day
    final totalHours = selectedClasses.fold<double>(
      0.0,
      (sum, item) => sum + ((item.endMinutes - item.startMinutes) / 60.0),
    );

    // Consecutive classes (gap under [breakThreshold]) merge into one
    // segmented stack; every stack boundary carries a break chip.
    final stacks = <List<ClassItem>>[];
    for (final item in selectedClasses) {
      final previous = stacks.isEmpty ? null : stacks.last.last;
      if (previous != null &&
          item.startMinutes - previous.endMinutes < breakThreshold) {
        stacks.last.add(item);
      } else {
        stacks.add([item]);
      }
    }
    final entries = <_AgendaEntry>[
      for (var s = 0; s < stacks.length; s++) ...[
        for (var row = 0; row < stacks[s].length; row++)
          _ClassEntry(stacks[s], row),
        // Stacks only break on a >= [breakThreshold] gap, so every boundary
        // has a real break to name.
        if (s < stacks.length - 1)
          _BreakEntry(
            stacks[s + 1].first.startMinutes - stacks[s].last.endMinutes,
          ),
      ],
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppTheme.pageContentMaxWidth,
        ),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Segmented day bar: one 2px-seamed row of day segments.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pageInset,
                10,
                AppTheme.pageInset,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Semantics(
                  label: 'Choose a day of the week',
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final weekdayTiles = [
                        for (var index = 0; index < dayNames.length; index++)
                          WeekdayTile(
                            date: monday.add(Duration(days: index)),
                            name: dayNames[index],
                            classCount: classesByDay[index + 1]!.length,
                            isToday: index + 1 == today,
                            selected: index + 1 == selectedDay,
                            onTap: () => onSelectDay(index + 1),
                            borderRadius: AppTheme.segmentRadiusHOf(
                              index,
                              dayNames.length,
                            ),
                          ),
                      ];

                      // If width allows, distribute evenly across the row
                      if (constraints.maxWidth >=
                          dayNames.length * 44 + (dayNames.length - 1) * 2) {
                        return Row(
                          children: [
                            for (var index = 0;
                                index < weekdayTiles.length;
                                index++) ...[
                              if (index > 0) const SizedBox(width: 2),
                              Expanded(child: weekdayTiles[index]),
                            ],
                          ],
                        );
                      }

                      // On narrower widths, keep a smooth single-row horizontal scroll
                      // rather than breaking the week into disjoint rows
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (var index = 0;
                                index < weekdayTiles.length;
                                index++) ...[
                              if (index > 0) const SizedBox(width: 2),
                              SizedBox(width: 48, child: weekdayTiles[index]),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),

            // Sticky Header displaying Selected Day and Daily Workload Badge
            SliverPersistentHeader(
              pinned: true,
              delegate: SelectedDayHeaderDelegate(
                dayName: dayNames[selectedDay - 1],
                formattedDate: MaterialLocalizations.of(
                  context,
                ).formatShortMonthDay(selectedDate),
                classCount: selectedClasses.length,
                totalHours: totalHours,
              ),
            ),

            // Class stacks or Empty States. Switching days plays a short
            // directional fade+slide instead of teleporting: the content
            // swaps immediately, then a 120ms enter-only transition runs,
            // matching the tab-switch motion. The list stays lazy (builder
            // delegate) and rows scrolled into view later do not re-animate.
            _DaySwitchTransition(
              day: selectedDay,
              dayDirection: dayDirection,
              sliverBuilder: (slide) => selectedClasses.isEmpty
                  ? SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.pageInset,
                        16,
                        AppTheme.pageInset,
                        100,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: SlideTransition(
                          position: slide,
                           child: allClassesEmpty
                               ? FirstRunOptions(
                                   onScan: () => Navigator.of(
                                     context,
                                     rootNavigator: true,
                                   ).pushNamed<void>(AppRoutes.importSchedule),
                                   onAdd: () => onAddClassForDay(selectedDay),
                                 )
                               : EmptyStateCard(
                                  icon: Icons.event_available_outlined,
                                  title: 'Nothing scheduled',
                                  message: 'Enjoy your open space.',
                                  actions: [
                                    FilledButton.icon(
                                      onPressed: () =>
                                          onAddClassForDay(selectedDay),
                                      icon: const Icon(Icons.add_rounded),
                                      label: Text(
                                        'Add a class for ${dayNames[selectedDay - 1]}',
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.only(top: 12, bottom: 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry = entries[index];
                            if (entry is _BreakEntry) {
                              return SlideTransition(
                                position: slide,
                                child: CampusBreakDivider(
                                  breakMinutes: entry.minutes,
                                ),
                              );
                            }
                            final classEntry = entry as _ClassEntry;
                            final item = classEntry.stack[classEntry.rowIndex];
                            final isSeam =
                                classEntry.rowIndex < classEntry.stack.length - 1;
                            final rowRadius = AppTheme.segmentRadiusOf(
                              classEntry.rowIndex,
                              classEntry.stack.length,
                            );
                            return KeyedSubtree(
                              // Per-class key: a day switch or a list shift
                              // reuses slots by identity, so SwipeActions
                              // never inherits another class's plane state.
                              key: ValueKey(
                                'class-${item.id ?? Object.hash(item.subject, item.day, item.startMinutes)}',
                              ),
                              child: SlideTransition(
                                position: slide,
                                child: SwipeActions(
                                  // The seam to the next row rides on the
                                  // swipe plane's padding, so it collapses
                                  // together with the row on delete.
                                  padding: EdgeInsets.fromLTRB(
                                    AppTheme.pageInset,
                                    0,
                                    AppTheme.pageInset,
                                    isSeam ? AppTheme.segmentGap : 0,
                                  ),
                                  // The row clip adopts the segment's own
                                  // corners while the plane is revealed.
                                  borderRadius: rowRadius,
                                  onEdit: () => onEdit(item),
                                  onDelete: () => onLongPress(item),
                                  child: ClassSegmentRow(
                                    item: item,
                                    radius: rowRadius,
                                    status: isToday
                                        ? classStatusAt(item, nowMinutes)
                                        : null,
                                    statusEntry: statusFor?.call(item),
                                    isFocus:
                                        focusClassId != null &&
                                        item.id == focusClassId,
                                    onTap: onTap != null
                                        ? () => onTap!(item)
                                        : null,
                                    onLongPress: () => onLongPress(item),
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: math.max(0, entries.length),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One lazy list slot in the day's agenda: either a class row inside its
/// stack, or the break chip between two stacks.
sealed class _AgendaEntry {
  const _AgendaEntry();
}

class _ClassEntry extends _AgendaEntry {
  const _ClassEntry(this.stack, this.rowIndex);

  final List<ClassItem> stack;
  final int rowIndex;
}

class _BreakEntry extends _AgendaEntry {
  const _BreakEntry(this.minutes);

  /// Minutes between the previous stack's last class and the next stack's
  /// first class.
  final int minutes;
}

/// Fades and slides the whole day content when the selected day changes.
///
/// Enter-only, like the tab switch in main_navigation_screen: the new day's
/// content is already in the tree when the 120ms transition starts, so
/// rapid day taps restart a short enter instead of queueing crossfades.
/// [AppTheme.motionDuration] collapses to zero under reduced motion, which
/// makes the swap instant. Uses [SliverFadeTransition] so the class list
/// stays lazy — items built later during scrolling find the animation
/// already settled and do not replay.
class _DaySwitchTransition extends StatefulWidget {
  const _DaySwitchTransition({
    required this.day,
    required this.dayDirection,
    required this.sliverBuilder,
  });

  final int day;

  /// +1 when the day moved later, -1 for earlier; the content slides in
  /// from that side.
  final int dayDirection;

  /// Builds the day's slivers. Receives the shared slide animation so every
  /// card and divider moves as one group — no stagger.
  final Widget Function(Animation<Offset> slide) sliverBuilder;

  @override
  State<_DaySwitchTransition> createState() => _DaySwitchTransitionState();
}

class _DaySwitchTransitionState extends State<_DaySwitchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    // Start settled: the first appearance does not animate, matching
    // AnimatedSwitcher semantics for an initial child.
    _controller.value = 1;
    _fade = CurvedAnimation(parent: _controller, curve: AppTheme.motionEaseOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolved here (not initState) because the duration depends on
    // inherited widgets; also catches the reduce-motion toggle changing.
    _controller.duration = AppTheme.motionDuration(
      context,
      AppTheme.motionFast,
    );
  }

  @override
  void didUpdateWidget(_DaySwitchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.day != oldWidget.day) {
      // Enter-only restart: the content is already the new day.
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: Offset(widget.dayDirection * 0.02, 0),
      end: Offset.zero,
    ).animate(_fade);
    return SliverFadeTransition(
      opacity: _fade,
      sliver: widget.sliverBuilder(slide),
    );
  }
}
