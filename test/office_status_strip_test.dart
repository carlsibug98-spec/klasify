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

  testWidgets('four offices switch the strip to a pager with an edge blur',
      (tester) async {
    await tester.pumpWidget(
      _host([
        _office('guidance'),
        _office('clinic'),
        _office('registrar'),
        _office('library'),
      ]),
    );

    expect(find.byType(BackdropFilter), findsOneWidget); // right edge only, offset 0
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('swiping advances exactly one office and flips the blur',
      (tester) async {
    await tester.pumpWidget(
      _host([
        _office('guidance'),
        _office('clinic'),
        _office('registrar'),
        _office('library'),
        _office('health_services'),
      ]),
    );

    final before = tester.getTopLeft(find.text('Guidance')).dx;
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('office_strip_pager')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(find.text('Guidance')).dx;
    expect(after, lessThan(before - 80)); // advanced about one column
    expect(find.byType(BackdropFilter), findsNWidgets(2)); // mid-strip: both edges

    await tester.drag(
      find.byKey(const Key('office_strip_pager')),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget); // back at the start
  });

  testWidgets('overscroll rubber-bands at the start and snaps back',
      (tester) async {
    await tester.pumpWidget(
      _host([
        _office('guidance'),
        _office('clinic'),
        _office('registrar'),
        _office('library'),
      ]),
    );

    final before = tester.getTopLeft(find.text('Guidance')).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('office_strip_pager'))),
    );
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump();

    final banded = tester.getTopLeft(find.text('Guidance')).dx;
    expect(banded, greaterThan(before)); // pulled right with the finger
    expect(banded, lessThan(before + 400)); // but rubber-banded, not full travel

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Guidance')).dx, before); // snapped back
  });

  testWidgets('an empty office list renders nothing', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.byType(PageView), findsNothing);
    expect(find.text('CAMPUS OFFICES'), findsNothing);
  });

  testWidgets('three offices keep the non-pager row layout', (tester) async {
    await tester.pumpWidget(
      _host([_office('guidance'), _office('clinic'), _office('registrar')]),
    );
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a tap (no drag) still opens the office sheet', (tester) async {
    OfficeStatus? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: OfficeStatusStrip(
            offices: [
              _office('guidance'),
              _office('clinic'),
              _office('registrar'),
              _office('library'),
            ],
            isAdmin: true,
            onEditOffice: (o) => tapped = o,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Guidance'));
    expect(tapped?.office, 'guidance');
  });
}
