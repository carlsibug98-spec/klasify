import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the user has already seen the onboarding flow.
class OnboardingStore {
  OnboardingStore._();

  static const _key = 'onboarding_completed';

  /// True once the user has finished or skipped onboarding.
  ///
  /// If storage is unavailable we return true so a broken preferences store
  /// never traps someone in onboarding on every launch.
  static Future<bool> isCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Non-critical: worst case the user sees onboarding once more.
    }
  }
}
