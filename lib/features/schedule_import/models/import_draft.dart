class ImportDraft {
  final String subject;
  final String room;
  final String professor;
  final int day;
  final int start;
  final int end;
  final double? ocrConfidence;

  ImportDraft({
    required this.subject,
    required this.room,
    required this.professor,
    required this.day,
    required this.start,
    required this.end,
    this.ocrConfidence,
  });

  ImportDraft copyWith({
    String? subject,
    String? room,
    String? professor,
    int? day,
    int? start,
    int? end,
    double? ocrConfidence,
    bool clearOcrConfidence = false,
  }) => ImportDraft(
    subject: subject ?? this.subject,
    room: room ?? this.room,
    professor: professor ?? this.professor,
    day: day ?? this.day,
    start: start ?? this.start,
    end: end ?? this.end,
    ocrConfidence: clearOcrConfidence
        ? null
        : ocrConfidence ?? this.ocrConfidence,
  );
}

/// What kind of problem a row has. The review card styles conflicts and
/// invalid rows differently, so this is stored instead of inferred from text.
enum ImportNoteKind { invalid, conflict }

/// A problem shown on an import row: its message and what kind it is.
class ImportNote {
  const ImportNote(this.text, this.kind);

  final String text;
  final ImportNoteKind kind;
}
