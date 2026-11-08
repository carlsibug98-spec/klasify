import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Consent line under the auth forms, restored to the approved mockup
/// wording: "By continuing you agree to the Terms of Service and Privacy
/// Policy." Both names are real links — the shipped screens previously
/// rendered this as one dead label.
class AuthLegalFooter extends StatefulWidget {
  const AuthLegalFooter({super.key});

  @override
  State<AuthLegalFooter> createState() => _AuthLegalFooterState();
}

class _AuthLegalFooterState extends State<AuthLegalFooter> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()
      ..onTap = () => showAuthLegalSheet(context, privacy: false);
    _privacy = TapGestureRecognizer()
      ..onTap = () => showAuthLegalSheet(context, privacy: true);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final linkStyle = style?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: scheme.outline,
    );

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'By continuing you agree to the '),
          TextSpan(
            text: 'Terms of Service',
            style: linkStyle,
            recognizer: _terms,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: _privacy,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

const List<(String, String)> _termsSections = [
  (
    'The app',
    'Klasify is a class-schedule app. It works fully offline, and cloud '
        'sync is optional and off until you sign in.',
  ),
  (
    'Your account',
    'You are responsible for keeping your password safe and for the '
        'accuracy of the schedule you enter.',
  ),
  (
    'Your data',
    'Your schedule stays yours. It is copied to the sync server only to '
        'keep your own signed-in devices in step.',
  ),
  (
    'Availability',
    'The app and the optional sync server are provided as-is, without '
        'warranties. Keep an exported backup (Settings → Backup and '
        'restore) for weeks that matter.',
  ),
  (
    'Changes',
    'These terms may change with app updates; continuing to use the app '
        'accepts the current version.',
  ),
  (
    'Ending use',
    'You can stop at any time by signing out or uninstalling.',
  ),
];

const List<(String, String)> _privacySections = [
  (
    'On this device',
    'Your classes, events and class marks live in a local database on '
        'this phone, whether or not you sign in.',
  ),
  (
    'When you sign in',
    'Sync is optional. After you sign in, those records are sent to the '
        'sync server this build is configured for, together with your '
        'email address and a device identifier, so they can be restored '
        'on your other signed-in devices. Deletions sync as markers so '
        'they also disappear elsewhere.',
  ),
  (
    'Your password',
    'It is never stored by the app. It is sent once, and the server '
        'keeps only a bcrypt hash. Your session token stays in Android '
        'secure storage.',
  ),
  (
    'Not collected',
    'No contacts, location, photos, analytics or advertising data. The '
        'camera is used only when you scan a schedule, and those images '
        'are processed on the device.',
  ),
  (
    'Who holds it',
    'The sync server is run by whoever operates this build of Klasify. '
        'Nothing is shared with third parties.',
  ),
  (
    'Removing it',
    'Uninstalling deletes the local copy. Synced copies are removed by '
        'the server operator; there is no in-app delete-account button '
        'yet.',
  ),
];

/// Opens the short, plain-language legal sheet for the link that was tapped.
Future<void> showAuthLegalSheet(
  BuildContext context, {
  required bool privacy,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final textTheme = theme.textTheme;
      final scheme = theme.colorScheme;
      final sections = privacy ? _privacySections : _termsSections;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                privacy ? 'Privacy Policy' : 'Terms of Service',
                style: textTheme.titleLarge?.copyWith(
                  fontFamily: 'Fraunces',
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Klasify · last updated 8 November 2026',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              for (final (heading, body) in sections) ...[
                Text(
                  heading,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
