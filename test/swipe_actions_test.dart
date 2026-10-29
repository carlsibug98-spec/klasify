import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klasify/models/class_item.dart';
import 'package:klasify/services/swipe_hint_store.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/class_card.dart';
import 'package:klasify/widgets/coach_hint.dart';
import 'package:klasify/widgets/swipe_actions.dart';

void main() {
  // The ClassCard is inert here: no status passed, so no LivePulse repeats
  // and pumpAndSettle settles.
  const item = ClassItem(
    id: 1,
    subject: 'Biology',
    room: 'Room 12',
    professor: 'Not specified',
    day: 1,
    startMinutes: 9 * 60,
    endMinutes: 10 * 60,
  );

  Widget host({
    VoidCallback? onEdit,
    Future<bool> Function()? onDelete,
    VoidCallback? onTap,
    VoidCallback? onSwipe,
    double? radius,
    bool forceOpen = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            SwipeActions(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              radius: radius,
              forceOpen: forceOpen,
              onEdit: onEdit,
              onDelete: onDelete,
              onSwipe: onSwipe,
              child: ClassCard(
                item: item,
                insetHorizontally: false,
                trailingGap: false,
                onTap: onTap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  group('SwipeActions', () {
    testWidgets(
      'a custom radius shapes the row clip, which stays off at rest',
      (tester) async {
        // The hero card carries 28px corners and an ambient shadow. The row
        // must adopt the custom radius and must NOT clip while closed, so the
        // shadow renders untouched until a swipe reveals the plane.
        await tester.pumpWidget(host(radius: 28));
        await tester.pumpAndSettle();

        final rowClip = tester.widget<ClipRRect>(
          find.byWidgetPredicate((w) => w is ClipRRect && w.child is Stack),
        );
        expect(rowClip.borderRadius, BorderRadius.circular(28));
        expect(rowClip.clipBehavior, Clip.none);
      },
    );

    testWidgets('the row clip engages only while the plane is revealed', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      ClipRRect rowClip() => tester.widget<ClipRRect>(
        find.byWidgetPredicate((w) => w is ClipRRect && w.child is Stack),
      );
      expect(rowClip().clipBehavior, Clip.none);

      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(rowClip().clipBehavior, Clip.antiAlias);
    });

    testWidgets('the plane surface fades with the reveal, so a closed row '
        'paints no action color outside its bounds', (tester) async {
      // With the row clip off at rest, the closed plane (anchored past the
      // trailing edge) would otherwise paint into the page gutter.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      Opacity planeFade() => tester.widget<Opacity>(
        find.byWidgetPredicate((w) => w is Opacity && w.child is IgnorePointer),
      );
      expect(planeFade().opacity, 0);

      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(planeFade().opacity, 1);
    });

    testWidgets('a short swipe snaps the action plane open', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // 100px is one full plane — past the 50px half-plane snap threshold
      // but short of the 115px full-swipe point.
      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('releasing the tour hold closes the plane it held open', (
      tester,
    ) async {
      // The coach tour latches this row open (forceOpen) for its swipe step.
      // When the tour moves on and flips forceOpen back, the release must
      // close the plane in motion — before, nothing listened on that
      // direction, so the demonstration froze open for the rest of the tour.
      Opacity planeFade() => tester.widget<Opacity>(
        find.byWidgetPredicate((w) => w is Opacity && w.child is IgnorePointer),
      );

      await tester.pumpWidget(host(forceOpen: true));

      // The demonstration starts from rest: the first frame is a closed row,
      // so the step shows the gesture happening instead of a pre-swiped card.
      expect(planeFade().opacity, 0);

      await tester.pumpAndSettle();
      expect(planeFade().opacity, 1);

      await tester.pumpWidget(host(forceOpen: false));
      await tester.pumpAndSettle();

      expect(planeFade().opacity, 0);
    });

    testWidgets('the tour anchor is the card slot, not the padded row', (
      tester,
    ) async {
      // The coach spotlight must hug the card (page insets excluded) and stay
      // put while the card travels, so a full-width row slot is the wrong
      // anchor: its ring would leave the screen on both sides.
      final anchor = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                SwipeActions(
                  targetKey: anchor,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: const ClassCard(
                    item: item,
                    insetHorizontally: false,
                    trailingGap: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(anchor)), tester.getRect(find.byType(ClassCard)));

      // ...and it stays on the resting slot while the card slides open.
      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(anchor)),
        tester.getRect(find.byType(ClassCard)).shift(const Offset(100, 0)),
      );
    });

    testWidgets('a full swipe deletes on release, flies the row off and '
        'collapses its footprint', (tester) async {
      var deletes = 0;
      await tester.pumpWidget(
        host(
          onDelete: () async {
            deletes++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Far past the 100px plane: rubber-banded to ~1.75 planes, above the
      // 115px full-swipe threshold.
      await tester.drag(find.byType(SwipeActions), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(deletes, 1);
      // The row has been handed over: the footprint is fully collapsed (the
      // caller removes the row after a real delete), so the card content is
      // still in the tree but the plane is closed beneath the collapse.
      // A zero-height sliver child counts as offstage to the finder framework,
      // so these tree assertions run with skipOffstage: false.
      expect(find.text('Biology', skipOffstage: false), findsOneWidget);
      expect(
        tester
            .widget<SizeTransition>(
              find.byType(SizeTransition, skipOffstage: false),
            )
            .sizeFactor
            .value,
        0,
      );
    });

    testWidgets('a failed delete brings the row back closed and full height', (
      tester,
    ) async {
      await tester.pumpWidget(host(onDelete: () async => false));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(SwipeActions), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SizeTransition>(find.byType(SizeTransition))
            .sizeFactor
            .value,
        1,
      );
      expect(find.text('Biology'), findsOneWidget);
      // Closed: a tap where the delete action was now reaches the covered
      // card instead of the action.
      await tester.tap(
        find.byIcon(Icons.delete_outline_rounded),
        warnIfMissed: false,
      );
    });

    testWidgets('a fast leftward fling opens the plane below the distance '
        'threshold', (tester) async {
      // The mockup's release rule: a fast leftward fling snaps the plane
      // open; only crossing the full-swipe distance deletes.
      var deletes = 0;
      await tester.pumpWidget(
        host(
          onDelete: () async {
            deletes++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      // 90px only reaches 0.9 of the 100px plane — short of the 115px
      // full-swipe point — but the fling velocity is far past the open
      // threshold.
      await tester.fling(
        find.byType(SwipeActions),
        const Offset(-90, 0),
        2500,
      );
      await tester.pumpAndSettle();

      expect(deletes, 0);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('tapping a plane action fires it and closes', (tester) async {
      var edits = 0;
      var deletes = 0;
      await tester.pumpWidget(
        host(
          onEdit: () => edits++,
          onDelete: () async {
            deletes++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(edits, 1);
      // Closed: the delete action is covered again and out of reach.
      await tester.tap(
        find.byIcon(Icons.delete_outline_rounded),
        warnIfMissed: false,
      );
      expect(deletes, 0);
    });

    testWidgets('tapping the card while open only closes it', (tester) async {
      var cardTaps = 0;
      await tester.pumpWidget(host(onTap: () => cardTaps++));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();

      // The card's content slides left with it, so a text label can move out
      // of the hit-test area while the plane is open. Tap the still-visible
      // part of the card (the wrapper center) instead.
      await tester.tap(find.byType(SwipeActions));
      await tester.pumpAndSettle();

      // The tap closed the plane instead of opening the card's sheet.
      expect(cardTaps, 0);

      // ...and the card accepts taps again now that it is closed.
      await tester.tap(find.byType(SwipeActions));
      await tester.pumpAndSettle();
      expect(cardTaps, 1);
    });

    testWidgets('any completed swipe retires the coach hint', (tester) async {
      var swipes = 0;
      await tester.pumpWidget(host(onSwipe: () => swipes++));
      await tester.pumpAndSettle();

      // A small, sub-threshold drag still counts as learning the gesture.
      // The arena eats the first ~18px as slop, so stay above half the
      // snap threshold even after that loss.
      await tester.drag(find.byType(SwipeActions), const Offset(-60, 0));
      await tester.pumpAndSettle();

      expect(swipes, 1);
    });

    testWidgets('reduced motion opens the plane instantly', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await tester.pumpWidget(host());
      await tester.pump();

      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      // One flushing frame only: with animations disabled the plane must be
      // fully open already, not mid-animation.
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('actions are icon-only pills with class semantics', (
      tester,
    ) async {
      // The v5 mockup's plane is two 44px icon-only pills (16px rounding,
      // 20px icons) carrying aria-labels "Edit class" / "Delete class".
      // No text label renders; semantics carries the names.
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // A short swipe snaps the plane open, putting both pills on screen.
      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.edit_outlined)).size,
        20,
      );
      expect(find.bySemanticsLabel('Edit class'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete class'), findsOneWidget);
      // The framework verifies handles at the end of the body, before any
      // addTearDown callback runs — dispose inline.
      semantics.dispose();
    });

    testWidgets('icons grow in with the reveal, not at full size from rest', (
      tester,
    ) async {
      // At rest the icons are scaled to 0.6 and invisible; once the plane is
      // fully open they sit at scale 1.0 and opacity 1.0. Inspect the Opacity
      // wrappers inside the action plane — they exist only for the grow-in
      // (no other Opacity widget is rendered in this test host).
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // Drag just past the half-plane snap threshold and let it settle open.
      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();

      final opacities = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((w) => w.opacity)
          .toList();
      // Two plane actions plus the plane-level reveal fade, all fully
      // opaque at the open position.
      expect(opacities.length, 3);
      expect(opacities, everyElement(1.0));
    });

    testWidgets('the plane travels with the card and exposes background '
        'once armed', (tester) async {
      // The plane is anchored to the card's trailing edge: closed it sits
      // entirely past the row's right edge (negative right inset); armed it
      // has slid inside the row, leaving a gap of background on its right.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      Positioned plane() => tester.widget<Positioned>(find.byType(Positioned));
      expect(plane().right, lessThan(0));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwipeActions)),
      );
      // -200px is past the 115px full-swipe threshold (1.15 planes) even
      // after the arena's ~18px slop is consumed.
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump();
      }
      // Still holding — _onDragEnd has not fired, so the plane is mid-drag
      // and armed: Edit has collapsed and Delete has taken the freed width.
      // The Edit action's SizedBox has collapsed to 0 width, so the icon
      // (still in the tree) is clipped out of view.
      final editSizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byIcon(Icons.edit_outlined),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(editSizedBox.width, 0);
      final delSizedBox = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byIcon(Icons.delete_outline_rounded),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(delSizedBox.width, SwipeActions.actionExtent * 2);
      // The plane has slid inside the row: background shows on its right.
      expect(plane().right, greaterThan(0));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the card keeps uniform rounding while the plane reveals', (
      tester,
    ) async {
      // The v5 mockup narrows the card without squaring its corners, so no
      // clip above the card text ever drops its radius — closed or open.
      double? topRightOf(ClipRRect clip) =>
          clip.borderRadius.resolve(TextDirection.ltr).topRight.x;

      Set<double> cardClipRightRadii() => tester
          .widgetList<ClipRRect>(
            find.ancestor(
              of: find.text('Biology'),
              matching: find.byType(ClipRRect),
            ),
          )
          .map(topRightOf)
          .whereType<double>()
          .toSet();

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // Closed: no clip squares the card's trailing corners off.
      expect(cardClipRightRadii(), isNot(contains(0)));

      await tester.drag(find.byType(SwipeActions), const Offset(-100, 0));
      await tester.pumpAndSettle();

      // Open: the card still reads uniformly rounded — the row clip keeps
      // its 16px corners and nothing has squared off to 0.
      expect(cardClipRightRadii(), isNot(contains(0)));
      expect(cardClipRightRadii(), contains(AppTheme.cardRadius));
    });

    testWidgets('each pill clips itself to 16px rounding on all corners', (
      tester,
    ) async {
      // The v5 mockup's pills are standalone 16px-rounded buttons; they
      // don't rely on the row's clip for any of their edges.
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      for (final icon in const [
        Icons.edit_outlined,
        Icons.delete_outline_rounded,
      ]) {
        final pillClip = tester.widget<ClipRRect>(
          find
              .ancestor(
                of: find.byIcon(icon),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        final shape = pillClip.borderRadius.resolve(TextDirection.ltr);
        expect(shape.topLeft.x, 16);
        expect(shape.topRight.x, 16);
        expect(shape.bottomLeft.x, 16);
        expect(shape.bottomRight.x, 16);
      }
    });
  });

  group('SwipeHintStore', () {
    test('starts undismissed and remembers dismissal', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SwipeHintStore.isDismissed(), isFalse);

      await SwipeHintStore.dismiss();
      expect(await SwipeHintStore.isDismissed(), isTrue);
    });
  });

  group('CoachHint', () {
    testWidgets('shows its message and dismisses on the close button', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      var dismissed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoachHint(
              message: 'Tip: swipe a class left to edit or delete',
              onDismiss: () => dismissed++,
            ),
          ),
        ),
      );

      expect(
        find.text('Tip: swipe a class left to edit or delete'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();

      expect(dismissed, 1);
    });
  });
}
