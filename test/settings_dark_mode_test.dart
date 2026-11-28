import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/screens/profile/profile_shared.dart';
import 'package:klasify/screens/profile/settings_privacy_screen.dart';
import 'package:klasify/services/theme_mode_service.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guard for the hub switch: it must show the theme the user is
/// actually looking at, including "system" while the phone is dark.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeModeService.instance.setMode(KlasifyThemeMode.system);
  });

  Widget appUnderTest() => ListenableBuilder(
    listenable: ThemeModeService.instance,
    builder: (context, _) {
      final mode = switch (ThemeModeService.instance.mode) {
        KlasifyThemeMode.light => ThemeMode.light,
        KlasifyThemeMode.dark => ThemeMode.dark,
        KlasifyThemeMode.system => ThemeMode.system,
      };
      return MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const SettingsPrivacyScreen(),
      );
    },
  );

  MiniSwitch switchOf(WidgetTester tester) =>
      tester.widget<MiniSwitch>(find.byType(MiniSwitch));

  testWidgets('system mode on a dark phone reads as on', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(appUnderTest());
    await tester.pumpAndSettle();

    expect(switchOf(tester).value, isTrue);
    expect(find.text('Follows your system'), findsOneWidget);
  });

  testWidgets('system mode on a light phone reads as off', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(appUnderTest());
    await tester.pumpAndSettle();

    expect(switchOf(tester).value, isFalse);
    expect(find.text('Follows your system'), findsOneWidget);
  });

  testWidgets('toggling pins an explicit mode and updates the subtitle', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(appUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniSwitch));
    await tester.pumpAndSettle();

    expect(ThemeModeService.instance.mode, KlasifyThemeMode.dark);
    expect(switchOf(tester).value, isTrue);
    expect(find.text('Always on'), findsOneWidget);

    await tester.tap(find.byType(MiniSwitch));
    await tester.pumpAndSettle();

    expect(ThemeModeService.instance.mode, KlasifyThemeMode.light);
    expect(switchOf(tester).value, isFalse);
    expect(find.text('Always off'), findsOneWidget);
  });

  testWidgets('an explicit mode can return to following the system', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(appUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MiniSwitch));
    await tester.pumpAndSettle();
    expect(ThemeModeService.instance.mode, KlasifyThemeMode.dark);
    expect(find.text('Use system setting'), findsOneWidget);

    await tester.tap(find.text('Use system setting'));
    await tester.pumpAndSettle();

    expect(ThemeModeService.instance.mode, KlasifyThemeMode.system);
    expect(find.text('Follows your system'), findsOneWidget);
    expect(switchOf(tester).value, isFalse);
    expect(find.text('Use system setting'), findsNothing);
  });
}
