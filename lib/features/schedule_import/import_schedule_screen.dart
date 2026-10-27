import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database_helper.dart';
import '../../models/class_item.dart';
import '../../routes/app_routes.dart';
import '../../screens/main_navigation_screen.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_notification.dart';
import '../../widgets/swipe_actions.dart';
import 'models/import_draft.dart';
import 'services/schedule_ocr_service.dart';
import 'utils/parse_chain.dart';
import 'utils/sectioned_schedule_parser.dart';
import 'utils/timetable_parser.dart';
import 'widgets/import_review_widgets.dart';
import 'widgets/import_source_preview_screen.dart';

/// The reason the import review raised its warnings.
enum _ReviewIssue { review, noClasses }

/// Offline timetable import: OCR is performed on-device. OCR cannot reliably
/// infer every school-specific table layout, so every row is reviewed first.
class ImportScheduleScreen extends StatefulWidget {
  const ImportScheduleScreen({
    super.key,
    this.initialFilePath,
    this.ocrService,
  });

  /// A file selected by the dashboard shortcut. When absent, this screen
  /// opens normally and waits for the user to choose a file or scan.
  final String? initialFilePath;

  /// Optional OCR service for testing.
  final ScheduleOcrService? ocrService;

  @override
  State<ImportScheduleScreen> createState() => _ImportScheduleScreenState();
}

class _ImportScheduleScreenState extends State<ImportScheduleScreen> {
  static const String _vlUrlKey = 'paddle_ocr_vl_url';

  final _db = DatabaseHelper.instance;
  late final ScheduleOcrService _ocrService =
      widget.ocrService ?? ScheduleOcrService();
  final TextEditingController _vlUrlController = TextEditingController();
  bool _working = false;
  bool _openManualAfterCancel = false;
  bool _cancelScanRequested = false;
  bool _disposeOcrAfterScan = false;
  String? _selectedFilePath;
  ImportScanStage _scanStage = ImportScanStage.idle;
  double _scanProgress = 0;
  String _scanDetail = '';
  String? _completedImportMessage;
  List<ImportDraft> _drafts = [];
  List<String> _warnings = [];

  /// Why `_warnings` were raised. Chooses the review heading without
  /// searching the warning text for phrases.
  _ReviewIssue _issue = _ReviewIssue.review;
  int _existingRefreshVersion = 0;

  /// Saved classes, cached so row badges can be recomputed instantly while editing.
  List<ClassItem> _existing = [];
  _ImportMode _importMode = _ImportMode.add;
  final Set<int> _selectedReplacementIds = {};

  /// Draft -> short explanation for rows with conflicts / invalid details.
  Map<ImportDraft, ImportNote> _notes = {};
  bool _allowRoutePop = false;

  @override
  void dispose() {
    _vlUrlController.dispose();
    _db.removeListener(_onScheduleChanged);
    if (_working) {
      _cancelScanRequested = true;
      _disposeOcrAfterScan = true;
    } else {
      unawaited(_ocrService.dispose());
    }
    super.dispose();
  }

  /// Back button and system back gesture. Returns to the screen that opened
  /// the import. A running scan asks to stop first, and unsaved classes ask
  /// to be discarded first.
  Future<void> _handleBack() async {
    if (_working) {
      if (!_cancelScanRequested) {
        final confirmed = await _requestScanCancellation();
        if (!confirmed || !mounted) return;
      }
    } else if (_drafts.isNotEmpty) {
      final discard = await _confirmDiscardDrafts();
      if (!discard || !mounted) return;
    }
    await _leaveScreen();
  }

  Future<bool> _confirmDiscardDrafts() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard import?'),
        content: const Text('The classes you reviewed will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep reviewing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _leaveScreen() async {
    setState(() => _allowRoutePop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _cancelReview() async {
    if (_working) return;
    await _leaveScreen();
  }

  @override
  void initState() {
    super.initState();
    _db.addListener(_onScheduleChanged);
    _loadVlServerUrl();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.initialFilePath != null) {
        _chooseFile(widget.initialFilePath);
      }
    });
  }

  Future<void> _loadVlServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString(_vlUrlKey) ?? '';
      if (!mounted) return;
      setState(() {
        _vlUrlController.text = url;
      });
    } catch (error) {
      debugPrint('Could not read the scan-server setting: $error');
    }
  }

  Future<void> _saveVlServerUrl() async {
    final url = _vlUrlController.text.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_vlUrlKey, url);
    } catch (error) {
      debugPrint('Could not save the scan-server setting: $error');
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          url.isEmpty
              ? 'High-accuracy server cleared. Scans stay on this device.'
              : 'Server saved. Image scans will try it first, then fall back to on-device OCR.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _onScheduleChanged() {
    if (!mounted || _working || _drafts.isEmpty) return;
    unawaited(_refreshExistingClasses());
  }

  Future<void> _refreshExistingClasses() async {
    final version = ++_existingRefreshVersion;
    try {
      final existing = await _db.getAll();
      if (!mounted || _working || version != _existingRefreshVersion) return;
      setState(() {
        _syncExistingClasses(existing);
        _refreshAnalysis();
      });
    } catch (error) {
      debugPrint('Could not refresh saved classes for import review: $error');
    }
  }

  Future<void> _openSourcePreview() async {
    final path = _selectedFilePath;
    if (path == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ImportSourcePreviewScreen(path: path),
      ),
    );
  }

  void _reportScanProgress(
    double progress,
    String detail, {
    ImportScanStage? stage,
  }) {
    if (!mounted) return;
    setState(() {
      if (stage != null) {
        _scanStage = stage;
      }
      _scanProgress = progress.clamp(_scanProgress, 1.0).toDouble();
      _scanDetail = _cancelScanRequested
          ? 'Stopping after the current OCR step…'
          : detail;
    });
  }

  Future<bool> _requestScanCancellation() async {
    if (!_working || _cancelScanRequested) return false;
    final confirmed = await showCancelScanConfirmation(context);
    if (!confirmed || !mounted || !_working || _cancelScanRequested) {
      return false;
    }
    setState(() {
      _cancelScanRequested = true;
      _scanDetail = 'Stopping after the current OCR step…';
    });
    _ocrService.cancel();
    final view = View.maybeOf(context);
    if (view != null) {
      SemanticsService.sendAnnouncement(
        view,
        'Cancelling scan. Stopping after the current step. No classes will be added.',
        TextDirection.ltr,
      );
    }
    return true;
  }

  void _finishCancelledScan() {
    if (!mounted) {
      if (_disposeOcrAfterScan) unawaited(_ocrService.dispose());
      return;
    }
    final openManual = _openManualAfterCancel;
    _openManualAfterCancel = false;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    setState(() {
      _working = false;
      _cancelScanRequested = false;
      _scanStage = ImportScanStage.idle;
      _scanProgress = 0;
      _scanDetail = '';
    });
    if (!openManual) {
      // Use the shared notification widget so the toast follows the app
      // theme instead of a hardcoded white slab that glares in dark mode.
      if (messenger != null) {
        showAppNotificationOnMessenger(
          messenger,
          Theme.of(context).colorScheme,
          'Scan cancelled. No classes were added.',
          kind: AppNotificationKind.info,
        );
      }
      final finishView = View.maybeOf(context);
      if (finishView != null) {
        SemanticsService.sendAnnouncement(
          finishView,
          'Scan cancelled. No classes were added.',
          TextDirection.ltr,
        );
      }
    }
    if (openManual) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addManualClass();
      });
    }
  }

  Future<void> _chooseFile([String? selectedPath]) async {
    try {
      var path = selectedPath;
      if (path == null) {
        final picked = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'jpe', 'webp', 'pdf'],
        );
        final pickedPath = picked?.path;
        if (pickedPath == null) return;
        if (!mounted) return;
        path = pickedPath;
      }
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 20 * 1024 * 1024) {
        _showError(
          'Choose a file smaller than 20 MB for reliable on-device processing.',
        );
        return;
      }
      if (!mounted) return;
      final ext = p.extension(path).toLowerCase();
      if (!['.png', '.jpg', '.jpeg', '.jpe', '.webp', '.pdf'].contains(ext)) {
        _showError('Choose a PNG, JPG, WEBP, or PDF file.');
        return;
      }
      _ocrService.resetCancel();
      // The optional high-accuracy pass uses the server URL saved in the
      // import screen; empty keeps every scan fully offline.
      _ocrService.vlBaseUrl = _vlUrlController.text.trim();
      setState(() {
        _working = true;
        _cancelScanRequested = false;
        _selectedFilePath = path;
        _scanStage = ImportScanStage.preparing;
        _scanProgress = .03;
        _scanDetail = 'Opening the selected file';
        _drafts = [];
        _notes = {};
        _warnings = [];
        _completedImportMessage = null;
      });
      if (ext != '.pdf') {
        _reportScanProgress(
          .08,
          'Checking the timetable layout',
          stage: ImportScanStage.detectingGrid,
        );
      } else {
        _reportScanProgress(
          .1,
          'Preparing PDF pages',
          stage: ImportScanStage.preparing,
        );
      }
      final pdfScan = ext == '.pdf'
          ? await _ocrService.scanPdf(
              path,
              onProgress: (progress, detail) => _reportScanProgress(
                progress,
                detail,
                stage: ImportScanStage.readingPdf,
              ),
              isCancelled: () => _cancelScanRequested,
            )
          : null;
      final gridRows = ext == '.pdf'
          ? pdfScan!.gridRows
          : await _ocrService.scanGridImage(
              path,
              onProgress: (progress, detail) =>
                  _reportScanProgress(progress, detail),
              isCancelled: () => _cancelScanRequested,
            );
      if (_cancelScanRequested) {
        _finishCancelledScan();
        return;
      }
      if (ext != '.pdf') {
        _reportScanProgress(
          .43,
          'Trying text recognition',
          stage: ImportScanStage.readingText,
        );
      }
      final text = ext == '.pdf'
          ? pdfScan!.text
          : await _ocrService.scanImage(
              path,
              onProgress: (progress, detail) =>
                  _reportScanProgress(progress, detail),
              isCancelled: () => _cancelScanRequested,
            );
      if (_cancelScanRequested) {
        _finishCancelledScan();
        return;
      }
      _reportScanProgress(
        .88,
        'Matching recognized text to class times',
        stage: ImportScanStage.assembling,
      );
      // A weekly grid has spatial meaning that a flattened OCR string cannot
      // preserve. If spatial extraction fails, do not silently fall
      // back to guessed AM times / mismatched weekdays; ask the user to retry
      // or enter classes manually instead of presenting misleading imports.
      final hasWeekdayHeaders =
          RegExp(
            r'\b(?:MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|FRI(?:DAY)?)\b',
            caseSensitive: false,
          ).allMatches(text).length >=
          2;
      ImportDraft toDraft(ParsedTimetableRow row) => ImportDraft(
        subject: row.subject,
        room: row.room,
        professor: row.professor,
        day: row.day,
        start: row.startMinutes,
        end: row.endMinutes,
        ocrConfidence: row.ocrConfidence,
      );
      ImportDraft fromSectioned(SectionedRow row) => ImportDraft(
        subject: row.subject,
        room: row.room,
        professor: row.professor,
        day: row.day,
        start: row.startMinutes,
        end: row.endMinutes,
        ocrConfidence: row.ocrConfidence,
      );
      List<ImportDraft> parsed;
      if (ext == '.pdf' || gridRows.isNotEmpty) {
        parsed = gridRows.map(toDraft).toList();
      } else {
        // Parser chain, most layout-aware first. The shared ParseChain runs
        // prepareScheduleLines then the sectioned parser, which reads weekday
        // header bands (slot grids, faculty rows, period rows), day sections,
        // exam records, calendar dates, day-less blocks and single-time lines;
        // rows built on an assumption carry a 0.74 confidence so the review
        // screen flags them for inspection. The list parser stays as the
        // conservative second attempt and is deliberately NOT given the
        // reshaping step.
        final chain = ParseChain.parse(text);
        final sectionedRows = chain.sectioned;
        if (sectionedRows.isNotEmpty) {
          parsed = sectionedRows.map(fromSectioned).toList();
        } else if (hasWeekdayHeaders) {
          // The text looks like a flattened weekly grid. Try the line-oriented
          // list parser first (one class per line); only when it finds nothing
          // fall back to the strict no-guess path so free-text lists are never
          // wrongly rejected as grids.
          final listRows = TimetableParser.parse(text);
          parsed = listRows.isNotEmpty
              ? listRows.map(toDraft).toList()
              : <ImportDraft>[];
        } else {
          parsed = chain.list.map(toDraft).toList();
        }
      }
      final scanWarnings = <String>[
        if (pdfScan != null && pdfScan.pagesSkipped > 0)
          'Only the first ${pdfScan.scannedPages} of ${pdfScan.totalPages} PDF pages were scanned. Inspect the remaining pages before importing.',
        if (pdfScan != null && pdfScan.gridRows.isNotEmpty)
          'PDF scanning can miss individual classes even when some rows were found. Open the original and compare the full timetable before importing.',
        if (pdfScan != null)
          for (final page in pdfScan.pagesNeedingReview)
            'PDF page $page could not be mapped reliably. Open the source, add missed classes, then acknowledge this warning to continue.',
      ];
      var existing = <ClassItem>[];
      try {
        existing = await _db.getAll();
      } catch (e) {
        debugPrint('Could not preload saved classes: $e');
      }
      if (_cancelScanRequested) {
        _finishCancelledScan();
        return;
      }
      if (!mounted) return;
      setState(() {
        _existing = existing;
        _drafts = parsed;
        _importMode = _ImportMode.add;
        _selectedReplacementIds.clear();
        _notes = _analyze(existing);
        _working = false;
        _scanStage = ImportScanStage.idle;
        _scanProgress = 0;
        _scanDetail = '';
        _issue = parsed.isEmpty ? _ReviewIssue.noClasses : _ReviewIssue.review;
        _warnings = [
          ...scanWarnings,
          if (parsed.isEmpty)
            if (text.trim().isEmpty)
              'No readable text was found. Try a sharper photo with the full timetable in frame, or add classes manually.'
            else if (hasWeekdayHeaders)
              'This looks like a weekly grid, but its cells could not be mapped reliably. No guessed classes were added. Try a higher-resolution image or add classes manually.'
            else
              'The timetable layout may not match the automatic parser. No classes were saved.',
        ];
      });
    } catch (e, st) {
      if (_cancelScanRequested) {
        _finishCancelledScan();
        return;
      }
      debugPrint('Schedule import failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _working = false;
        _scanStage = ImportScanStage.failed;
        _scanProgress = 0;
        _scanDetail = '';
      });
      _showError('Could not read this file. Try a clearer image or PDF.');
    }
  }

  Future<bool> _edit(ImportDraft draft) async {
    if (_working) return false;
    final result = await Navigator.of(context, rootNavigator: true)
        .pushNamed<Object?>(
          AppRoutes.importDraftEditor,
          arguments: _toItem(draft),
        );
    if (!mounted || result is! ClassItem) return false;
    setState(() {
      final index = _drafts.indexOf(draft);
      if (index < 0) return;
      _drafts[index] = draft.copyWith(
        subject: result.subject,
        room: result.room,
        professor: result.professor,
        day: result.day,
        start: result.startMinutes,
        end: result.endMinutes,
        clearOcrConfidence: true,
      );
      _refreshAnalysis();
    });
    return true;
  }

  Future<void> _addManualClass() async {
    if (_working) return;
    final result = await Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed<Object?>(AppRoutes.classForm, arguments: true);
    if (!mounted || result is! ClassItem) return;
    final item = result;
    setState(() {
      _drafts.add(
        ImportDraft(
          subject: item.subject,
          room: item.room,
          professor: item.professor,
          day: item.day,
          start: item.startMinutes,
          end: item.endMinutes,
        ),
      );
      _refreshAnalysis();
      _warnings = [];
    });
    showAppNotification(
      context,
      'Manual class added to this import review. It has not been saved yet.',
    );
  }

  void _enterManualClasses() {
    if (_working) {
      _openManualAfterCancel = true;
      _requestScanCancellation();
      return;
    }
    unawaited(_addManualClass());
  }

  ClassItem _toItem(ImportDraft d) => ClassItem(
    subject: d.subject.trim(),
    room: d.room.trim(),
    professor: d.professor.trim().length < 2
        ? unspecifiedProfessor
        : d.professor.trim(),
    day: d.day,
    startMinutes: d.start,
    endMinutes: d.end,
  );

  static bool _isUnknownRoom(String room) {
    final r = room.trim().toLowerCase();
    return r.isEmpty || r == 'unknown room' || r == 'room to confirm';
  }

  static bool _needsOcrReview(ImportDraft draft) =>
      (draft.ocrConfidence != null && draft.ocrConfidence! < .75) ||
      TimetableParser.looksLikeOcrTextIssue(draft.subject);

  static String? _ocrReviewLabel(ImportDraft draft) {
    final confidence = draft.ocrConfidence;
    if (confidence != null && confidence < .75) {
      return 'Low OCR score · ${(confidence * 100).round()}%';
    }
    return TimetableParser.looksLikeOcrTextIssue(draft.subject)
        ? 'Check scanned text'
        : null;
  }

  /// Returns a short explanation for every draft that cannot be imported yet:
  /// invalid details, or an overlap with a saved class / an earlier draft.
  Map<ImportDraft, ImportNote> _analyze(List<ClassItem> existing) {
    final notes = <ImportDraft, ImportNote>{};
    final accepted = <ClassItem>[];
    for (final d in _drafts) {
      final current = _toItem(d);
      try {
        DatabaseHelper.validateClass(current);
      } on ArgumentError {
        notes[d] = const ImportNote(
          'Missing or invalid details',
          ImportNoteKind.invalid,
        );
        continue;
      }
      final overlap = [...existing, ...accepted]
          .where(
            (c) =>
                c.day == current.day &&
                current.startMinutes < c.endMinutes &&
                c.startMinutes < current.endMinutes,
          )
          .toList();
      if (overlap.isNotEmpty) {
        notes[d] = ImportNote(
          'Overlaps ${overlap.map((c) => c.subject).join(', ')}',
          ImportNoteKind.conflict,
        );
      } else {
        accepted.add(current);
      }
    }
    return notes;
  }

  List<ClassItem> _classesThatRemain(List<ClassItem> existing) {
    switch (_importMode) {
      case _ImportMode.add:
        return existing;
      case _ImportMode.replaceAll:
        return const [];
      case _ImportMode.replaceSelected:
        return existing
            .where((item) => !_selectedReplacementIds.contains(item.id))
            .toList();
    }
  }

  void _refreshAnalysis() {
    _notes = _analyze(_classesThatRemain(_existing));
  }

  void _syncExistingClasses(List<ClassItem> existing) {
    _existing = existing;
    if (existing.isEmpty) {
      _importMode = _ImportMode.add;
      _selectedReplacementIds.clear();
      return;
    }

    final existingIds = existing
        .map((item) => item.id)
        .whereType<int>()
        .toSet();
    _selectedReplacementIds.removeWhere((id) => !existingIds.contains(id));
  }

  void _setImportMode(_ImportMode mode) {
    setState(() {
      _importMode = mode;
      _refreshAnalysis();
    });
  }

  void _toggleReplacement(ClassItem item, bool selected) {
    final id = item.id;
    if (id == null) return;
    setState(() {
      if (selected) {
        _selectedReplacementIds.add(id);
      } else {
        _selectedReplacementIds.remove(id);
      }
      _refreshAnalysis();
    });
  }

  /// Removes the draft at [index]. Reports whether the removal happened, so
  /// the swipe row can restore itself when the screen was busy.
  bool _deleteDraft(int index) {
    if (_working || index < 0 || index >= _drafts.length) return false;
    final deleted = _drafts.removeAt(index);
    setState(() {
      _refreshAnalysis();
    });

    showAppNotification(
      context,
      'Removed "${deleted.subject}" from this import review.',
      kind: AppNotificationKind.success,
    );
    return true;
  }

  Future<void> _save() async {
    if (_drafts.isEmpty || _working) return;
    if (_importMode == _ImportMode.replaceSelected &&
        _selectedReplacementIds.isEmpty) {
      _showError(
        'Select at least one saved class to replace, or choose Add to schedule.',
      );
      return;
    }
    setState(() => _working = true);
    try {
      final roomsToConfirm = _drafts
          .where((draft) => _isUnknownRoom(draft.room))
          .length;
      final namesToReview = _drafts.where(_needsOcrReview).length;
      if (roomsToConfirm > 0 || namesToReview > 0) {
        final confirmed = await _confirmFlaggedImport(
          roomsToConfirm,
          namesToReview,
        );
        if (!mounted) return;
        if (!confirmed) {
          setState(() => _working = false);
          return;
        }
      }
      // Re-read saved classes immediately before validating to reduce the chance
      // of importing against stale schedule data.
      final existing = await _db.getAll();
      final notes = _analyze(_classesThatRemain(existing));
      if (notes.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _working = false;
          _syncExistingClasses(existing);
          _notes = notes;
          _warnings = [];
        });
        _showError('Resolve schedule conflicts before importing.');
        return;
      }
      final imports = _drafts.map(_toItem).toList();
      final int count;
      if (_importMode == _ImportMode.replaceAll) {
        final confirmed = await _confirmReplacement(
          existing.length,
          imports.length,
        );
        if (!confirmed) {
          if (mounted) {
            setState(() => _working = false);
          }
          return;
        }
        count = await _db.replaceAll(imports);
      } else if (_importMode == _ImportMode.replaceSelected) {
        final selectedCount = existing
            .where((item) => _selectedReplacementIds.contains(item.id))
            .length;
        final confirmed = await _confirmReplacement(
          selectedCount,
          imports.length,
        );
        if (!confirmed) {
          if (mounted) {
            setState(() => _working = false);
          }
          return;
        }
        count = await _db.replaceSelected(
          _selectedReplacementIds.toList(),
          imports,
        );
      } else {
        count = await _db.insertMany(imports);
      }
      var remindersUpdated = true;
      var remindersEnabled = false;
      try {
        // Keep background reminders in sync with this import. The scheduler
        // is local-only and safely does nothing when reminders are disabled.
        remindersEnabled = await ReminderService.instance.isEnabled;
        await ReminderService.instance.sync();
      } catch (e, st) {
        remindersUpdated = false;
        debugPrint('Imported classes, but reminder sync failed: $e\n$st');
      }
      if (!mounted) return;
      final classLabel = count == 1 ? 'class' : 'classes';
      final successStatus = switch (_importMode) {
        _ImportMode.add => 'Imported $count $classLabel successfully.',
        _ImportMode.replaceAll =>
          'Replaced the schedule with $count $classLabel.',
        _ImportMode.replaceSelected =>
          'Replaced selected classes with $count imported $classLabel.',
      };
      setState(() {
        _working = false;
        _completedImportMessage = successStatus;
        _drafts = [];
        _notes = {};
        _selectedFilePath = null;
        _existing = [];
        _selectedReplacementIds.clear();
        _importMode = _ImportMode.add;
        _warnings = [];
      });
      showAppNotification(
        context,
        successStatus,
        kind: AppNotificationKind.success,
        duration: const Duration(seconds: 5),
      );
      // Reminder problems get their own notification instead of being appended
      // to the success message, so each one has its own kind and timing.
      if (!remindersUpdated) {
        showAppNotification(
          context,
          'Classes saved, but reminders could not be updated. Check notification permission.',
          kind: AppNotificationKind.warning,
        );
      } else if (!remindersEnabled) {
        showAppNotification(
          context,
          'Turn on class reminders in Settings to get notifications when the app is closed.',
          kind: AppNotificationKind.info,
        );
      }
    } catch (e, st) {
      debugPrint('Bulk schedule save failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _working = false;
      });
      _showError('Import failed. No classes were saved. Please try again.');
    }
  }

  Future<bool> _confirmFlaggedImport(
    int roomsToConfirm,
    int namesToReview,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.fact_check_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          title: const Text('Some details still need review'),
          content: Text(
            '${_drafts.length} ${_drafts.length == 1 ? 'class has' : 'classes have'} flagged details: $roomsToConfirm ${roomsToConfirm == 1 ? 'room' : 'rooms'} to confirm and $namesToReview ${namesToReview == 1 ? 'name' : 'names'} to check. Continuing saves them as shown.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Review classes'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Import anyway'),
            ),
          ],
        ),
      ) ==
      true;

  Future<bool> _confirmReplacement(int removeCount, int importCount) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Replace saved classes?'),
            content: Text(
              '$removeCount saved ${removeCount == 1 ? 'class' : 'classes'} will be removed and $importCount imported ${importCount == 1 ? 'class' : 'classes'} will be added. This can’t be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Replace classes'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Shows an error toast. Every caller reports a failure, so the style is
  /// passed as a fact here rather than inferred from the wording.
  void _showError(String text) {
    if (!mounted) return;
    showAppNotification(context, text, kind: AppNotificationKind.error);
  }

  String get _warningTitle {
    if (_warnings.isEmpty) return 'Review needed';
    return switch (_issue) {
      _ReviewIssue.noClasses => 'No classes were recognized',
      _ReviewIssue.review =>
        _drafts.isEmpty
            ? 'No classes were recognized'
            : 'Resolve before importing',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reviewing = _drafts.isNotEmpty;
    final unknownCount = _drafts.where((d) => _isUnknownRoom(d.room)).length;
    final ocrReviewCount = _drafts.where(_needsOcrReview).length;
    final canImport =
        reviewing &&
        !_working &&
        _warnings.isEmpty &&
        _notes.isEmpty &&
        (_importMode != _ImportMode.replaceSelected ||
            (_existing.isNotEmpty && _selectedReplacementIds.isNotEmpty));
    final importStatus = _working
        ? 'Checking and saving your schedule…'
        : _warnings.isNotEmpty
        ? 'Review and acknowledge the scan warnings above to continue.'
        : _notes.isNotEmpty
        ? 'Fix ${_notes.length} flagged ${_notes.length == 1 ? 'class' : 'classes'} above to continue.'
        : _importMode == _ImportMode.replaceSelected &&
              _selectedReplacementIds.isEmpty
        ? 'Select at least one saved class above to continue.'
        : 'Conflicts are checked again before your schedule is updated.';
    final reviewMessages = [
      if (unknownCount > 0)
        '$unknownCount ${unknownCount == 1 ? 'room needs' : 'rooms need'} confirmation. Use “Room to confirm” when you’ll fill it in later.',
      if (ocrReviewCount > 0)
        '$ocrReviewCount ${ocrReviewCount == 1 ? 'class name may' : 'class names may'} contain merged or repeated text. Check the marked rows.',
      if (_notes.isNotEmpty)
        '${_notes.length} ${_notes.length == 1 ? 'class has' : 'classes have'} an issue. Open the marked rows to review it.',
    ];

    return PopScope<void>(
      canPop: _allowRoutePop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_allowRoutePop) unawaited(_handleBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(reviewing ? 'Review import' : 'Import schedule'),
          actions: [
            if (reviewing && _selectedFilePath != null)
              IconButton(
                tooltip: 'View original timetable',
                onPressed: _openSourcePreview,
                icon: const Icon(Icons.visibility_outlined),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.pageContentMaxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.pageInset,
                      8,
                      AppTheme.pageInset,
                      24,
                    ),
                    children: [
                      if (!reviewing)
                        _completedImportMessage == null
                            ? (_working
                                  ? const SizedBox.shrink()
                                  : _pickerCard(context))
                            : _importSuccessCard(context),
                      if (!reviewing &&
                          !_working &&
                          _completedImportMessage == null)
                        _vlServerCard(context),
                      if (_working && reviewing)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: const LinearProgressIndicator(minHeight: 5),
                          ),
                        ),
                      if (_working && !reviewing)
                        ImportScanProgress(
                          stage: _scanStage,
                          progress: _scanProgress,
                          detail: _scanDetail,
                          filePath: _selectedFilePath,
                          isCancelling: _cancelScanRequested,
                          isPdf:
                              _selectedFilePath != null &&
                              p.extension(_selectedFilePath!).toLowerCase() ==
                                  '.pdf',
                          onCancel: _cancelScanRequested
                              ? null
                              : _requestScanCancellation,
                        ),
                      if (reviewing) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Review your timetable',
                                      style: textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Step 2 of 2',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: scheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_drafts.length} ${_drafts.length == 1 ? 'class' : 'classes'} recognized. Review the details, then import them to your schedule.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (reviewing && reviewMessages.isNotEmpty)
                        ImportAttentionBanner(
                          title: 'A few details need review',
                          message: reviewMessages.join('\n'),
                        ),
                      if (reviewing) _replacementOptions(context),
                      if (_warnings.isNotEmpty)
                        ImportAttentionBanner(
                          title: _warningTitle,
                          message: _warnings.join('\n'),
                          blocking: true,
                          dismissLabel: 'Acknowledge and continue',
                          onDismiss: () => setState(() {
                            _warnings = [];
                          }),
                        ),
                      if (reviewing) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Classes to import',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                '${_drafts.length}',
                                style: textTheme.labelLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        for (var i = 0; i < _drafts.length; i++)
                          // The review rows carry the same swipe plane as the
                          // saved-schedule rows: full-swipe removes the draft
                          // (notification, no undo — pre-save staging), the
                          // plane's Edit opens the draft editor. The trash
                          // icon stays as the discoverable fallback.
                          SwipeActions(
                            key: ValueKey('draft-$i'),
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            onEdit: () => _edit(_drafts[i]),
                            onDelete: () async => _deleteDraft(i),
                            child: ImportDraftCard(
                              draft: _drafts[i],
                              note: _notes[_drafts[i]],
                              unknownRoom: _isUnknownRoom(_drafts[i].room),
                              ocrReviewNeeded: _needsOcrReview(_drafts[i]),
                              ocrReviewLabel: _ocrReviewLabel(_drafts[i]),
                              onTap: () => _edit(_drafts[i]),
                              onDelete: () => _deleteDraft(i),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            onPressed: _working ? null : _addManualClass,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add a missed class'),
                          ),
                        ),
                      ],
                      if (!reviewing && _completedImportMessage == null) ...[
                        const SizedBox(height: AppTheme.itemGap),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'A sharp, well-lit photo with the full timetable in frame gives the best results.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (reviewing)
              DecoratedBox(
                decoration: BoxDecoration(color: scheme.surface),
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppTheme.pageContentMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              importStatus,
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _working
                                            ? null
                                            : _cancelReview,
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(64, 50),
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: AppTheme.itemGap),
                                    Expanded(
                                      flex: 2,
                                      child: FilledButton.icon(
                                        onPressed: canImport ? _save : null,
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(64, 50),
                                        ),
                                        icon: const Icon(
                                          Icons.playlist_add_check_rounded,
                                        ),
                                        label: Text(
                                          'Import ${_drafts.length} '
                                          '${_drafts.length == 1 ? 'class' : 'classes'}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Widget _replacementOptions(BuildContext context) {
    if (_existing.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    Widget option(_ImportMode mode, String title, String subtitle) {
      final selected = _importMode == mode;
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: selected ? scheme.primaryContainer : scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: InkWell(
          onTap: _working ? null : () => _setImportMode(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Radio<_ImportMode>(value: mode),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (mode == _ImportMode.add) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Recommended',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RadioGroup<_ImportMode>(
      groupValue: _importMode,
      onChanged: (value) {
        if (!_working && value != null) _setImportMode(value);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import options',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Choose how these classes should update your saved schedule.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          option(
            _ImportMode.add,
            'Add to schedule',
            'Keep saved classes and add these classes.',
          ),
          option(
            _ImportMode.replaceAll,
            'Replace entire schedule',
            'Remove every saved class and use this import.',
          ),
          if (_importMode == _ImportMode.replaceAll)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All saved classes will be removed after you confirm.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          option(
            _ImportMode.replaceSelected,
            'Choose classes to replace',
            'Select saved classes to remove before importing.',
          ),
          if (_importMode == _ImportMode.replaceSelected) ...[
            const Divider(height: 16),
            for (final item in _existing)
              CheckboxListTile(
                value:
                    item.id != null &&
                    _selectedReplacementIds.contains(item.id),
                onChanged: _working || item.id == null
                    ? null
                    : (value) => _toggleReplacement(item, value ?? false),
                title: Text(
                  item.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${item.dayName} · ${item.timeRange} · ${formatRoom(item.room)}',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            if (_selectedReplacementIds.isEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                ),
                child: Text(
                  'Select at least one saved class, or switch to Add to schedule.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                ),
                child: Text(
                  '${_selectedReplacementIds.length} saved ${_selectedReplacementIds.length == 1 ? 'class' : 'classes'} will be removed after confirmation.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _importSuccessCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.onSecondaryContainer,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Import complete',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _completedImportMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: AppTheme.itemGap,
              runSpacing: AppTheme.itemGap,
              children: [
                FilledButton.icon(
                  // Go back to the app shell and open its Week tab. Pushing
                  // /schedule here would replace this page with a bare
                  // ScheduleScreen that has no bottom navigation.
                  onPressed: () {
                    MainNavigationScreen.tabRequest.value =
                        MainNavigationScreen.weekTab;
                    Navigator.of(context).popUntil(
                      (route) =>
                          route.settings.name == AppRoutes.home ||
                          route.isFirst,
                    );
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: const Text('View schedule'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _completedImportMessage = null;
                  }),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Import another'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      color: scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  ),
                  child: Icon(
                    Icons.table_view_rounded,
                    color: scheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.offline_bolt_outlined,
                        size: 16,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Works offline',
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Bring in your timetable',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a schedule image or PDF, then review every class before saving.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final format in ['PDF', 'JPG', 'PNG', 'WEBP'])
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                    ),
                    child: Text(
                      format,
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(AppTheme.chipRadius),
                  ),
                  child: Text(
                    'Up to 20 MB',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (_selectedFilePath != null) ...[
              const SizedBox(height: 16),
              _selectedFileName(context),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _working
                      ? null
                      : () => _chooseFile(_selectedFilePath),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan timetable'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _selectedFilePath != null
                  ? OutlinedButton.icon(
                      onPressed: _working ? null : () => _chooseFile(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Choose another file'),
                    )
                  : FilledButton.icon(
                      onPressed: _working ? null : () => _chooseFile(),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Choose a timetable'),
                    ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _enterManualClasses,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(
                  _working
                      ? 'Enter manually instead'
                      : 'Enter classes manually',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your timetable stays on your device. No internet connection is needed.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vlServerCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = _vlUrlController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.dns_outlined, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'High-accuracy scan server (optional)',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Scanning already works fully offline with the on-device PaddleOCR engine. '
                'For harder layouts you can point Klasify at a self-hosted '
                'PaddleOCR-VL 1.6 server - free, runs from the PaddleOCR docker '
                'compose guide on a GPU PC. Whenever the server is unavailable, '
                'scans silently fall back to this device.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vlUrlController,
                      enabled: !_working,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: 'http://192.168.1.10:8080',
                        labelText: 'Server URL',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _working ? null : _saveVlServerUrl,
                    child: const Text('Save'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                enabled
                    ? 'Enabled - image scans try the server first, then fall back to on-device OCR.'
                    : 'Off - every scan stays on this device.',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedFileName(BuildContext context) {
    final path = _selectedFilePath!;
    final isPdf = p.extension(path).toLowerCase() == '.pdf';
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppTheme.controlRadius),
            ),
            child: Icon(
              isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected file',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
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

enum _ImportMode { add, replaceAll, replaceSelected }
