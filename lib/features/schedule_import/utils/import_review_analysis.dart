import '../../../data/validation/class_rules.dart';
import '../../../models/class_item.dart';
import '../models/import_draft.dart';
import '../models/import_mode.dart';
import 'timetable_parser.dart';

/// Converts one reviewed draft into the row that will be saved.
///
/// Blank or too-short professor names become [unspecifiedProfessor]; the
/// editor relies on the same conversion when it opens a draft.
ClassItem classItemFromDraft(ImportDraft draft) => ClassItem(
  subject: draft.subject.trim(),
  room: draft.room.trim(),
  professor: draft.professor.trim().length < 2
      ? unspecifiedProfessor
      : draft.professor.trim(),
  day: draft.day,
  startMinutes: draft.start,
  endMinutes: draft.end,
);

/// True when the room still needs a human to confirm it.
bool isUnknownRoom(String room) {
  final normalized = room.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'unknown room' ||
      normalized == 'room to confirm';
}

/// True when OCR was unsure about this row or the subject text looks merged.
bool needsOcrReview(ImportDraft draft) =>
    (draft.ocrConfidence != null && draft.ocrConfidence! < .75) ||
    TimetableParser.looksLikeOcrTextIssue(draft.subject);

/// The short badge shown on a row that needs OCR review, or null.
String? ocrReviewLabel(ImportDraft draft) {
  final confidence = draft.ocrConfidence;
  if (confidence != null && confidence < .75) {
    return 'Low OCR score · ${(confidence * 100).round()}%';
  }
  return TimetableParser.looksLikeOcrTextIssue(draft.subject)
      ? 'Check scanned text'
      : null;
}

/// The saved classes that stay after applying [mode].
///
/// `add` keeps everything, `replaceAll` starts from empty, and
/// `replaceSelected` removes only the checked ids.
List<ClassItem> classesThatRemain({
  required List<ClassItem> existing,
  required ImportMode mode,
  required Set<int> selectedIds,
}) {
  switch (mode) {
    case ImportMode.add:
      return existing;
    case ImportMode.replaceAll:
      return const [];
    case ImportMode.replaceSelected:
      return existing.where((item) => !selectedIds.contains(item.id)).toList();
  }
}

/// Returns a short explanation for every draft that cannot be imported yet:
/// invalid details, or an overlap with a saved class / an earlier draft.
Map<ImportDraft, ImportNote> analyzeImportDrafts({
  required List<ImportDraft> drafts,
  required List<ClassItem> existing,
}) {
  final notes = <ImportDraft, ImportNote>{};
  final accepted = <ClassItem>[];
  for (final draft in drafts) {
    final current = classItemFromDraft(draft);
    try {
      validateClass(current);
    } on ArgumentError {
      notes[draft] = const ImportNote(
        'Missing or invalid details',
        ImportNoteKind.invalid,
      );
      continue;
    }
    final overlap = [...existing, ...accepted]
        .where(
          (item) =>
              item.day == current.day &&
              current.startMinutes < item.endMinutes &&
              item.startMinutes < current.endMinutes,
        )
        .toList();
    if (overlap.isNotEmpty) {
      notes[draft] = ImportNote(
        'Overlaps ${overlap.map((item) => item.subject).join(', ')}',
        ImportNoteKind.conflict,
      );
    } else {
      accepted.add(current);
    }
  }
  return notes;
}

/// Everything the review screen needs to know before committing an import.
class ImportReview {
  const ImportReview({
    required this.notes,
    required this.imports,
    required this.roomsToConfirm,
    required this.namesToReview,
    required this.selectedCount,
  });

  /// Rows that still block the import, keyed by draft.
  final Map<ImportDraft, ImportNote> notes;

  /// Drafts converted to savable rows.
  final List<ClassItem> imports;

  /// Drafts whose room still needs confirmation.
  final int roomsToConfirm;

  /// Drafts whose OCR score or subject text still needs review.
  final int namesToReview;

  /// Saved classes that the current replace-selected mode will remove.
  final int selectedCount;

  bool get hasNotes => notes.isNotEmpty;
}

/// Builds a review for [drafts] against the current saved schedule.
///
/// Conflict checks run only against classes that will remain after the chosen
/// mode is applied, so replacing a class clears its overlap.
ImportReview reviewImport({
  required List<ImportDraft> drafts,
  required List<ClassItem> existing,
  required ImportMode mode,
  required Set<int> selectedIds,
}) {
  final remaining = classesThatRemain(
    existing: existing,
    mode: mode,
    selectedIds: selectedIds,
  );
  return ImportReview(
    notes: analyzeImportDrafts(drafts: drafts, existing: remaining),
    imports: drafts.map(classItemFromDraft).toList(),
    roomsToConfirm: drafts.where((draft) => isUnknownRoom(draft.room)).length,
    namesToReview: drafts.where(needsOcrReview).length,
    selectedCount: existing
        .where((item) => selectedIds.contains(item.id))
        .length,
  );
}
