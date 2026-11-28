import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/screens/profile/profile_shared.dart';
import 'package:klasify/screens/profile/settings_privacy_screen.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The hub's Notifications pill must describe what is actually scheduled:
/// both reminder kinds on, one on, or none.
void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.light,
        home: const SettingsPrivacyScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  StatusPill pill(WidgetTester tester) =>
      tester.widget<StatusPill>(find.byType(StatusPill));

  testWidgets('both reminder kinds on reads as On', (tester) async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': true,
      'event_reminders_enabled': true,
    });

    await pumpSettings(tester);

    expect(pill(tester).on, isTrue);
    expect(pill(tester).partial, isFalse);
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('only class reminders on reads as Partial', (tester) async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': true,
      'event_reminders_enabled': false,
    });

    await pumpSettings(tester);

    expect(pill(tester).on, isTrue);
    expect(pill(tester).partial, isTrue);
    expect(find.text('Partial'), findsOneWidget);
  });

  testWidgets('class reminders off reads as Off even if events were on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': false,
      'event_reminders_enabled': true,
    });

    await pumpSettings(tester);

    expect(pill(tester).on, isFalse);
    expect(pill(tester).partial, isFalse);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('Settings no longer offers Contact support', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpSettings(tester);

    expect(find.text('Contact support'), findsNothing);
    expect(find.text('Help centre'), findsOneWidget);
  });
}
