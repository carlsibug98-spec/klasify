import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/office_status_editor_sheet.dart';

void main() {
  bool? editorResult;
  String? renamedTo;
  var retired = false;

  Widget host({
    List<String> other = const [],
    Future<void> Function(String)? onRename,
    Future<void> Function()? onRetire,
  }) =>
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  editorResult = await showOfficeStatusEditorSheet(
                    context,
                    displayName: 'Guidance',
                    initialStatus: 'open',
                    initialNote: null,
                    onSave: (status, note) async {},
                    otherOfficeNames: other,
                    onRename: onRename,
                    onRetire: onRetire,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  setUp(() {
    editorResult = null;
    renamedTo = null;
    retired = false;
  });

  testWidgets('without manage callbacks there is no manage section',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('MANAGE OFFICE'), findsNothing);
    expect(find.text('Rename office'), findsNothing);
    expect(find.text('Retire office'), findsNothing);
  });

  testWidgets('super admin sees the manage section with both rows',
      (tester) async {
    await tester.pumpWidget(
      host(onRename: (_) async {}, onRetire: () async {}),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('MANAGE OFFICE'), findsOneWidget);
    expect(find.text('Rename office'), findsOneWidget);
    expect(find.text('Retire office'), findsOneWidget);
  });

  testWidgets('rename opens the name sheet prefilled and calls onRename',
      (tester) async {
    await tester.pumpWidget(
      host(onRename: (name) async => renamedTo = name),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename office'));
    await tester.pumpAndSettle();

    // The name sheet is open on top of the editor, prefilled with the
    // current display name.
    expect(find.widgetWithText(FilledButton, 'Rename'), findsOneWidget);
    final nameField = tester.widget<TextField>(find.byType(TextField).last);
    expect(nameField.controller!.text, 'Guidance');
    await tester.enterText(find.byType(TextField).last, 'Learning Commons');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(renamedTo, 'Learning Commons');
    expect(editorResult, isTrue);
  });

  testWidgets('retire shows the confirm dialog and confirm calls onRetire',
      (tester) async {
    await tester.pumpWidget(host(onRetire: () async => retired = true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retire office'));
    await tester.pumpAndSettle();

    expect(find.text('Retire Guidance?'), findsOneWidget);
    expect(
      find.text('Students will no longer see it on Today. Its record stays on file.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Retire'));
    await tester.pumpAndSettle();

    expect(retired, isTrue);
    expect(editorResult, isTrue);
  });

  testWidgets('retire cancel leaves the editor open', (tester) async {
    await tester.pumpWidget(host(onRetire: () async => retired = true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retire office'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    expect(retired, isFalse);
    expect(find.text('Update availability'), findsOneWidget);
  });
}
