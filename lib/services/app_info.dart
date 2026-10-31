/// The app's identity as shown in Settings → About.
///
/// These constants are the single source of truth inside the code; the
/// pubspec.yaml `version:` line is the single source of truth for releases.
/// A drift-guard test (`test/app_info_test.dart`) parses pubspec.yaml and
/// fails when the two disagree, so update both together.
class AppInfo {
  AppInfo._();

  static const String name = 'Klasify';

  /// Semantic version, mirrors pubspec.yaml's `version: <version>+<build>`.
  static const String version = '1.4.0';

  /// Release build number, mirrors the `+<build>` part of pubspec.yaml.
  static const int build = 10;

  /// The label Settings shows, e.g. "Version 1.4.0 (build 10)".
  static const String versionLabel = 'Version $version (build $build)';

  /// The app's defining fact, stated wherever identity is shown.
  static const String tagline = 'Your schedule stays on this device.';
}
