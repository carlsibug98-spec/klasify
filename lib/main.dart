import 'dart:async';

import 'package:flutter/material.dart';
import 'routes/app_router.dart';
import 'routes/app_routes.dart';
import 'services/auth_service.dart';
import 'services/app_logger.dart';
import 'services/auto_backup_service.dart';
import 'services/background_sync.dart';
import 'services/crash_reporting.dart';
import 'services/local_scope_service.dart';
import 'services/notification_tap_service.dart';
import 'services/onboarding_store.dart';
import 'services/reminder_service.dart';
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
      AppLogger.e('startup', 'Session restore failed', error: e);
    }
    // Restore (and if needed adopt) the scope the saved session belongs to
    // before anything reads the schedule. A failure leaves the app usable and
    // only blocks sync: it must not act on a file it was not meant to touch.
    try {
      await LocalScopeService.instance.initialise();
      final userId = AuthService.instance.currentUser?['id'];
      await LocalScopeService.instance.ensureForUser(
        userId is int ? userId : null,
      );
    } catch (e) {
      AppLogger.e('startup', 'Local scope init failed', error: e);
      LocalScopeService.instance.markSyncBlocked();
    }
    // Touch the sync client so a restored session starts its 5-minute
    // background timer (the auth listener does the rest).
    SyncService.instance.ensureStarted();
    // Process-death-proof cadence. Registration is non-fatal and Android-only.
    unawaited(BackgroundSync.register());
    // The quiet backup follows schedule changes for the whole session; it
    // starts async so launch never waits on disk or prefs.
    unawaited(AutoBackupService.instance.attach());
    final seenOnboarding = await OnboardingStore.isCompleted();
    // Load the saved theme before the first frame: a dark-mode user must not
    // watch the app start light and flip once prefs finish reading.
    await ThemeModeService.instance.load();
    runApp(ScheduleApp(showOnboarding: !seenOnboarding));
    // A notification tap that launched a killed app arrives here. Wait for
    // the first frame so the navigator key has a live state to route with.
    try {
      final payload = await ReminderService.instance.consumeLaunchPayload();
      if (payload != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleNotificationTap(payload);
        });
      }
    } catch (error) {
      AppLogger.w('notification', 'Launch payload failed', error: error);
    }
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
          navigatorKey: AppRouter.navigatorKey,
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
