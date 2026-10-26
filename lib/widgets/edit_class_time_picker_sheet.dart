import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TimePickerResult {
  final int minutes;
  final int? adjustedEndMinutes;

  const TimePickerResult({required this.minutes, this.adjustedEndMinutes});
}

Future<TimePickerResult?> showEditClassTimePickerSheet({
  required BuildContext context,
  required String title,
  required int initialMinutes,
  required bool isStart,
  int? currentStartMinutes,
  int? currentEndMinutes,
  int? previousDuration,
}) {
  return showModalBottomSheet<TimePickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (context) => EditClassTimePickerSheet(
      title: title,
      initialMinutes: initialMinutes,
      isStart: isStart,
      currentStartMinutes: currentStartMinutes,
      currentEndMinutes: currentEndMinutes,
      previousDuration: previousDuration,
    ),
  );
}

class EditClassTimePickerSheet extends StatefulWidget {
  final String title;
  final int initialMinutes;
  final bool isStart;
  final int? currentStartMinutes;
  final int? currentEndMinutes;
  final int? previousDuration;

  const EditClassTimePickerSheet({
    super.key,
    required this.title,
    required this.initialMinutes,
    required this.isStart,
    this.currentStartMinutes,
    this.currentEndMinutes,
    this.previousDuration,
  });

  @override
  State<EditClassTimePickerSheet> createState() =>
      _EditClassTimePickerSheetState();
}

class _EditClassTimePickerSheetState extends State<EditClassTimePickerSheet> {
  late int _selectedHour; // 1 - 12
  late int _selectedMinute; // 0 - 59
  late String _selectedPeriod; // 'AM' or 'PM'

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  String? _sheetError;

  @override
  void initState() {
    super.initState();
    final h24 = (widget.initialMinutes ~/ 60) % 24;
    _selectedMinute = widget.initialMinutes % 60;
    _selectedPeriod = h24 >= 12 ? 'PM' : 'AM';
    _selectedHour = (h24 % 12 == 0) ? 12 : (h24 % 12);

    _hourController = FixedExtentScrollController(
      initialItem: _selectedHour - 1,
    );
    _minuteController = FixedExtentScrollController(
      initialItem: _selectedMinute,
    );
    _periodController = FixedExtentScrollController(
      initialItem: _selectedPeriod == 'PM' ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  int get _calculatedMinutes {
    final h24 = (_selectedHour % 12) + (_selectedPeriod == 'PM' ? 12 : 0);
    return h24 * 60 + _selectedMinute;
  }

  String get _previewText {
    final mStr = _selectedMinute.toString().padLeft(2, '0');
    return '$_selectedHour:$mStr $_selectedPeriod';
  }

  void _onDone() {
    HapticFeedback.selectionClick();
    final chosen = _calculatedMinutes;

    if (widget.isStart) {
      int? adjustedEnd;
      if (widget.currentEndMinutes != null &&
          chosen >= widget.currentEndMinutes!) {
        final duration =
            widget.previousDuration ??
            (widget.currentEndMinutes! - widget.initialMinutes);
        final validDuration = duration > 0 ? duration : 60;
        adjustedEnd = (chosen + validDuration).clamp(0, 1439);
      }
      Navigator.of(
        context,
      ).pop(TimePickerResult(minutes: chosen, adjustedEndMinutes: adjustedEnd));
    } else {
      if (widget.currentStartMinutes != null &&
          chosen <= widget.currentStartMinutes!) {
        setState(() {
          _sheetError = 'End must be after the start time.';
        });
        return;
      }
      Navigator.of(context).pop(TimePickerResult(minutes: chosen));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grabber
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header row: Cancel, Title + Preview, Done
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const Key('time_picker_cancel_button'),
                  onPressed: () => Navigator.of(context).pop(null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Color(0xFFA3A3A3),
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
                      widget.title,
                      key: const Key('time_picker_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _previewText,
                      key: const Key('time_picker_preview'),
                      style: const TextStyle(
                        color: Color(0xFFA3A3A3),
                        fontSize: 15,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const Key('time_picker_done_button'),
                  onPressed: _onDone,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Color(0xFF85B7EB),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_sheetError != null) ...[
            const SizedBox(height: 8),
            Text(
              _sheetError!,
              key: const Key('time_picker_error_text'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFF28B82),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Wheels
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Highlight band behind the selected row
                Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                // Wheels with edge fade mask
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black,
                        Colors.black,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.22, 0.78, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: Row(
                    children: [
                      // Hour wheel (1 to 12)
                      Expanded(
                        child: CupertinoPicker(
                          key: const Key('time_picker_hour_wheel'),
                          itemExtent: 44,
                          scrollController: _hourController,
                          selectionOverlay: null,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedHour = index + 1;
                              _sheetError = null;
                            });
                          },
                          children: List.generate(12, (i) {
                            final h = i + 1;
                            final isSelected = h == _selectedHour;
                            return Center(
                              child: Text(
                                '$h',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF707070),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // Minute wheel (0 to 59)
                      Expanded(
                        child: CupertinoPicker(
                          key: const Key('time_picker_minute_wheel'),
                          itemExtent: 44,
                          scrollController: _minuteController,
                          selectionOverlay: null,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedMinute = index;
                              _sheetError = null;
                            });
                          },
                          children: List.generate(60, (i) {
                            final isSelected = i == _selectedMinute;
                            return Center(
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF707070),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // AM/PM wheel
                      Expanded(
                        child: CupertinoPicker(
                          key: const Key('time_picker_period_wheel'),
                          itemExtent: 44,
                          scrollController: _periodController,
                          selectionOverlay: null,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedPeriod = index == 1 ? 'PM' : 'AM';
                              _sheetError = null;
                            });
                          },
                          children: ['AM', 'PM'].map((p) {
                            final isSelected = p == _selectedPeriod;
                            return Center(
                              child: Text(
                                p,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF707070),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
