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
          label: 'In class',
          subject: 'Advanced Mathematics',
          room: '304',
          professor: 'Prof. Santos',
          time: '10:00 AM - 11:30 AM',
          whenText: 'Ends in 24m',
          onTap: () {},
        ),
      ),
      'hero_in_class',
    );

    await _shoot(
      tester,
      panel(
        NextClassCard(
          label: 'Upcoming',
          subject: 'Data Structures',
          room: 'Room 211',
          professor: 'Prof. Lim',
          time: '4:00 PM - 5:30 PM',
          whenText: 'Starts 4:00 PM',
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

  testWidgets('capture coach tour', (tester) async {
    final heroKey = GlobalKey();
    final swipeKey = GlobalKey();
    final fabKey = GlobalKey();
    final navKey = GlobalKey();

    await _shoot(
      tester,
      Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFFF2F2F2),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      key: heroKey,
                      height: 150,
                      decoration: BoxDecoration(
                        color: const Color(0xFF151515),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Next class',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      key: swipeKey,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Swipe a class card'),
                    ),
                  ],
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton(
              key: fabKey,
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
            bottomNavigationBar: Container(
              key: navKey,
              height: 64,
              color: Colors.white,
              alignment: Alignment.center,
              child: const Text('Tabs'),
            ),
          ),
          CoachTourOverlay(
            keys: CoachTargetKeys(
              heroKey: heroKey,
              swipeTargetKey: swipeKey,
              fabKey: fabKey,
              navKey: navKey,
            ),
            onDone: () {},
            onTargetActive: (_) {},
          ),
        ],
      ),
      'coach_tour_step1',
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
