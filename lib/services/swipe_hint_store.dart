import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the swipe coach hint has been dismissed, so the hint
/// shows once and never nags again. Mirrors OnboardingStore's contract: if
/// storage is unavailable the hint may simply show again, which is harmless.
class SwipeHintStore {
  SwipeHintStore._();

  static const _key = 'swipe_hint_dismissed';

  static Future<bool> isDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> dismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Non-critical: worst case the hint shows once more.
    }
  }
}
