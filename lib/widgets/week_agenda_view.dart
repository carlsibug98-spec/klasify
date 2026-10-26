import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../models/class_item.dart';
import '../models/class_status.dart';
import '../theme/app_theme.dart';
import 'campus_break_divider.dart';
import 'class_card.dart';
import 'empty_state_card.dart';
import 'selected_day_header.dart';
import 'swipe_actions.dart';
import 'weekday_tile.dart';

/// Single-day agenda view showing the 1-row week strip, sticky day header,
/// and time-ordered class cards with campus break indicators.
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppTheme.pageContentMaxWidth,
        ),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Responsive 1-row week strip
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
                          ),
                      ];

                      // If width allows, distribute evenly across the row
                      if (constraints.maxWidth >= dayNames.length * 44) {
                        return Row(
                          children: [
                            for (final tile in weekdayTiles)
                              Expanded(child: tile),
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
                            for (final tile in weekdayTiles)
                              SizedBox(width: 48, child: tile),
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

            // Class List or Empty States. Switching days plays a short
            // directional fade+slide instead of teleporting: the content
            // swaps immediately, then a 120ms enter-only transition runs,
            // matching the tab-switch motion. The list stays lazy (builder
            // delegate) and cards scrolled into view later do not re-animate.
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
                              ? EmptyStateCard(
                                  icon: Icons.calendar_month_outlined,
                                  title: 'Build your week',
                                  message:
                                      'Add your first class now, or bring in a timetable to review before saving.',
                                  actions: [
                                    FilledButton.icon(
                                      onPressed: () =>
                                          onAddClassForDay(selectedDay),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Add a class'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          Navigator.of(
                                            context,
                                            rootNavigator: true,
                                          ).pushNamed<void>(
                                            AppRoutes.importSchedule,
                                          ),
                                      icon: const Icon(
                                        Icons.upload_file_outlined,
                                      ),
                                      label: const Text('Import a timetable'),
                                    ),
                                  ],
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
                            // Items alternate between class cards and break dividers
                            if (index.isOdd) {
                              final prevIndex = index ~/ 2;
                              final prevClass = selectedClasses[prevIndex];
                              final nextClass = selectedClasses[prevIndex + 1];
                              final gapMinutes =
                                  nextClass.startMinutes - prevClass.endMinutes;

                              if (gapMinutes >= 15) {
                                return SlideTransition(
                                  position: slide,
                                  child: CampusBreakDivider(
                                    breakMinutes: gapMinutes,
                                  ),
                                );
                              }
                              // Consecutive classes: ClassCard already includes standard 10px bottom gap.
                              return const SizedBox.shrink();
                            }

                            final classIndex = index ~/ 2;
                            final item = selectedClasses[classIndex];
                            return SlideTransition(
                              position: slide,
                              child: SwipeActions(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTheme.pageInset,
                                  0,
                                  AppTheme.pageInset,
                                  10,
                                ),
                                onEdit: () => onEdit(item),
                                onDelete: () => onLongPress(item),
                                child: ClassCard(
                                  item: item,
                                  insetHorizontally: false,
                                  trailingGap: false,
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
                                  onEdit: () => onEdit(item),
                                  onDelete: () => onLongPress(item),
                                  onLongPress: () => onLongPress(item),
                                ),
                              ),
                            );
                          },
                          // Count includes class cards plus dividers between them
                          childCount: math.max(
                            0,
                            selectedClasses.length * 2 - 1,
                          ),
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
