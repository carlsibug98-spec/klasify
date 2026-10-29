import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/coach_tour_overlay.dart';

CoachTargetKeys _keys() => CoachTargetKeys(
  heroKey: GlobalKey(),
  swipeTargetKey: GlobalKey(),
  fabKey: GlobalKey(),
  navKey: GlobalKey(),
  tilesKey: GlobalKey(),
);

/// A stand-in for the home screen: one box per tour anchor. Targets can be
/// omitted to model the states where they really are absent — a class added
/// for another day (no Today card) or the desktop shell (no tab bar).
Widget _harness({
  required CoachTargetKeys keys,
  required VoidCallback onDone,
  ValueChanged<CoachStepSpec>? onStep,
  bool withSwipeCard = true,
  bool withNav = true,
  List<CoachStepSpec>? steps,
  bool withTiles = false,
  double swipeTop = 210,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 24,
            left: 16,
            right: 16,
            child: Container(
              key: keys.heroKey,
              height: 150,
              color: const Color(0xFF1C1C1C),
            ),
          ),
          if (withSwipeCard)
            Positioned(
              top: swipeTop,
              left: 16,
              right: 16,
              child: Container(
                key: keys.swipeTargetKey,
                height: 88,
                color: Colors.white,
              ),
            ),
          Positioned(
            bottom: 96,
            right: 24,
            child: Container(
              key: keys.fabKey,
              width: 56,
              height: 56,
              color: const Color(0xFF1C1C1C),
            ),
          ),
          if (withNav)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                key: keys.navKey,
                height: 80,
                color: Colors.white,
              ),
            ),
          if (withTiles)
            Positioned(
              top: 300,
              left: 16,
              right: 16,
              child: Container(
                key: keys.tilesKey,
                height: 104,
                color: Colors.white,
              ),
            ),
          Positioned.fill(
            child: CoachTourOverlay(
              keys: keys,
              onDone: onDone,
              onTargetActive: onStep,
              steps: steps,
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  test(
    'tour copy matches the hero and the swipe step targets the list card',
    () {
      final steps = CoachTourOverlay.tourSteps;

      expect(steps, hasLength(5));
      expect(steps[0].target, CoachTarget.hero);
      expect(steps[0].body, contains('how long until it starts or ends'));
      expect(steps[0].body, isNot(contains('room and time')));

      // Step 2's demonstration plane lives on the first Today list card, so the
      // spotlight must follow it there; otherwise the tour explains a gesture
      // it never shows. Step 3 uses the same card because tapping it opens the
      // attendance sheet (long-press deletes, so the old copy was wrong).
      expect(steps[1].target, CoachTarget.swipeCard);
      expect(steps[1].demoSwipe, isTrue);
      expect(steps[2].target, CoachTarget.swipeCard);
      expect(steps[2].demoSwipe, isFalse);
      expect(steps[2].body, contains('Tap a class'));
      expect(steps[2].body, isNot(contains('Long-press')));
      expect(steps[3].target, CoachTarget.fab);
      expect(steps[3].demoSwipe, isFalse);
      expect(steps[4].target, CoachTarget.nav);
    },
  );

  testWidgets('walks the five steps and only demos the swipe plane once', (
    tester,
  ) async {
    final reported = <CoachStepSpec>[];
    var done = false;

    await tester.pumpWidget(
      _harness(keys: _keys(), onDone: () => done = true, onStep: reported.add),
    );
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF 5'), findsOneWidget);
    expect(find.text('Your next class'), findsOneWidget);
    expect(reported.last.target, CoachTarget.hero);
    expect(reported.last.demoSwipe, isFalse);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Swipe to manage'), findsOneWidget);
    expect(reported.last.target, CoachTarget.swipeCard);
    expect(reported.last.demoSwipe, isTrue);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Mark attendance'), findsOneWidget);
    expect(
      find.text('Tap a class to mark it as done, skipped, or cancelled.'),
      findsOneWidget,
    );
    // The plane closes again: only the swipe step demonstrates the gesture.
    expect(reported.last.target, CoachTarget.swipeCard);
    expect(reported.last.demoSwipe, isFalse);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Add classes'), findsOneWidget);
    expect(reported.last.target, CoachTarget.fab);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Navigate around'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(done, isFalse);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('skips the card steps when Today has no class card', (
    tester,
  ) async {
    final reported = <CoachStepSpec>[];

    await tester.pumpWidget(
      _harness(
        keys: _keys(),
        onDone: () {},
        onStep: reported.add,
        withSwipeCard: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your next class'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // One tap moves past both card steps instead of parking the tooltip on a
    // target that isn't there.
    expect(find.text('Swipe to manage'), findsNothing);
    expect(find.text('Mark attendance'), findsNothing);
    expect(find.text('Add classes'), findsOneWidget);
    expect(reported.last.target, CoachTarget.fab);
  });

  testWidgets('finishes instead of pointing at a missing tab bar', (
    tester,
  ) async {
    var done = false;

    await tester.pumpWidget(
      _harness(keys: _keys(), onDone: () => done = true, withNav: false),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Add classes'), findsOneWidget);
    expect(done, isFalse);

    // Step 5 has no target on the desktop shell, so the tour ends cleanly.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Navigate around'), findsNothing);
    expect(done, isTrue);
  });

  testWidgets('skip tour ends the walkthrough', (tester) async {
    var done = false;

    await tester.pumpWidget(_harness(keys: _keys(), onDone: () => done = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip tour'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  group('empty-schedule coach (single step)', () {
    /// The "Explore first" flow: no tour yet, nothing to skip out of.
    testWidgets('spotlights the tiles with the kicker and no step counter', (
      tester,
    ) async {
      var done = false;

      await tester.pumpWidget(
        _harness(
          keys: _keys(),
          steps: CoachTourOverlay.firstRunSteps,
          withTiles: true,
          onDone: () => done = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add your first class'), findsOneWidget);
      expect(find.text('START HERE'), findsOneWidget);
      // A one-step coach is not really a step count.
      expect(find.text('STEP 1 / 1'), findsNothing);
      // And it has nothing between steps, so no dots are announced either.
      expect(find.bySemanticsLabel('Step 1 of 1'), findsNothing);
      // The quiet exit rebrands: "Dismiss" for a single tip.
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.text('Skip tour'), findsNothing);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
    });

    testWidgets('Dismiss ends it the same way', (tester) async {
      var done = false;

      await tester.pumpWidget(
        _harness(
          keys: _keys(),
          steps: CoachTourOverlay.firstRunSteps,
          withTiles: true,
          onDone: () => done = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
    });

    testWidgets('tapping outside the tooltip dismisses', (tester) async {
      var done = false;

      await tester.pumpWidget(
        _harness(
          keys: _keys(),
          steps: CoachTourOverlay.firstRunSteps,
          withTiles: true,
          onDone: () => done = true,
        ),
      );
      await tester.pumpAndSettle();

      // The tooltip card runs along the top edge on this short test panel,
      // so tap open space instead: right of the card, beside the spotlight.
      await tester.tapAt(const Offset(600, 300));
      await tester.pumpAndSettle();
      expect(done, isTrue);
    });

    testWidgets('exits cleanly when the tiles never land on screen', (
      tester,
    ) async {
      var done = false;

      // The pruner waits a few frames for a mounting anchor, then gives up —
      // the coach must not linger pointing at air, or worse, stay forever.
      await tester.pumpWidget(
        _harness(
          keys: _keys(),
          steps: CoachTourOverlay.firstRunSteps,
          onDone: () => done = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(find.text('Add your first class'), findsNothing);
    });
  });

  group('tour mechanics (mock 04 fidelity)', () {
    /// Back must cater to Android's system gesture: it steers the tour —
    /// advancing until the last step, then finishing — instead of leaving the
    /// screen the tour is riding on.
    testWidgets('system back advances the tour and finishes at the end', (
      tester,
    ) async {
      var done = false;

      await tester.pumpWidget(_harness(keys: _keys(), onDone: () => done = true));
      await tester.pumpAndSettle();
      expect(find.text('Your next class'), findsOneWidget);

      Future<bool> back() => tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();

      await back();
      await tester.pumpAndSettle();
      expect(find.text('Swipe to manage'), findsOneWidget);
      expect(done, isFalse);

      // Steps 3, 4, 5.
      for (var i = 0; i < 3; i++) {
        await back();
        await tester.pumpAndSettle();
      }
      expect(find.text('Navigate around'), findsOneWidget);
      expect(done, isFalse);

      await back();
      await tester.pumpAndSettle();
      expect(done, isTrue);
    });

    testWidgets('hero tooltip hangs below; FAB and tab bar flip above', (
      tester,
    ) async {
      final keys = _keys();

      // Phone-proportioned panel: the real device is 360×820 logical, and the
      // default 800×600 test surface is too short for the mock's tip-above
      // card to fit — the fit fallback would correctly drop it below and the
      // assertion would test the fallback instead of the mock placement.
      tester.view.physicalSize = const Size(2400, 2460); // 800×820 @ dpr 3
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // Card roughly where Today puts it on the device (~47% down), so there
      // is mock-faithful headroom above it.
      await tester.pumpWidget(
        _harness(keys: keys, onDone: () {}, swipeTop: 385),
      );
      await tester.pumpAndSettle();

      double titleTop(String text) => tester.getTopLeft(find.text(text)).dy;

      // The hero sits high on the screen, so its mock tooltip hangs below.
      expect(
        titleTop('Your next class'),
        greaterThan(tester.getRect(find.byKey(keys.heroKey)).bottom),
      );

      // The swipe step's tooltip flips above the row like mock 04, and the
      // spotlight hole must already be on that row — it repaints off the
      // hole anim, so it never sits on the previous step's target.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final keyCard = find.byKey(keys.swipeTargetKey);
      expect(
        titleTop('Swipe to manage'),
        lessThan(tester.getRect(keyCard).top),
      );
      final spotlight = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType.toString() == '_SpotlightPainter',
        ),
      );
      final holeRect = (spotlight.painter! as dynamic).hole as Rect?;
      expect(holeRect, tester.getRect(keyCard).inflate(6));

      // The FAB is one of the mock's low targets: the tooltip sits above it.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        titleTop('Add classes'),
        lessThan(tester.getRect(find.byKey(keys.fabKey)).top),
      );

      // The tab bar step keeps the narrow 290 tooltip from mock 04, and above.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final tip = tester.widget<Positioned>(
        find.ancestor(
          of: find.text('Navigate around'),
          matching: find.byWidgetPredicate(
            (widget) => widget is Positioned && widget.width != null,
          ),
        ).first,
      );
      expect(tip.width, 290);
      expect(
        titleTop('Navigate around'),
        lessThan(tester.getRect(find.byKey(keys.navKey)).top),
      );
    });

    testWidgets('the spotlight chases a target that moves under it', (
      tester,
    ) async {
      // The hero crossfades from its empty state as the tour mounts, so the
      // first class row ends up somewhere else a few frames later. A hole
      // measured once strands the ring on the old box; it must follow.
      tester.view.physicalSize = const Size(2400, 2460); // 800×820 @ dpr 3
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final keys = _keys();
      await tester.pumpWidget(
        _harness(keys: keys, onDone: () {}, swipeTop: 210),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      Rect hole() {
        final spotlight = tester.widget<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter.runtimeType.toString() == '_SpotlightPainter',
          ),
        );
        return (spotlight.painter! as dynamic).hole as Rect;
      }

      final card = find.byKey(keys.swipeTargetKey);
      expect(hole(), tester.getRect(card).inflate(6));

      // The list settles 175px lower; the whole spotlight (hole and tooltip)
      // follows the card there instead of staying on the old box.
      await tester.pumpWidget(
        _harness(keys: keys, onDone: () {}, swipeTop: 385),
      );
      await tester.pumpAndSettle();

      expect(hole(), tester.getRect(card).inflate(6));
      expect(
        tester.getTopLeft(find.text('Swipe to manage')).dy,
        lessThan(tester.getRect(card).top),
      );
    });
  });
}
