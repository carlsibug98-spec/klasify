import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the empty-schedule coach has been seen, so the "START
/// HERE" spotlight over the Scan/Add tiles shows once for newcomers who
/// reached Today with no classes — the "Explore first" path, or a skip
/// past onboarding — and never nags again. If storage is unavailable the
/// coach may simply show again, which is harmless.
class FirstClassCoachStore {
  FirstClassCoachStore._();

  static const _key = 'first_class_coach_dismissed';

  static Future<bool> isDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Non-critical: worst case the coach plays once more.
    }
  }
}
