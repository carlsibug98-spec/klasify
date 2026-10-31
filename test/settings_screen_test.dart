import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klasify/screens/settings_screen.dart';
import 'package:klasify/services/app_info.dart';
import 'package:klasify/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()),
    );
    await tester.pump();
  }

  testWidgets('groups settings by task and shows reminder state', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.pump();

    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('HELP'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);

    expect(find.text('Import schedule'), findsOneWidget);
    expect(find.text('Backup and restore'), findsOneWidget);
    expect(find.text('Class reminders'), findsOneWidget);
    expect(find.text('How Klasify works'), findsOneWidget);
    expect(find.text('Home-screen widget'), findsOneWidget);
    expect(find.text('About Klasify'), findsOneWidget);

    expect(find.text('No alerts scheduled'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('shows On when class reminders are enabled', (tester) async {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': true});
    await pumpSettings(tester);
    await tester.pump();

    expect(find.text('Alerts before each class'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('home-screen widget row explains how to add the widget', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Home-screen widget'));
    await tester.pumpAndSettle();

    expect(find.text('Add it from your home screen'), findsOneWidget);
    expect(
      find.text('Touch and hold an empty spot on your home screen.'),
      findsOneWidget,
    );
    expect(find.text('Choose Widgets, then find Klasify.'), findsOneWidget);
    expect(find.text('Drag “Upcoming” to the spot you want.'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('STARTS IN'), findsOneWidget);
  });

  testWidgets('help section asks the shell to replay the coach tour', (
    tester,
  ) async {
    var replayed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsScreen(onReplayCoachTour: () => replayed = true),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Replay the coach tour'));
    await tester.pump();
    expect(replayed, isTrue);
  });

  testWidgets('privacy note closes the page', (tester) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(
      find.text(AppInfo.tagline),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text(AppInfo.tagline), findsOneWidget);
  });

  testWidgets('keeps a readable settings column on wide screens', (
    tester,
  ) async {
    await pumpSettings(tester, size: const Size(1000, 900));
    await tester.pump();

    final appBar = tester.getRect(find.byType(AppBar));
    expect(appBar.width, 680);
    expect(appBar.left, 160);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow phone without overflowing', (tester) async {
    await pumpSettings(tester, size: const Size(320, 640));
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Home-screen widget'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('segmented rows (approved settings study)', () {
    test('single-row groups are fully rounded standalone cards', () {
      final r = AppTheme.segmentRadiusOf(0, 1);
      expect(r.topLeft, Radius.circular(AppTheme.cardRadius));
      expect(r.topRight, Radius.circular(AppTheme.cardRadius));
      expect(r.bottomLeft, Radius.circular(AppTheme.cardRadius));
      expect(r.bottomRight, Radius.circular(AppTheme.cardRadius));
    });

    test('first row curves the top, softens the meeting edge', () {
      final r = AppTheme.segmentRadiusOf(0, 3);
      expect(r.topLeft, Radius.circular(AppTheme.cardRadius));
      expect(r.topRight, Radius.circular(AppTheme.cardRadius));
      expect(r.bottomLeft, Radius.circular(AppTheme.segmentSoften));
      expect(r.bottomRight, Radius.circular(AppTheme.segmentSoften));
    });

    test('middle rows soften every corner, no dead-straight cuts', () {
      final r = AppTheme.segmentRadiusOf(1, 3);
      expect(r.topLeft, Radius.circular(AppTheme.segmentSoften));
      expect(r.topRight, Radius.circular(AppTheme.segmentSoften));
      expect(r.bottomLeft, Radius.circular(AppTheme.segmentSoften));
      expect(r.bottomRight, Radius.circular(AppTheme.segmentSoften));
    });

    test('last row curves the bottom, softens the meeting edge', () {
      final r = AppTheme.segmentRadiusOf(2, 3);
      expect(r.topLeft, Radius.circular(AppTheme.segmentSoften));
      expect(r.topRight, Radius.circular(AppTheme.segmentSoften));
      expect(r.bottomLeft, Radius.circular(AppTheme.cardRadius));
      expect(r.bottomRight, Radius.circular(AppTheme.cardRadius));
    });

    testWidgets('every row renders inside its own shadowed segment Material', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.pump();

      // Seven rows → seven segments. Each wraps a Material whose shape
      // carries the hairline side; the ambient shadow wraps the Material.
      final segments = find.byWidgetPredicate(
        (w) =>
            w is Material &&
            w.shape is RoundedRectangleBorder &&
            (w.shape as RoundedRectangleBorder).side != BorderSide.none,
      );
      expect(segments, findsNWidgets(7));
    });
  });
}
