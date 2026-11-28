import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/screens/profile/profile_shared.dart';
import 'package:klasify/theme/app_theme.dart';

void main() {
  testWidgets('the conflict notice names the count and can be dismissed', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SyncConflictNotice(
            count: 2,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(
      find.textContaining('2 older server changes were skipped'),
      findsOneWidget,
    );
    expect(find.text('Dismiss'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(dismissed, isTrue);
  });

  test('one conflict reads as singular', () {
    expect(
      syncConflictMessage(1),
      contains('1 older server change was skipped'),
    );
  });
}
