import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/office_status.dart';

void main() {
  test('maps a server row into the display model', () {
    final office = OfficeStatus.fromMap({
      'office_name': 'guidance',
      'status': 'break',
      'custom_message': ' Back at 2pm ',
      'updated_at': '2026-11-09T08:30:00.000Z',
    });

    expect(office.displayName, 'Guidance');
    expect(office.statusLabel, 'On break');
    expect(office.message, 'Back at 2pm');
    expect(office.updatedAt, DateTime.utc(2026, 11, 9, 8, 30));
    expect(office.isOnBreak, isTrue);
    expect(office.semanticLabel, 'Guidance: On break — Back at 2pm');
  });

  test('defaults keep the strip renderable when fields are missing', () {
    final office = OfficeStatus.fromMap({'office_name': 'clinic'});

    expect(office.status, 'open');
    expect(office.statusLabel, 'Open');
    expect(office.message, isNull);
    expect(office.updatedAt, isNull);
    expect(office.semanticLabel, 'Clinic: Open');
  });

  test('unknown office keys still capitalize into a readable name', () {
    final office = OfficeStatus.fromMap({
      'office_name': 'student_affairs',
      'status': 'closed',
    });

    expect(office.displayName, 'Student affairs');
    expect(office.statusLabel, 'Closed');
    expect(office.isClosed, isTrue);
  });
}
