import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/office_status.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/office_status_strip.dart';

OfficeStatus _office(
  String name, {
  String status = 'open',
  String? note,
}) => OfficeStatus.fromMap({
  'office_name': name,
  'status': status,
  'custom_message': note,
  'updated_at': '2026-11-10T08:30:00.000Z',
});

Widget _host(
  List<OfficeStatus> offices, {
  bool isAdmin = false,
  Set<String> pending = const {},
}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: OfficeStatusStrip(
      offices: offices,
      isAdmin: isAdmin,
      pendingOffices: pending,
      onEditOffice: isAdmin ? (_) {} : null,
    ),
  ),
);

void main() {
  testWidgets('students see no edit affordance on the tiles', (tester) async {
    await tester.pumpWidget(_host([_office('guidance'), _office('clinic')]));

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('admins get one edit chip per office', (tester) async {
    await tester.pumpWidget(
      _host([_office('guidance'), _office('clinic'), _office('registrar')], isAdmin: true),
    );

    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(3));
    expect(find.byType(InkWell), findsNWidgets(3));
  });

  testWidgets('a pending office shows Syncing… instead of its note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        _office('guidance', note: 'Back at 2pm'),
        _office('clinic', status: 'break', note: 'Lunch'),
      ], pending: {'clinic'}),
    );

    expect(find.text('Syncing…'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
    // The non-pending office keeps its note.
    expect(find.text('Back at 2pm'), findsOneWidget);
  });

  testWidgets('more than three offices add a swipe hint', (tester) async {
    await tester.pumpWidget(
      _host([
        _office('guidance'),
        _office('clinic'),
        _office('registrar'),
        _office('library'),
        _office('health_services'),
      ]),
    );

    expect(find.textContaining('Swipe sideways'), findsOneWidget);
  });

  testWidgets('three offices show no hint for students', (tester) async {
    await tester.pumpWidget(
      _host([_office('guidance'), _office('clinic'), _office('registrar')]),
    );

    expect(find.textContaining('Swipe sideways'), findsNothing);
    expect(find.textContaining('Tap an office'), findsNothing);
  });

  testWidgets('admin hint tells the admin what tapping does', (tester) async {
    await tester.pumpWidget(
      _host([_office('guidance'), _office('clinic'), _office('registrar')], isAdmin: true),
    );

    expect(find.textContaining('Tap an office to change it.'), findsOneWidget);
  });
}
