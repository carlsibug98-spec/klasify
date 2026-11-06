import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/compose_colors.dart';

/// Bottom-sheet date picker for the event sheet: the same compose-mode
/// shell as [showEditClassTimePickerSheet] — grabber, Cancel on the left,
/// the pick in the center (month first, then the full selected date), Done
/// on the right — with a month calendar grid instead of wheels. Selecting
/// a day only arms Done; closing without Done keeps the old date.
Future<DateTime?> showEventDatePickerSheet({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (context) => EventDatePickerSheet(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Sunday-first weekday initials, matching a wall calendar.
const _weekdayInitials = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// One month of leading blanks + day numbers, Sunday-first.
List<int?> _monthCells(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  return [
    for (var i = 0; i < first.weekday % 7; i++) null,
    for (var d = 1; d <= daysInMonth; d++) d,
  ];
}

class EventDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const EventDatePickerSheet({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<EventDatePickerSheet> createState() => _EventDatePickerSheetState();
}

class _EventDatePickerSheetState extends State<EventDatePickerSheet> {
  late DateTime _selected;
  late int _pageYear;
  late int _pageMonth;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _pageYear = _selected.year;
    _pageMonth = _selected.month;
  }

  DateTime get _pageFirst => DateTime(_pageYear, _pageMonth, 1);

  void _movePage(int delta) {
    final next = DateTime(_pageYear, _pageMonth + delta, 1);
    setState(() {
      _pageYear = next.year;
      _pageMonth = next.month;
    });
    HapticFeedback.selectionClick();
  }

  bool get _canGoBack => _pageFirst.isAfter(DateTime(
        widget.firstDate.year,
        widget.firstDate.month,
        1,
      )); // the page before still has pickable days
  bool get _canGoForward => _pageFirst.isBefore(DateTime(
        widget.lastDate.year,
        widget.lastDate.month,
        1,
      ));

  String get _previewText {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final selectedKey = DateTime(_selected.year, _selected.month, _selected.day);
    final diff = selectedKey.difference(todayKey).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    if (diff > 1 && diff < 7) return weekdays[_selected.weekday - 1];
    return '${_monthNames[_selected.month - 1]} ${_selected.day}, '
        '${_selected.year}';
  }

  void _onDone() {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final p = ComposeColors.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final scheme = Theme.of(context).colorScheme;
    final cells = _monthCells(_pageFirst);
    // Pad to whole weeks so the grid rows line up.
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: p.grabber,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header row: Cancel, Month + preview, Done — the time picker's
          // exact arrangement.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const Key('date_picker_cancel_button'),
                  onPressed: () => Navigator.of(context).pop(null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: p.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Event date',
                      key: const Key('date_picker_title'),
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _previewText,
                      key: const Key('date_picker_preview'),
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 15,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const Key('date_picker_done_button'),
                  onPressed: _onDone,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Month pager: the calendar cards slide one month at a time.
          Row(
            children: [
              IconButton(
                key: const Key('date_picker_prev_month'),
                onPressed: _canGoBack ? _moveBack : null,
                icon: Icon(
                  Icons.chevron_left_rounded,
                  size: 26,
                  color: _canGoBack ? p.muted : p.grabber,
                ),
              ),
              Expanded(
                child: Text(
                  '${_monthNames[_pageMonth - 1]} $_pageYear'.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              IconButton(
                key: const Key('date_picker_next_month'),
                onPressed: _canGoForward ? _moveForward : null,
                icon: Icon(
                  Icons.chevron_right_rounded,
                  size: 26,
                  color: _canGoForward ? p.muted : p.grabber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // No fixed height: months need 4, 5, or 6 day rows, so the grid
          // reports its own extent and the sheet hugs the calendar instead
          // of stranding empty space under it.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Weekday initials strip.
              Row(
                children: [
                  for (final w in _weekdayInitials)
                    Expanded(
                      child: Center(
                        child: Text(
                          w,
                          style: TextStyle(
                            color: p.hint,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              _Grid(
                cells: cells,
                selected: _selected,
                page: _pageFirst,
                first: widget.firstDate,
                last: widget.lastDate,
                accent: p,
                scheme: scheme,
                onPick: (day) {
                  setState(() => _selected = day);
                  HapticFeedback.selectionClick();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _moveBack() => _movePage(-1);
  void _moveForward() => _movePage(1);
}

/// The six-week day grid. Days outside the pickable window are inert;
/// days of other months fade; the selected day wears the accent disc.
class _Grid extends StatelessWidget {
  final List<int?> cells;
  final DateTime selected;
  final DateTime page;
  final DateTime first;
  final DateTime last;
  final ComposePalette accent;
  final ColorScheme scheme;
  final ValueChanged<DateTime> onPick;

  const _Grid({
    required this.cells,
    required this.selected,
    required this.page,
    required this.first,
    required this.last,
    required this.accent,
    required this.scheme,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: const Key('date_picker_grid'),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        // A day cell runs the full table width in 7 columns, so this keeps
        // each row ~44 tall regardless of the sheet's pixel width — tall
        // enough for the 36px day disc, compact enough that the whole
        // calendar sits tight above the sheet's bottom edge.
        childAspectRatio: 1.15,
      ),
      itemCount: cells.length,
      itemBuilder: (context, index) {
        final day = cells[index];
        if (day == null) return const SizedBox();
        final date = DateTime(page.year, page.month, day);
        final inRange = !date.isBefore(DateTime(
              first.year,
              first.month,
              first.day,
            )) &&
            !date.isAfter(DateTime(last.year, last.month, last.day));
        final isSelected = date == selected;
        final isToday = date == _todayKey();

        final labelColor = !inRange
            ? accent.grabber
            : accent.muted;

        return Center(
          child: GestureDetector(
            key: Key('date_picker_day_${date.toIso8601String().substring(0, 10)}'),
            onTap: inRange ? () => onPick(date) : null,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? scheme.primary : null,
                border: isToday && !isSelected
                    ? Border.all(color: scheme.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isSelected ? scheme.onPrimary : labelColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static DateTime _todayKey() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
