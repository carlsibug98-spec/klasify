import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/office_name_sheet.dart';

void main() {
  final savedNames = <String>[];
  var throwOnSave = false;

  Widget host({List<String> taken = const [], String initial = ''}) =>
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showOfficeNameSheet(
                  context,
                  title: 'Add office',
                  ctaLabel: 'Add office',
                  initialName: initial,
                  takenNames: taken,
                  onSave: (name) async {
                    savedNames.add(name);
                    if (throwOnSave) {
                      // A real server call takes time; the delay keeps the
                      // mid-save "Saving…" state observable in the test.
                      await Future<void>.delayed(
                        const Duration(milliseconds: 60),
                      );
                      throw Exception('server down');
                    }
                  },
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  setUp(() {
    savedNames.clear();
    throwOnSave = false;
  });

  testWidgets('empty name disables the CTA', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final cta = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add office'),
    );
    expect(cta.onPressed, isNull);
  });

  testWidgets('a name differing only in case is rejected inline', (tester) async {
    await tester.pumpWidget(host(taken: const ['Library']));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'library');
    await tester.pumpAndSettle();

    expect(find.text('An office with this name already exists.'), findsOneWidget);
    final cta = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add office'),
    );
    expect(cta.onPressed, isNull);
  });

  testWidgets('leading/trailing spaces do not bypass the duplicate check',
      (tester) async {
    await tester.pumpWidget(host(taken: const ['Library']));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Library  ');
    await tester.pumpAndSettle();

    expect(find.text('An office with this name already exists.'), findsOneWidget);
    final cta = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add office'),
    );
    expect(cta.onPressed, isNull);
  });

  testWidgets('a valid name calls onSave with the trimmed name and pops true',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Health Services  ');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add office'));
    await tester.pumpAndSettle();

    expect(savedNames, ['Health Services']);
  });

  testWidgets('a server failure keeps the sheet open with an error toast',
      (tester) async {
    throwOnSave = true;
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Library');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add office'));
    await tester.pump(); // spinner frame
    // mid-save CTA reads "Saving…"
    expect(find.text('Saving…'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't save the office. Nothing changed. Try again."),
      findsOneWidget,
    );
    // sheet still open
    expect(find.text('Add office'), findsWidgets);
  });
}
