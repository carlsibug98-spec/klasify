import 'package:flutter/material.dart';
import '../models/class_item.dart';
import '../screens/edit_class_screen.dart';
import '../screens/backup_screen.dart';
import '../screens/reminders_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../features/schedule_import/import_schedule_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/schedule_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/profile/settings_privacy_screen.dart';
import '../screens/profile/personal_details_screen.dart';
import '../screens/profile/security_hub_screen.dart';
import '../screens/profile/change_password_screen.dart';
import '../screens/profile/reset_password_screens.dart';
import '../screens/profile/legal_screens.dart';
import '../screens/profile/admin_screen.dart';
import 'app_routes.dart';

/// The ONLY file that lists every screen.
class AppRouter {
  AppRouter._();

  /// Navigator observer that tells the route-aware shell (main navigation
  /// screen) when a pushed screen — the import flow, the class editor —
  /// pops back on top of it.
  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();

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
      case AppRoutes.login:
        return _page(const LoginScreen(), settings);
      case AppRoutes.signup:
        return _page(const SignupScreen(), settings);
      case AppRoutes.settingsPrivacy:
        return _page(const SettingsPrivacyScreen(), settings);
      case AppRoutes.personalDetails:
        return _page(const PersonalDetailsScreen(), settings);
      case AppRoutes.passwordSecurity:
        return _page(const SecurityHubScreen(), settings);
      case AppRoutes.changePassword:
        return _page(const ChangePasswordScreen(), settings);
      case AppRoutes.resetPassword:
        return _page(const ResetPasswordScreen(), settings);
      case AppRoutes.resetPasswordConfirm:
        return _page(const ResetPasswordConfirmScreen(), settings);
      case AppRoutes.legalTerms:
        return _page(const TermsOfServiceScreen(), settings);
      case AppRoutes.legalPrivacy:
        return _page(const PrivacyPolicyScreen(), settings);
      case AppRoutes.legalStandards:
        return _page(const CommunityStandardsScreen(), settings);
      case AppRoutes.admin:
        return _page(const AdminScreen(), settings);
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
