import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/screens/auth/legal_sheets.dart';
import 'package:klasify/screens/auth/login_screen.dart';
import 'package:klasify/screens/auth/signup_screen.dart';

Future<void> _pumpFooter(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: Center(child: AuthLegalFooter())),
    ),
  );
  expect(
    find.textContaining(
      'By continuing you agree to the Terms of Service and Privacy Policy.',
      findRichText: true,
    ),
    findsOneWidget,
  );
}

void main() {
  testWidgets('both auth screens carry the consent footer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.byType(AuthLegalFooter), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    expect(find.byType(AuthLegalFooter), findsOneWidget);
  });

  testWidgets('Terms link opens the terms sheet', (tester) async {
    await _pumpFooter(tester);

    await tester.tapOnText(find.textRange.ofSubstring('Terms'));
    await tester.pumpAndSettle();
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.textContaining('provided as-is'), findsOneWidget);
    expect(find.textContaining('bcrypt'), findsNothing);
  });

  testWidgets('Privacy link opens the privacy sheet', (tester) async {
    await _pumpFooter(tester);

    await tester.tapOnText(find.textRange.ofSubstring('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.textContaining('bcrypt hash'), findsOneWidget);
    expect(find.textContaining('No contacts, location, photos'), findsOneWidget);
  });
}
