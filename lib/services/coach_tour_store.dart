import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the one-time coach tour has been shown, so the guided
/// walkthrough runs once — right after the user's first class lands — and
/// never nags again. Mirrors SwipeHintStore's contract: if storage is
/// unavailable the tour may simply show again, which is harmless.
class CoachTourStore {
  CoachTourStore._();

  static const _key = 'coach_tour_shown';

  static Future<bool> isShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {
      // Non-critical: worst case the tour plays once more.
    }
  }

  /// Settings' Help section replays the one-time tour: clear the flag so
  /// the shell mounts the guided walkthrough again on request.
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Non-critical: worst case the tour plays once more.
    }
  }
}
