import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/screens/auth/signup_screen.dart';

void main() {
  testWidgets('signup asks for a department and offers the four choices', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.text('Department'), findsOneWidget);
    expect(find.text('Choose your department'), findsOneWidget);

    final departmentField = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(departmentField);
    await tester.tap(departmentField);
    await tester.pumpAndSettle();

    for (final department in ['IT', 'AIS', 'BA', 'EDUC']) {
      expect(find.text(department), findsOneWidget);
    }

    await tester.tap(find.text('AIS'));
    await tester.pumpAndSettle();

    expect(find.text('AIS'), findsOneWidget);
  });

  testWidgets('create account without a department is blocked', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    await tester.enterText(find.byType(TextField).at(0), 'Juan');
    await tester.enterText(find.byType(TextField).at(1), 'juan@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'password123');

    final createButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pump();

    expect(find.text('Please choose your department.'), findsOneWidget);
  });

  testWidgets('Google signup uses the typed name, not a Google name', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    final googleButton = find.widgetWithText(
      OutlinedButton,
      'Continue with Google',
    );
    await tester.ensureVisible(googleButton);
    await tester.tap(googleButton);
    await tester.pump();

    expect(
      find.text('Enter your name before continuing with Google.'),
      findsOneWidget,
    );
  });
}
