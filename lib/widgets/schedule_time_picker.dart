import 'package:flutter/material.dart';

/// Native schedule time picker shared by class entry and import review.
Future<TimeOfDay?> showScheduleTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  required String helpText,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  initialEntryMode: TimePickerEntryMode.dial,
  helpText: helpText,
);
