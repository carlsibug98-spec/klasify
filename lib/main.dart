import 'package:flutter/material.dart';
import 'routes/app_router.dart';
import 'routes/app_routes.dart';
import 'services/crash_reporting.dart';
import 'services/onboarding_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initCrashReporting(() async {
    final seenOnboarding = await OnboardingStore.isCompleted();
    runApp(ScheduleApp(showOnboarding: !seenOnboarding));
  });
}

class ScheduleApp extends StatelessWidget {
  /// Show the onboarding flow first (true on a fresh install).
  final bool showOnboarding;

  const ScheduleApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Klasify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      initialRoute: showOnboarding ? AppRoutes.onboarding : AppRoutes.home,
      // Build ONLY the initial route. The default would also stack the home
      // screen underneath '/onboarding'.
      onGenerateInitialRoutes: (name) => [
        AppRouter.onGenerateRoute(RouteSettings(name: name)),
      ],
      onGenerateRoute: AppRouter.onGenerateRoute,
      onUnknownRoute: AppRouter.onUnknownRoute,
    );
  }
}
