import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klasify/screens/profile/profile_screen.dart';
import 'package:klasify/services/app_info.dart';
import 'package:klasify/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppInfo', () {
    test('stays in sync with pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(
        match,
        isNotNull,
        reason: 'pubspec.yaml must declare version: x.y.z+build',
      );
      expect(
        AppInfo.version,
        '${match!.group(1)}.${match.group(2)}.${match.group(3)}',
        reason: 'AppInfo.version drifted from pubspec.yaml — update both.',
      );
      expect(
        AppInfo.build,
        int.parse(match.group(4)!),
        reason: 'AppInfo.build drifted from pubspec.yaml — update both.',
      );
      expect(
        AppInfo.versionLabel,
        'Version ${AppInfo.version} (build ${AppInfo.build})',
      );
    });
  });

  testWidgets('Profile has a version line that opens the about sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
    );
    await tester.pump();

    // The version line sits at the bottom of the page.
    expect(
      find.text('Klasify ${AppInfo.version} (build ${AppInfo.build})'),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.text('Klasify ${AppInfo.version} (build ${AppInfo.build})'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Klasify ${AppInfo.version} (build ${AppInfo.build})'),
    );
    await tester.pumpAndSettle();

    // The sheet states the app's identity and its defining fact.
    expect(find.text('Klasify'), findsOneWidget);
    expect(find.text(AppInfo.versionLabel), findsOneWidget);
    expect(find.text(AppInfo.tagline), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });
}
