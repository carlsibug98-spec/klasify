import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/class_item.dart';
import '../models/class_status.dart';

/// Keeps the Android launcher widget in sync with the app's local schedule.
class NextClassWidgetService {
  NextClassWidgetService._();

  static const MethodChannel _channel = MethodChannel(
    'klasify/next_class_widget',
  );

  /// [statuses] adds each class's marked dates (finished, not attending, cancelled)
  /// for the next week, so the widget skips those occurrences and counts them as done.
  static Future<void> sync(
    List<ClassItem> classes, {
    ClassStatuses statuses = const {},
    DateTime? now,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final reference = now ?? DateTime.now();

    try {
      await _channel.invokeMethod<void>('updateSchedule', {
        'scheduleJson': jsonEncode([
          for (final item in classes)
            {
              ...item.toMap(),
              'marked_dates': markedDateKeys(
                statuses,
                item.id,
                item.day,
                reference,
              ),
            },
        ]),
      });
    } catch (error, stackTrace) {
      // Widget sync must never block schedule edits or imports.
      debugPrint('Next-class widget sync failed: $error\n$stackTrace');
    }
  }
}
