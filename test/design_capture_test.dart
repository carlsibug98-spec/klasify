import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/screens/onboarding_screen.dart';
import 'package:klasify/screens/reminders_screen.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/coach_tour_overlay.dart';
import 'package:klasify/widgets/first_run_options.dart';
import 'package:klasify/widgets/next_class_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Flutter SDK's font cache, resolved cross-platform. The original
/// capture ran on Windows with a hard-coded path; derive the SDK root from
/// the FLUTTER_ROOT environment (set by `flutter test`) or, failing that,
/// from the flutter_tester binary location so goldens rebuild anywhere.
String _resolveFontDir() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) {
    return '$env/bin/cache/artifacts/material_fonts';
  }
  // Fallback: <sdk>/bin/cache/artifacts/engine/<target>/flutter_tester.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 4; i++) {
    dir = dir.parent;
  }
  return '${dir.path}/bin/cache/artifacts/material_fonts';
}

final String _fontDir = _resolveFontDir();

Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
  // Index the cache case-insensitively: the artifact package ships
  // `Roboto-Regular.ttf` but the capture list says `roboto-regular.ttf`,
  // which only ever matched because Windows is case-insensitive.
  final byName = {
    for (final e in Directory(_fontDir).listSync())
      e.uri.pathSegments.last.toLowerCase(): e.path,
  };
  for (final f in files) {
    final path = byName[f.toLowerCase()];
    if (path == null) {
      throw StateError('Font $f not found in $_fontDir');
    }
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

ThemeData _theme() {
  final base = AppTheme.light();
  TextStyle? buttonText(ButtonStyle? style) => style?.textStyle
      ?.resolve(const <WidgetState>{})
      ?.copyWith(fontFamily: 'Roboto');
  ButtonStyle? withFont(ButtonStyle? style) =>
      style?.copyWith(textStyle: WidgetStatePropertyAll(buttonText(style)));
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: withFont(base.filledButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: withFont(base.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: withFont(base.outlinedButtonTheme.style),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Roboto',
      ),
    ),
  );
}

const _phoneInsets = EdgeInsets.only(top: 44, bottom: 34);

final _rootKey = GlobalKey();

Future<void> _shoot(
  WidgetTester tester,
  Widget screen,
  String name, {
  EdgeInsets padding = EdgeInsets.zero,
  bool settle = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  debugDisableShadows = false;

  await tester.pumpWidget(
    RepaintBoundary(
      key: _rootKey,
      child: MaterialApp(
        theme: _theme(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              padding: padding,
              viewPadding: padding,
              viewInsets: EdgeInsets.zero,
            ),
            child: child!,
          );
        },
        home: screen,
      ),
    ),
  );
  await tester.pump();
  // The cover logo is an asset; let it decode before the fixed-time pump.
  if (find.byType(Image).evaluate().isNotEmpty) {
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/klasify_logo.png'),
        tester.element(find.byType(Scaffold).first),
      );
    });
    await tester.pump();
  }
  // Fixed pumps: the hero's live pulse never settles. The reminders screen
  // has no perpetual motion, so it can settle its async settings load.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 700));
  }
  await expectLater(
    find.byKey(_rootKey),
    matchesGoldenFile('goldens/$name.png'),
  );
  debugDisableShadows = true;
}

void main() {
  setUpAll(() async {
    await _load('Roboto', [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
    ]);
    await _load('MaterialIcons', ['materialicons-regular.otf']);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  tearDownAll(() {
    debugDisableShadows = true;
  });

  testWidgets('capture onboarding', (tester) async {
    await _shoot(
      tester,
      const OnboardingScreen(isReplay: false),
      'onboarding_1',
      padding: _phoneInsets,
    );

    for (var page = 2; page <= 3; page++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(_rootKey),
        matchesGoldenFile('goldens/onboarding_$page.png'),
      );
    }
  });

  testWidgets('capture hero states', (tester) async {
    Widget panel(Widget child) => Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Center(
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    );

    await _shoot(
      tester,
      panel(
        NextClassCard(
          label: 'Live now',
          subject: 'Advanced Mathematics',
          room: '304',
          countdown: const Duration(minutes: 24),
          whenText: 'Ends in 24m',
          liveProgress: 0.4,
          liveRemaining: const Duration(minutes: 24),
          onTap: () {},
        ),
      ),
      'hero_in_class',
    );

    await _shoot(
      tester,
      panel(
        NextClassCard(
          label: 'Next up',
          subject: 'Data Structures',
          room: 'Room 211',
          countdown: const Duration(hours: 16, minutes: 20),
          onTap: () {},
        ),
      ),
      'hero_upcoming',
    );

    await _shoot(
      tester,
      panel(
        const NextClassCard(
          label: 'Upcoming',
          subject: 'Data Structures',
          room: 'Room 211',
          time: '8:00 AM - 9:30 AM',
          whenText: 'Starts in 16h 20m',
          celebrationTitle: 'All done for today',
          celebrationSubtitle: 'Enjoy the rest of your Saturday.',
          celebrationIcon: Icons.check_circle_outline_rounded,
          dayPillText: 'TOMORROW',
        ),
      ),
      'hero_celebration',
    );
  });

  testWidgets('capture coach tour', (tester) async {
    final keys = CoachTargetKeys(
      heroKey: GlobalKey(),
      swipeTargetKey: GlobalKey(),
      fabKey: GlobalKey(),
      navKey: GlobalKey(),
      tilesKey: GlobalKey(),
    );

    await _shoot(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        body: Stack(
          children: [
            Positioned(
              top: 76,
              left: 20,
              right: 20,
              child: SizedBox(
                key: keys.heroKey,
                child: NextClassCard(
                  label: 'Next up',
                  subject: 'Data Structures',
                  room: 'Room 211',
                  countdown: const Duration(hours: 2, minutes: 12),
                  onTap: () {},
                ),
              ),
            ),
            // The first Today card, parked below the tooltip so it reads as
            // the rest of the screen rather than disappearing underneath.
            Positioned(
              top: 528,
              left: 20,
              right: 20,
              child: Container(
                key: keys.swipeTargetKey,
                height: 88,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Operating Systems'),
                    SizedBox(height: 2),
                    Text('2:00 PM - 3:30 PM · Room 108'),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 118,
              right: 24,
              child: Container(
                key: keys.fabKey,
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFF1C1C1C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 84,
              child: Container(
                key: keys.navKey,
                color: Colors.white,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [Text('Today'), Text('Week'), Text('Settings')],
                ),
              ),
            ),
            Positioned.fill(
              child: CoachTourOverlay(keys: keys, onDone: () {}),
            ),
          ],
        ),
      ),
      'coach_tour_step1',
      settle: true,
    );
  });

  testWidgets('capture first run options', (tester) async {
    await _shoot(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        body: Padding(
          padding: const EdgeInsets.all(20),
          // The captured design is the onboarding variant: tiles on the
          // quiet panel with the detected-class example beneath.
          child: FirstRunOptions(
            onScan: () {},
            onAdd: () {},
            showExample: true,
          ),
        ),
      ),
      'first_run_options',
    );
  });

  testWidgets('capture reminders', (tester) async {
    SharedPreferences.setMockInitialValues({
      'class_reminders_enabled': true,
      'class_reminders_lead_minutes': 10,
    });
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    const timezone = MethodChannel('flutter_timezone');
    const notifications = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(timezone, (call) async => 'UTC');
    messenger.setMockMethodCallHandler(notifications, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method == 'canScheduleExactNotifications') return true;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(timezone, null);
      messenger.setMockMethodCallHandler(notifications, null);
    });

    await _shoot(
      tester,
      const RemindersScreen(),
      'reminders',
      padding: _phoneInsets,
      settle: true,
    );
  });
}
