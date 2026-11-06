import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/database/database_helper.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/event_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Captures the redesigned event sheet and its pickers exactly as they
/// appear over the shell: the add form, the bottom-sheet date calendar,
/// and the class editor's time wheels, in both themes.
///
/// `flutter test test/event_sheet_capture_test.dart --update-goldens`
/// refreshes the pixels; a plain run smoke-tests the routes.
String _resolveFontDir() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) {
    return '$env/bin/cache/artifacts/material_fonts';
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 4; i++) {
    dir = dir.parent;
  }
  return '${dir.path}/bin/cache/artifacts/material_fonts';
}

final String _fontDir = _resolveFontDir();

Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
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

ThemeData _theme(bool dark) {
  final base = dark ? AppTheme.dark() : AppTheme.light();
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
  );
}

const _phoneInsets = EdgeInsets.only(top: 44, bottom: 34);

final _rootKey = GlobalKey();

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('klasify/next_class_widget'),
      (call) async => null,
    );
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'event_capture_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  testWidgets('capture event sheet and pickers in both themes', (tester) async {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': false});

    Future<void> captureTheme(bool dark) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final suffix = dark ? 'dark' : 'light';

      await tester.pumpWidget(
        RepaintBoundary(
          key: _rootKey,
          child: MaterialApp(
            key: ValueKey('app-$suffix'),
            theme: _theme(dark),
            debugShowCheckedModeBanner: false,
            // The dimmed shell behind a modal: an empty schedule surface
            // keeps the capture honest — the sheet rides the same barrier
            // and SafeArea insets it would over the real Today screen.
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: _phoneInsets,
                  viewPadding: _phoneInsets,
                  viewInsets: EdgeInsets.zero,
                ),
                child: child!,
              );
            },
            home: Builder(
              builder: (context) => Scaffold(
                body: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Future<void> shoot(String name) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (!autoUpdateGoldenFiles) return;
        await expectLater(
          find.byKey(_rootKey),
          matchesGoldenFile('goldens/$name.png'),
        );
      }

      // Add form.
      showEventSheet(tester.element(find.byType(Scaffold).first));
      await tester.pumpAndSettle();
      await shoot('look_event_add_$suffix');

      // Bottom-sheet date calendar.
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();
      await shoot('look_event_date_$suffix');
      await tester.tap(find.byKey(const Key('date_picker_cancel_button')));
      await tester.pumpAndSettle();

      // The class editor's time wheels.
      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      await shoot('look_event_time_$suffix');
      await tester.tap(
        find.byKey(const Key('time_picker_cancel_button')).first,
      );
      await tester.pumpAndSettle();
    }

    await captureTheme(false);
    await captureTheme(true);
  });
}
