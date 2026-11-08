import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which theme the user picked on Profile → Preferences.
enum KlasifyThemeMode { system, light, dark }

/// Persists and broadcasts the app theme mode. The Material [ThemeMode]
/// mapping lives in `main.dart`; this class stays theme-agnostic and
/// mirrors the other stores' fail-open behaviour (a broken prefs store is
/// not allowed to change how the app looks).
class ThemeModeService extends ChangeNotifier {
  ThemeModeService._();
  static final ThemeModeService instance = ThemeModeService._();

  static const _key = 'theme_mode';

  KlasifyThemeMode _mode = KlasifyThemeMode.system;

  /// The selected mode; system is the default on fresh installs.
  KlasifyThemeMode get mode => _mode;

  /// Read the stored selection. Call once at startup (before runApp).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _mode = KlasifyThemeMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => KlasifyThemeMode.system,
      );
    } catch (_) {
      // Missing/corrupt prefs: the default (system) stands.
    }
    notifyListeners();
  }

  /// Switch the mode, broadcast it, and persist the choice.
  Future<void> setMode(KlasifyThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Non-critical: the toggle still works this session.
    }
  }
}
