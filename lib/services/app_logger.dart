import 'package:flutter/foundation.dart';

/// Small structured logger for diagnostics that used to be ad-hoc
/// `debugPrint` calls. A line is always `LEVEL [scope] message`, with an
/// optional error suffix. No file, no PII, no network.
class AppLogger {
  AppLogger._();

  /// Tests replace this with a list sink. null uses [debugPrint].
  static void Function(String line)? sink;

  static void d(String scope, String message, {Object? error}) =>
      _emit('DEBUG', scope, message, error);
  static void i(String scope, String message, {Object? error}) =>
      _emit('INFO', scope, message, error);
  static void w(String scope, String message, {Object? error}) =>
      _emit('WARN', scope, message, error);
  static void e(String scope, String message, {Object? error}) =>
      _emit('ERROR', scope, message, error);

  static void _emit(String level, String scope, String message, Object? error) {
    final line = '$level [$scope] $message${error == null ? '' : ' — $error'}';
    try {
      final target = sink;
      if (target != null) {
        target(line);
      } else {
        debugPrint(line);
      }
    } catch (_) {
      // Logging must never take down the caller.
    }
  }
}
