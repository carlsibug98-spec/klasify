/// One office's last-known availability, cached locally so the strip on
/// Today still renders offline. Values mirror the server's office_statuses
/// rows: guidance / clinic / registrar with open / closed / break.
class OfficeStatus {
  const OfficeStatus({
    required this.office,
    required this.status,
    this.message,
    this.updatedAt,
  });

  /// Server key: 'guidance', 'clinic', 'registrar'.
  final String office;

  /// 'open' | 'closed' | 'break'.
  final String status;

  /// Optional note from the admin ("Back at 2pm").
  final String? message;

  /// When the office last changed its status (UTC from the server).
  final DateTime? updatedAt;

  factory OfficeStatus.fromMap(Map<String, Object?> m) => OfficeStatus(
    office: m['office_name'] as String? ?? '',
    status: m['status'] as String? ?? 'open',
    message: (m['custom_message'] as String?)?.trim(),
    updatedAt: m['updated_at'] != null
        ? DateTime.tryParse(m['updated_at'] as String)
        : null,
  );

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isOnBreak => status == 'break';

  /// "Guidance", "Clinic", "Registrar"; unknown keys still read nicely.
  String get displayName {
    if (office.isEmpty) return 'Office';
    final spaced = office.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// "Open" / "On break" / "Closed".
  String get statusLabel => switch (status) {
    'open' => 'Open',
    'break' => 'On break',
    'closed' => 'Closed',
    _ => 'Open',
  };

  /// "Guidance: On break — Back at 2pm" for the semantics label.
  String get semanticLabel {
    final note = (message == null || message!.isEmpty) ? '' : ' — $message';
    return '$displayName: $statusLabel$note';
  }
}
