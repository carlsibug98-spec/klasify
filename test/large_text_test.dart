import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/schedule_import/models/import_draft.dart';
import 'package:klasify/features/schedule_import/widgets/import_review_widgets.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/day_chips.dart';

/// Renders [child] at a phone-like [width] with system text scaled by [scale].
Widget _scaledHost(
  Widget child, {
  required double width,
  required double scale,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

void main() {
  // The PDF flagged the weekday tiles as the most likely to overflow at 200%
  // text. A Flutter overflow shows up as an exception during the pump.
  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'weekday chips fit at ${width.toInt()}px with ${(scale * 100).toInt()}% text',
        (tester) async {
          await tester.pumpWidget(
            _scaledHost(
              DayChips(selected: 1, onChanged: (_) {}),
              width: width,
              scale: scale,
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Mon'), findsOneWidget);
          expect(find.text('Sun'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('import row shows conflict note text at 200% text', (
    tester,
  ) async {
    final draft = ImportDraft(
      subject: 'Calculus',
      room: '301',
      professor: '',
      day: 1,
      start: 540,
      end: 630,
    );
    await tester.pumpWidget(
      _scaledHost(
        ImportDraftCard(
          draft: draft,
          note: const ImportNote('Overlaps Physics', ImportNoteKind.conflict),
          unknownRoom: false,
          ocrReviewNeeded: false,
          ocrReviewLabel: null,
          onTap: () {},
          onDelete: () {},
        ),
        width: 360,
        scale: 2.0,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Overlaps Physics'), findsOneWidget);
  });
}
