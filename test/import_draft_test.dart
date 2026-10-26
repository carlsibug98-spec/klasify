import 'package:klasify/features/schedule_import/models/import_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editing a draft creates a new value and clears its old OCR score', () {
    final original = ImportDraft(
      subject: 'Mathematics',
      room: '101',
      professor: 'Prof. Cruz',
      day: 1,
      start: 480,
      end: 540,
      ocrConfidence: .62,
    );

    final edited = original.copyWith(
      subject: 'Discrete Mathematics',
      clearOcrConfidence: true,
    );

    expect(original.subject, 'Mathematics');
    expect(original.ocrConfidence, .62);
    expect(edited.subject, 'Discrete Mathematics');
    expect(edited.ocrConfidence, isNull);
  });
}
