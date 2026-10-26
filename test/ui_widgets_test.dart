import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/class_item.dart';
import 'package:klasify/models/class_status.dart';
import 'package:klasify/features/schedule_import/models/import_draft.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/class_card.dart';
import 'package:klasify/widgets/app_notification.dart';
import 'package:klasify/widgets/day_chips.dart';
import 'package:klasify/features/schedule_import/widgets/import_review_widgets.dart';
import 'package:klasify/widgets/next_class_card.dart';
import 'package:klasify/widgets/live_pulse.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('undo notification exposes one action and runs it', (
    tester,
  ) async {
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppNotification(
                context,
                'Class deleted',
                kind: AppNotificationKind.info,
                duration: const Duration(seconds: 5),
                actionLabel: 'Undo',
                onAction: () async {
                  undone = true;
                },
              ),
              child: const Text('Show notification'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show notification'));
    await tester.pump();
    expect(find.text('Class deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsWidgets);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('Class deleted'), findsNothing);
  });

  test(
    'light and dark themes use matching brightness and warning contrast',
    () {
      final light = AppTheme.light().colorScheme;
      final dark = AppTheme.dark().colorScheme;

      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
      expect(light.tertiaryContainer, isNot(dark.tertiaryContainer));
      expect(
        ThemeData.estimateBrightnessForColor(dark.tertiaryContainer),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(dark.onTertiaryContainer),
        Brightness.light,
      );
    },
  );

  group('formatRoom', () {
    test('adds "Room" to bare numbers and codes', () {
      expect(formatRoom('304'), 'Room 304');
      expect(formatRoom('A-101'), 'Room A-101');
    });
    test('keeps names that already describe the place', () {
      expect(formatRoom('Lab 2'), 'Lab 2');
      expect(formatRoom('Computer Lab 2'), 'Computer Lab 2');
    });
  });

  group('DayChips', () {
    testWidgets('shows seven days and reports taps', (tester) async {
      int? picked;
      await tester.pumpWidget(
        _host(DayChips(selected: 4, onChanged: (d) => picked = d)),
      );
      for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(d), findsOneWidget);
      }
      await tester.tap(find.text('Sat'));
      expect(picked, 6);
    });

    testWidgets('is read-only when onChanged is null', (tester) async {
      await tester.pumpWidget(_host(const DayChips(selected: 3, count: 5)));
      expect(find.text('Sat'), findsNothing);
      await tester.tap(find.text('Mon')); // must not throw
    });

    testWidgets('keeps weekday targets at least 48 pixels wide on phones', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: DayChips(selected: 3, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );

      final dayTargets = find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox && widget.width == 48 && widget.height == 48,
      );
      expect(tester.getSize(dayTargets.first).width, 48);
      expect(find.text('Sun'), findsOneWidget);
    });
  });

  testWidgets('import review rows open for editing and can be removed', (
    tester,
  ) async {
    var edited = false;
    var deleted = false;
    await tester.pumpWidget(
      _host(
        ImportDraftCard(
          draft: ImportDraft(
            subject: 'Data Structures',
            room: 'R4',
            professor: 'Prof. Santos',
            day: 4,
            start: 600,
            end: 660,
          ),
          note: null,
          unknownRoom: false,
          ocrReviewNeeded: false,
          onTap: () => edited = true,
          onDelete: () => deleted = true,
        ),
      ),
    );

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await tester.tap(find.text('Data Structures'));
    expect(edited, isTrue);
    await tester.tap(find.byTooltip('Remove Data Structures from import'));
    expect(deleted, isTrue);
  });

  testWidgets('blocking import warning explains how to continue', (
    tester,
  ) async {
    var acknowledged = false;
    await tester.pumpWidget(
      _host(
        ImportAttentionBanner(
          title: 'Some PDF pages need review',
          message: 'Open the source and add any missed classes.',
          blocking: true,
          dismissLabel: 'Acknowledge and continue',
          onDismiss: () => acknowledged = true,
        ),
      ),
    );

    expect(find.text('Some PDF pages need review'), findsOneWidget);
    await tester.tap(find.text('Acknowledge and continue'));
    expect(acknowledged, isTrue);
  });

  testWidgets('import scan progress shows the current task and percentage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ImportScanProgress(
          stage: ImportScanStage.readingText,
          progress: .56,
          detail: 'Reading PDF page 2 of 4',
        ),
      ),
    );

    expect(find.text('Reading text'), findsNWidgets(2));
    expect(find.text('Reading PDF page 2 of 4'), findsOneWidget);
    expect(find.text('56%'), findsOneWidget);
    expect(find.byIcon(Icons.document_scanner_outlined), findsOneWidget);
  });

  testWidgets('import scan progress can be cancelled', (tester) async {
    var cancelled = false;
    await tester.pumpWidget(
      _host(
        ImportScanProgress(
          stage: ImportScanStage.readingText,
          progress: .4,
          detail: 'Reading timetable text',
          onCancel: () => cancelled = true,
        ),
      ),
    );

    await tester.tap(find.text('Cancel scan'));
    expect(cancelled, isTrue);
  });

  group('ClassCard', () {
    const item = ClassItem(
      subject: 'Data Structures',
      room: '304',
      professor: 'Prof. Santos',
      day: 4,
      startMinutes: 13 * 60,
      endMinutes: 14 * 60 + 30,
    );

    testWidgets('shows time, room and professor', (tester) async {
      await tester.pumpWidget(_host(const ClassCard(item: item)));
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.text(item.timeRange), findsOneWidget);
      expect(find.text('Room 304'), findsOneWidget);
      expect(find.text('Prof. Santos'), findsOneWidget);
    });

    testWidgets('hides a placeholder professor', (tester) async {
      const noProf = ClassItem(
        subject: 'Networking',
        room: 'Lab 2',
        professor: 'Not specified',
        day: 5,
        startMinutes: 600,
        endMinutes: 660,
      );
      await tester.pumpWidget(_host(const ClassCard(item: noProf)));
      expect(find.text('Lab 2'), findsOneWidget);
    });

    testWidgets('emphasizes the time and optionally shows the day', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ClassCard(item: item, showDay: true)),
      );

      final time = tester.widget<Text>(find.text(item.timeRange));
      expect(time.style?.fontWeight, FontWeight.w700);
      expect(find.text('Thu'), findsOneWidget);
    });

    testWidgets('mark pill keeps the status name beside the time', (
      tester,
    ) async {
      const entry = ClassStatusEntry(
        classId: 1,
        status: DayStatus.notAttending,
        startDate: '2026-01-01',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: ClassCard(item: item, statusEntry: entry),
              ),
            ),
          ),
        ),
      );

      // 600px is wider than a phone, but the test font (Ahem) draws every
      // glyph as wide as its size, so text runs ~2.4x real-world width.
      // Under those metrics the short pill fits beside the time while the
      // old combined "status · duration" label still wraps - so this line
      // pins the actual fix.
      expect(find.text('Not attending'), findsOneWidget);
      expect(find.text('Not attending · until cleared'), findsNothing);
      final timeCenter = tester.getCenter(find.text(item.timeRange)).dy;
      final pillCenter = tester.getCenter(find.text('Not attending')).dy;
      expect((pillCenter - timeCenter).abs(), lessThan(4));
    });

    testWidgets('renders pale and reduced opacity when class is finished', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ClassCard(item: item, status: ClassStatus.done)),
      );

      final opacityWidget = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacityWidget.opacity, 0.5);
    });

    testWidgets('offers Edit and Delete in a visible more-options menu', (
      tester,
    ) async {
      var deleteRequested = false;
      await tester.pumpWidget(
        _host(ClassCard(item: item, onDelete: () => deleteRequested = true)),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Edit class'), findsNothing);
      await tester.tap(find.text('Delete class'));
      await tester.pumpAndSettle();
      expect(deleteRequested, isTrue);
    });

    testWidgets('long subject and professor names fit a narrow card', (
      tester,
    ) async {
      const longNames = ClassItem(
        subject:
            'Advanced Distributed Systems and Network Architecture Seminar',
        room: 'Room 304',
        professor: 'Professor Alexandria Montgomery-Smith',
        day: 4,
        startMinutes: 13 * 60,
        endMinutes: 14 * 60 + 30,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 240, child: ClassCard(item: longNames)),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(longNames.subject), findsOneWidget);
      expect(find.textContaining('Professor Alexandria'), findsOneWidget);
    });
  });

  testWidgets('NextClassCard renders its details and badge', (tester) async {
    await tester.pumpWidget(
      _host(
        const NextClassCard(
          label: 'Next up',
          subject: 'Data Structures',
          room: 'Room 304',
          time: '1:00 PM - 2:30 PM',
          whenText: 'Starts in 45 min',
        ),
      ),
    );
    expect(find.text('Next up'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('Starts in 45 min'), findsOneWidget);
    expect(find.text('1:00 PM - 2:30 PM'), findsOneWidget);
    expect(find.text('Room 304'), findsOneWidget);
  });

  testWidgets('hero status tag pulses only while in class', (tester) async {
    Widget hero(String label) => _host(
      NextClassCard(
        key: ValueKey(label),
        label: label,
        subject: 'Data Structures',
        room: 'Room 304',
        time: '1:00 PM - 2:30 PM',
        whenText: label == 'In class' ? 'Ends in 25 min' : 'Starts in 45 min',
      ),
    );

    await tester.pumpWidget(hero('Next up'));
    expect(find.byType(LivePulse), findsNothing);

    await tester.pumpWidget(hero('In class'));
    expect(find.byType(LivePulse), findsOneWidget);
    // Let the pulse run a few frames; it must not throw or leak timers.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(hero('Next up'));
    await tester.pumpAndSettle();
    expect(find.byType(LivePulse), findsNothing);
  });

  testWidgets('live pulse stops under reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: LivePulse())),
        ),
      ),
    );

    final pulse = tester.widget<LivePulse>(find.byType(LivePulse));
    expect(pulse, isNotNull);
    // No ticking animation controller should remain: pumpAndSettle would
    // time out if the pulse kept animating.
    await tester.pumpAndSettle();
  });

  testWidgets('class card shows a live pulse only for the live status', (
    tester,
  ) async {
    final item = const ClassItem(
      subject: 'Algorithms',
      room: 'Room 12',
      professor: 'Prof. Lee',
      day: 1,
      startMinutes: 8 * 60,
      endMinutes: 9 * 60 + 30,
    );

    await tester.pumpWidget(
      _host(ClassCard(item: item, status: ClassStatus.upcoming)),
    );
    expect(find.byType(LivePulse), findsNothing);

    await tester.pumpWidget(
      _host(ClassCard(item: item, status: ClassStatus.live)),
    );
    expect(find.byType(LivePulse), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('NextClassCard renders celebration state with day pill shelf', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const NextClassCard(
          label: 'Next up',
          subject: 'Advanced Mathematics',
          room: 'Room 304',
          time: '08:00 AM - 09:30 AM',
          whenText: 'Starts in 16h 20m',
          celebrationTitle: 'All classes done',
          celebrationSubtitle: 'Good job today — rest up and recharge.',
          celebrationIcon: Icons.check_circle_outline_rounded,
          dayPillText: 'TOMORROW',
        ),
      ),
    );

    expect(find.text('All classes done'), findsOneWidget);
    expect(find.text('Good job today — rest up and recharge.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    // The up-next shelf in the design: day pill left, meta right, then the
    // subject line with its time, and the room beneath.
    expect(find.text('TOMORROW'), findsOneWidget);
    expect(find.text('Starts in 16h 20m'), findsOneWidget);
    expect(find.text('Advanced Mathematics'), findsOneWidget);
    expect(find.text('08:00 AM - 09:30 AM'), findsOneWidget);
    expect(find.text('Room 304'), findsOneWidget);
  });
}
