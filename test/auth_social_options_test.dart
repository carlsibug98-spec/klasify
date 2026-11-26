import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/screens/auth/login_screen.dart';
import 'package:klasify/screens/auth/signup_screen.dart';

void main() {
  testWidgets('login offers Google but no Apple sign-in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.byIcon(Icons.apple), findsNothing);
  });

  testWidgets('signup offers Google but no Apple sign-in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.byIcon(Icons.apple), findsNothing);
  });
}
