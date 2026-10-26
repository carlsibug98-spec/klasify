import 'package:flutter/material.dart';
import '../models/class_item.dart';
import '../screens/edit_class_screen.dart';
import '../screens/backup_screen.dart';
import '../screens/reminders_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../features/schedule_import/import_schedule_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/schedule_screen.dart';
import 'app_routes.dart';

/// The ONLY file that lists every screen.
class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.importSchedule:
        return _page(
          ImportScheduleScreen(
            initialFilePath: settings.arguments is String
                ? settings.arguments as String
                : null,
          ),
          settings,
        );
      case AppRoutes.backup:
        return _page(const BackupScreen(), settings);
      case AppRoutes.reminders:
        return _page(const RemindersScreen(), settings);
      case AppRoutes.home:
        return _page(const MainNavigationScreen(), settings);
      case AppRoutes.schedule:
        return _page(const ScheduleScreen(), settings);
      case AppRoutes.classForm:
        // null = add a new class (today), int = add a class on that weekday
        // (1-7), ClassItem = edit that class, true = return a draft for import
        final args = settings.arguments;
        return _page(
          EditClassScreen(
            classItem: args is ClassItem ? args : null,
            initialDay: args is int ? args : null,
            returnDraft: args == true,
          ),
          settings,
        );
      case AppRoutes.importDraftEditor:
        // Editing a scanned row: return the edited ClassItem to the import
        // review instead of saving it to the database.
        return _page(
          EditClassScreen(
            classItem: settings.arguments as ClassItem,
            returnDraft: true,
          ),
          settings,
        );
      case AppRoutes.onboarding:
        // true = replayed from Settings, so finishing just closes it
        final replay = settings.arguments as bool? ?? false;
        return _page(OnboardingScreen(isReplay: replay), settings);
      case AppRoutes.editClass:
        final item = settings.arguments as ClassItem;
        return _page(EditClassScreen(classItem: item), settings);
      default:
        return onUnknownRoute(settings);
    }
  }

  static Route<dynamic> onUnknownRoute(RouteSettings settings) {
    return _page(
      Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: Center(child: Text('No page named "${settings.name}"')),
      ),
      settings,
    );
  }

  static MaterialPageRoute<dynamic> _page(Widget child, RouteSettings s) =>
      MaterialPageRoute<dynamic>(builder: (_) => child, settings: s);
}
