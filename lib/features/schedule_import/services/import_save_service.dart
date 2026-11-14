import 'package:flutter/foundation.dart';

import '../../../data/database_helper.dart';
import '../../../models/class_item.dart';
import '../../../services/reminder_service.dart';
import '../models/import_mode.dart';

/// What happened after the reviewed rows were committed.
class ImportSaveResult {
  const ImportSaveResult({
    required this.count,
    required this.remindersUpdated,
    required this.remindersEnabled,
  });

  /// Rows written by the database helper.
  final int count;

  /// False when reminder scheduling threw after the rows were saved.
  final bool remindersUpdated;

  /// Whether class reminders were enabled during this save.
  final bool remindersEnabled;
}

/// Commits a reviewed import and refreshes local reminders.
///
/// The screen owns dialogs and notifications; this service owns the database
/// write and the reminder follow-up, so the save transaction has one home.
class ImportSaveService {
  ImportSaveService({DatabaseHelper? database, ReminderService? reminders})
    : _database = database ?? DatabaseHelper.instance,
      _reminders = reminders ?? ReminderService.instance;

  final DatabaseHelper _database;
  final ReminderService _reminders;

  /// Saves [imports] with the chosen [mode]. Throws when the database write
  /// fails, leaving the review screen to report the failure; a reminder
  /// failure is reported in the result instead.
  Future<ImportSaveResult> save({
    required List<ClassItem> imports,
    required ImportMode mode,
    required Set<int> selectedIds,
  }) async {
    final count = switch (mode) {
      ImportMode.add => await _database.insertMany(imports),
      ImportMode.replaceAll => await _database.replaceAll(imports),
      ImportMode.replaceSelected => await _database.replaceSelected(
        selectedIds.toList(),
        imports,
      ),
    };

    var remindersUpdated = true;
    var remindersEnabled = false;
    try {
      // Keep background reminders in sync with this import. The scheduler
      // is local-only and safely does nothing when reminders are disabled.
      remindersEnabled = await _reminders.isEnabled;
      await _reminders.sync();
    } catch (e, st) {
      remindersUpdated = false;
      debugPrint('Imported classes, but reminder sync failed: $e\n$st');
    }

    return ImportSaveResult(
      count: count,
      remindersUpdated: remindersUpdated,
      remindersEnabled: remindersEnabled,
    );
  }

  /// The success copy for [mode] after [count] rows were written.
  static String successMessage(ImportMode mode, int count) {
    final classLabel = count == 1 ? 'class' : 'classes';
    return switch (mode) {
      ImportMode.add => 'Imported $count $classLabel successfully.',
      ImportMode.replaceAll => 'Replaced the schedule with $count $classLabel.',
      ImportMode.replaceSelected =>
        'Replaced selected classes with $count imported $classLabel.',
    };
  }
}
