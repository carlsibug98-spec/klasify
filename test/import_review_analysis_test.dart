import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/models/import_draft.dart';
import 'package:klasify/features/schedule_import/models/import_mode.dart';
import 'package:klasify/features/schedule_import/services/import_save_service.dart';
import 'package:klasify/features/schedule_import/utils/import_review_analysis.dart';
import 'package:klasify/models/class_item.dart';

ClassItem _saved({
  int? id,
  String subject = 'Math',
  int day = 1,
  int start = 480,
  int end = 540,
}) => ClassItem(
  id: id,
  subject: subject,
  room: 'Room 101',
  professor: 'Prof. Cruz',
  day: day,
  startMinutes: start,
  endMinutes: end,
);

ImportDraft _draft({
  String subject = 'Science',
  String room = 'Room 102',
  String professor = 'Prof. Reyes',
  int day = 1,
  int start = 600,
  int end = 660,
  double? ocrConfidence,
}) => ImportDraft(
  subject: subject,
  room: room,
  professor: professor,
  day: day,
  start: start,
  end: end,
  ocrConfidence: ocrConfidence,
);

void main() {
  group('classItemFromDraft', () {
    test('trims fields and supplies the unspecified professor sentinel', () {
      final item = classItemFromDraft(
        _draft(subject: ' Science ', room: ' Room 102 ', professor: '  '),
      );

      expect(item.subject, 'Science');
      expect(item.room, 'Room 102');
      expect(item.professor, unspecifiedProfessor);
    });
  });

  group('isUnknownRoom', () {
    test('recognises the placeholder room values', () {
      expect(isUnknownRoom(''), isTrue);
      expect(isUnknownRoom(' unknown room '), isTrue);
      expect(isUnknownRoom('Room to confirm'), isTrue);
      expect(isUnknownRoom('Room 101'), isFalse);
    });
  });

  group('needsOcrReview', () {
    test('flags low confidence and merged subject text only', () {
      expect(needsOcrReview(_draft(ocrConfidence: .74)), isTrue);
      expect(needsOcrReview(_draft(ocrConfidence: .75)), isFalse);
      expect(needsOcrReview(_draft(subject: 'AlgebraAlgebra')), isTrue);
      expect(needsOcrReview(_draft(subject: 'Algebra')), isFalse);
    });

    test('reports the reason for the badge', () {
      expect(ocrReviewLabel(_draft(ocrConfidence: .62)), 'Low OCR score · 62%');
      expect(
        ocrReviewLabel(_draft(subject: 'AlgebraAlgebra')),
        'Check scanned text',
      );
      expect(ocrReviewLabel(_draft()), isNull);
    });
  });

  group('analyzeImportDrafts', () {
    test('marks invalid details without rejecting valid rows', () {
      final invalid = _draft(subject: 'A');
      final valid = _draft(subject: 'Science');

      final notes = analyzeImportDrafts(
        drafts: [invalid, valid],
        existing: const [],
      );

      expect(notes[invalid]?.kind, ImportNoteKind.invalid);
      expect(notes[invalid]?.text, 'Missing or invalid details');
      expect(notes.containsKey(valid), isFalse);
    });

    test('reports overlap with a saved class and with an earlier draft', () {
      final againstExisting = _draft(start: 510, end: 570);
      final first = _draft(subject: 'Science', start: 600, end: 660);
      final second = _draft(subject: 'English', start: 630, end: 690);

      final notes = analyzeImportDrafts(
        drafts: [againstExisting, first, second],
        existing: [_saved()],
      );

      expect(notes[againstExisting]?.kind, ImportNoteKind.conflict);
      expect(notes[againstExisting]?.text, 'Overlaps Math');
      expect(notes.containsKey(first), isFalse);
      expect(notes[second]?.text, 'Overlaps Science');
    });
  });

  group('classesThatRemain', () {
    test('keeps, clears, or removes only selected saved classes', () {
      final first = _saved(id: 1, subject: 'Math');
      final second = _saved(id: 2, subject: 'Science');

      expect(
        classesThatRemain(
          existing: [first, second],
          mode: ImportMode.add,
          selectedIds: {2},
        ),
        [first, second],
      );
      expect(
        classesThatRemain(
          existing: [first, second],
          mode: ImportMode.replaceAll,
          selectedIds: const {},
        ),
        isEmpty,
      );
      expect(
        classesThatRemain(
          existing: [first, second],
          mode: ImportMode.replaceSelected,
          selectedIds: {2},
        ),
        [first],
      );
    });
  });

  group('reviewImport', () {
    test('a replace mode clears the conflict it removes', () {
      final saved = _saved(id: 7, start: 480, end: 540);
      final draft = _draft(start: 510, end: 570);

      final adding = reviewImport(
        drafts: [draft],
        existing: [saved],
        mode: ImportMode.add,
        selectedIds: const {},
      );
      expect(adding.hasNotes, isTrue);
      expect(adding.imports, hasLength(1));

      final replacingAll = reviewImport(
        drafts: [draft],
        existing: [saved],
        mode: ImportMode.replaceAll,
        selectedIds: const {},
      );
      expect(replacingAll.hasNotes, isFalse);

      final replacingSelected = reviewImport(
        drafts: [draft],
        existing: [saved],
        mode: ImportMode.replaceSelected,
        selectedIds: {7},
      );
      expect(replacingSelected.hasNotes, isFalse);
      expect(replacingSelected.selectedCount, 1);
    });

    test('counts rooms and OCR names that still need review', () {
      final review = reviewImport(
        drafts: [
          _draft(room: 'Room to confirm'),
          _draft(subject: 'AlgebraAlgebra', start: 700, end: 760),
        ],
        existing: const [],
        mode: ImportMode.add,
        selectedIds: const {},
      );

      expect(review.roomsToConfirm, 1);
      expect(review.namesToReview, 1);
    });
  });

  group('ImportSaveService.successMessage', () {
    test('keeps the singular and plural copy stable', () {
      expect(
        ImportSaveService.successMessage(ImportMode.add, 1),
        'Imported 1 class successfully.',
      );
      expect(
        ImportSaveService.successMessage(ImportMode.add, 2),
        'Imported 2 classes successfully.',
      );
      expect(
        ImportSaveService.successMessage(ImportMode.replaceAll, 2),
        'Replaced the schedule with 2 classes.',
      );
      expect(
        ImportSaveService.successMessage(ImportMode.replaceSelected, 1),
        'Replaced selected classes with 1 imported class.',
      );
    });
  });
}
