import 'dart:async';

import 'package:flutter/material.dart';
import 'routes/app_router.dart';
import 'routes/app_routes.dart';
import 'services/auth_service.dart';
import 'services/auto_backup_service.dart';
import 'services/crash_reporting.dart';
import 'services/onboarding_store.dart';
import 'services/sync_service.dart';
import 'services/theme_mode_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCrashReporting(() async {
    // A saved session should survive a cold start so sync keeps working
    // without another sign-in. A keystore failure must never block launch.
    try {
      await AuthService.instance.restoreSession();
    } catch (e) {
      debugPrint('Session restore failed: $e');
    }
    // Touch the sync client so a restored session starts its 5-minute
    // background timer (the auth listener does the rest).
    SyncService.instance.ensureStarted();
    // The quiet backup follows schedule changes for the whole session; it
    // starts async so launch never waits on disk or prefs.
    unawaited(AutoBackupService.instance.attach());
    final seenOnboarding = await OnboardingStore.isCompleted();
    unawaited(ThemeModeService.instance.load());
    runApp(ScheduleApp(showOnboarding: !seenOnboarding));
  });
}

class ScheduleApp extends StatelessWidget {
  /// Show the onboarding flow first (true on a fresh install).
  final bool showOnboarding;

  const ScheduleApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeModeService.instance,
      builder: (context, _) {
        final selected = ThemeModeService.instance.mode;
        final themeMode = switch (selected) {
          KlasifyThemeMode.light => ThemeMode.light,
          KlasifyThemeMode.dark => ThemeMode.dark,
          KlasifyThemeMode.system => ThemeMode.system,
        };
        return MaterialApp(
          title: 'Klasify',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          initialRoute: showOnboarding ? AppRoutes.onboarding : AppRoutes.home,
          // Build ONLY the initial route. The default would also stack the
          // home screen underneath '/onboarding'.
          onGenerateInitialRoutes: (name) => [
            AppRouter.onGenerateRoute(RouteSettings(name: name)),
          ],
          onGenerateRoute: AppRouter.onGenerateRoute,
          onUnknownRoute: AppRouter.onUnknownRoute,
          navigatorObservers: [AppRouter.routeObserver],
        );
      },
    );
  }
}
