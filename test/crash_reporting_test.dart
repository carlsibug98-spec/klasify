import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/services/crash_reporting.dart';

void main() {
  test(
    'initCrashReporting runs the app runner when no DSN is compiled in',
    () async {
      // Tests build without --dart-define, so the DSN default is '' and the
      // Sentry SDK must never initialize: the local-first default is
      // "no network, no telemetry". Regression guard for that promise.
      var ran = false;
      await initCrashReporting(() async {
        ran = true;
      });
      expect(ran, isTrue);
    },
  );

  test('initCrashReporting awaits the app runner before returning', () async {
    var finished = false;
    final done = initCrashReporting(() async {
      // Simulates the real runner: onboarding read + runApp are awaited.
      await Future<void>.delayed(Duration.zero);
      finished = true;
    });
    expect(finished, isFalse); // not synchronous
    await done;
    expect(finished, isTrue);
  });
}
