import 'package:sentry_flutter/sentry_flutter.dart';

/// Opt-in crash reporting for Klasify.
///
/// Klasify is local-first: no accounts, no analytics, and no network calls.
/// Crash reporting preserves that default. The DSN is supplied at BUILD time
/// through a dart-define:
///
/// ```bash
/// flutter build appbundle --release \
///   --dart-define=KLASIFY_SENTRY_DSN=https://<key>@<org>.ingest.sentry.io/<id>
/// ```
///
/// When no DSN is compiled in (the normal local case), [initCrashReporting]
/// simply runs the app: the Sentry SDK is never initialized, nothing is
/// queued, and the app behaves exactly as before this file existed.
///
/// When a DSN is present, the SDK captures uncaught errors, Flutter
/// framework errors, and native crashes. Offline events are cached on disk
/// and uploaded when connectivity returns, which fits an offline-first app.
/// Privacy configuration (see docs/privacy-policy.html):
///   - `sendDefaultPii` is false: no user identifiers are attached.
///   - Performance tracing is disabled (`tracesSampleRate = 0`).
///   - Screenshots and view hierarchies are never attached.
///   - Reports contain technical diagnostics only (device model, OS and app
///     version, stack traces, timestamps) — never schedule content.
const String _kSentryDsn = String.fromEnvironment(
  'KLASIFY_SENTRY_DSN',
  defaultValue: '',
);

/// Optional environment tag for the report (e.g. `production`, `beta`).
const String _kSentryEnvironment = String.fromEnvironment(
  'KLASIFY_SENTRY_ENV',
  defaultValue: 'production',
);

/// Runs [appRunner], with Sentry active only when a DSN was compiled in.
///
/// Keep this the single wrapper around `runApp` so every build — debug,
/// profile, release — shares one code path.
Future<void> initCrashReporting(AppRunner appRunner) async {
  if (_kSentryDsn.isEmpty) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _kSentryDsn;
      options.environment = _kSentryEnvironment;
      // Privacy-minimal configuration: diagnostics only, no tracing, no PII,
      // no screenshots or view hierarchies.
      options.tracesSampleRate = 0;
      options.sendDefaultPii = false;
      options.attachScreenshot = false;
      options.attachViewHierarchy = false;
      options.replay.sessionSampleRate = 0;
      options.replay.onErrorSampleRate = 0;
    },
    appRunner: appRunner,
  );
}
