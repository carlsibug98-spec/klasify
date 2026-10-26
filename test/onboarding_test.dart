import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klasify/routes/app_routes.dart';
import 'package:klasify/screens/onboarding_screen.dart';
import 'package:klasify/services/onboarding_store.dart';

void main() {
  group('OnboardingStore', () {
    test('is not completed on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await OnboardingStore.isCompleted(), isFalse);
    });

    test('remembers completion', () async {
      SharedPreferences.setMockInitialValues({});
      await OnboardingStore.markCompleted();
      expect(await OnboardingStore.isCompleted(), isTrue);
    });
  });

  group('OnboardingScreen', () {
    // The staggered entrance and page transition are time-based; pump one
    // flushing frame, then a fixed 600 ms past the 220 ms transition and the
    // 480 ms stagger.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    // Three pages: Continue walks cover -> add -> reminders; the last page
    // swaps Continue for the ending CTA.
    Future<void> walkToLastPage(WidgetTester tester) async {
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Continue'));
        await settle(tester);
      }
      expect(find.text('Continue'), findsNothing);
    }

    Widget host({bool replay = true, Map<String, WidgetBuilder>? routes}) {
      // Built via the routes table (not home:) so tests can also register '/',
      // which is where first-run completion navigates.
      return MaterialApp(
        initialRoute: AppRoutes.onboarding,
        routes: {
          AppRoutes.onboarding: (_) => OnboardingScreen(isReplay: replay),
          ...?routes,
        },
      );
    }

    testWidgets('cover shows the brand page first, then walks the tour', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await settle(tester);

      // Cover: headline plus the stacked next-class widget preview.
      expect(find.text('Klasify'), findsOneWidget);
      expect(find.text('Know what’s\nnext.'), findsOneWidget);
      // The v52 hero mockup: status pill, start clock, title and meta line.
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Starts 4:00 PM'), findsOneWidget);
      expect(find.text('Design Class'), findsOneWidget);
      expect(find.text('4:00 PM - 6:00 PM · Room 242-B'), findsOneWidget);
      // The mock cover has no swipe hint; that affordance lives on Home.
      expect(find.text('Swipe to take the tour'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-progress')), findsOneWidget);
      // The Example qualifier lives in the tour pages' kicker row, not here.
      expect(find.text('Example'), findsNothing);

      // Page 1: adding and scanning, with the example class card.
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('Add your timetable'), findsOneWidget);
      expect(find.text('ADD & SCAN'), findsOneWidget);
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('Scan it'), findsOneWidget);
      expect(find.text('Add by hand'), findsOneWidget);
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.text('Check room'), findsOneWidget);
      expect(find.text('Mon · 10:30 AM - 12:00 PM · Room 211'), findsOneWidget);

      // Page 2: reminders and backup, replay mode ends with Done.
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(find.text('Stay on track'), findsOneWidget);
      expect(find.text('REMINDERS'), findsOneWidget);
      expect(find.text('Remind me before class'), findsOneWidget);
      expect(find.text('Weekly, on your class days'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget); // replay mode label
      expect(find.text('Add my first class'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('close exits a replayed onboarding', (tester) async {
      // Pushed from a host screen so Navigator.pop has somewhere to go.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OnboardingScreen(isReplay: true),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.text('Know what’s\nnext.'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await settle(tester);
      expect(find.text('Know where to be, and when.'), findsNothing);
    });

    testWidgets('first run ends by marking completion and opening the form', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        host(
          replay: false,
          routes: {
            AppRoutes.classForm: (_) =>
                const Scaffold(body: Center(child: Text('CLASS FORM'))),
          },
        ),
      );
      await settle(tester);

      // Fresh install starts uncompleted, and the quick exit is Skip.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isNull);
      expect(find.text('Skip'), findsOneWidget);

      await walkToLastPage(tester);
      expect(find.text('Add my first class'), findsOneWidget);

      await tester.tap(find.text('Add my first class'));
      await settle(tester);
      expect(find.text('CLASS FORM'), findsOneWidget);

      final prefsAfter = await SharedPreferences.getInstance();
      expect(prefsAfter.getBool('onboarding_completed'), isTrue);
    });

    testWidgets(
      'explore-first on the last page marks completion and lands home',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          host(
            replay: false,
            routes: {
              AppRoutes.home: (_) =>
                  const Scaffold(body: Center(child: Text('HOME'))),
            },
          ),
        );
        await settle(tester);

        await walkToLastPage(tester);
        // The quiet exit sits under the primary CTA and is replay-only hidden.
        expect(find.text('Explore first'), findsOneWidget);

        await tester.tap(find.text('Explore first'));
        await settle(tester);
        expect(find.text('HOME'), findsOneWidget);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('onboarding_completed'), isTrue);
      },
    );

    testWidgets('replay keeps a single exit path on the last page', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await settle(tester);

      await walkToLastPage(tester);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Explore first'), findsNothing);
    });

    testWidgets('skip on a first run completes onboarding and lands home', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        host(
          replay: false,
          routes: {
            AppRoutes.home: (_) =>
                const Scaffold(body: Center(child: Text('HOME'))),
          },
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Skip'));
      await settle(tester);
      expect(find.text('HOME'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_completed'), isTrue);
    });

    testWidgets('fits a small phone with large text and no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(host());
      await settle(tester);
      expect(tester.takeException(), isNull);

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Continue'));
        await settle(tester);
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('cover keeps the inverted-surface treatment in dark mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          initialRoute: AppRoutes.onboarding,
          routes: {
            AppRoutes.onboarding: (_) => const OnboardingScreen(isReplay: true),
          },
        ),
      );
      await settle(tester);

      final scheme = ThemeData.dark().colorScheme;
      final page = tester.widget<Container>(
        find.byKey(const ValueKey('onboarding-page-0')),
      );
      expect(page.color, scheme.inverseSurface);
    });

    testWidgets('every page announces its step and keeps previews inert', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await settle(tester);

      // Step announcement lives in the progress semantics, not as visible text.
      final progress = find.byKey(const ValueKey('onboarding-progress'));
      expect(progress, findsOneWidget);
      expect(tester.getSemantics(progress).label, 'Step 1 of 3');

      await tester.tap(find.text('Continue'));
      await settle(tester);
      final progress1 = find.byKey(const ValueKey('onboarding-progress'));
      expect(tester.getSemantics(progress1).label, 'Step 2 of 3');

      await tester.tap(find.text('Continue'));
      await settle(tester);
      final progress2 = find.byKey(const ValueKey('onboarding-progress'));
      expect(tester.getSemantics(progress2).label, 'Step 3 of 3');
    });
  });
}
