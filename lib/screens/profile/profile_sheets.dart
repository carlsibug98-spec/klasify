import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_info.dart';
import '../../theme/app_theme.dart';

/// The bottom sheets the Profile world opens. The About sheet carried over
/// from the old Settings screen; the Help centre and Contact support sheets
/// answer the two rows the Security-and-privacy hub gained in mockup v9.
/// All answers stay factual to how the app actually works.

Future<void> showProfileAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.sheetRadius),
      ),
    ),
    builder: (_) => const ProfileAboutSheet(),
  );
}

Future<void> showProfileHelpCentreSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.sheetRadius),
      ),
    ),
    builder: (_) => const ProfileHelpCentreSheet(),
  );
}

Future<void> showProfileContactSupportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.sheetRadius),
      ),
    ),
    builder: (_) => const ProfileContactSupportSheet(),
  );
}

/// The About bottom sheet: the app's identity, version, and its defining
/// fact, with the licenses one tap away. Same layout idiom as the day
/// status sheet (icon block + title + subtitle on a single quiet surface).
class ProfileAboutSheet extends StatelessWidget {
  const ProfileAboutSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pageInset,
              6,
              AppTheme.pageInset,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/klasify_logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: AppTheme.itemGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppInfo.name,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppInfo.versionLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  AppInfo.tagline,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Timetable, reminders, and automatic backups all work '
                  'offline. Syncing across phones is optional, and file '
                  'exports let you move your schedule by hand.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Divider(color: scheme.outlineVariant),
                InkWell(
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppInfo.name,
                    applicationVersion: '${AppInfo.version} (${AppInfo.build})',
                    applicationIcon: const ImageIcon(
                      AssetImage('assets/klasify_logo.png'),
                      size: 44,
                    ),
                    applicationLegalese: AppInfo.tagline,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Open-source licenses',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Help centre sheet: the questions the app can answer from its own
/// behaviour, written from how things actually work.
class ProfileHelpCentreSheet extends StatelessWidget {
  const ProfileHelpCentreSheet({super.key});

  static const List<(String, String)> _answers = [
    (
      'Where does my schedule live?',
      'On this phone. Klasify is offline-first: your classes, events and '
          'marks all work with no account at all.',
    ),
    (
      'When does sync happen?',
      'Automatically. Right after you sign in, then again after every '
          'change and whenever you reopen the app. There is no Sync now '
          'button — it just keeps up.',
    ),
    (
      'How do I move my schedule to a new phone?',
      'Profile → My schedule → Backup and restore makes a backup file, '
          'and the same screen brings it back on the new phone.',
    ),
    (
      'Reminders don’t arrive on time.',
      'Check Android settings: Klasify needs Notifications, and '
          '“Alarms & reminders” for on-time alerts. Do Not Disturb still '
          'applies.',
    ),
    (
      'How do I remove my account?',
      'Personal details → Delete account. The server copies disappear '
          'with it; local data on this phone stays until you remove it.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppTheme.itemGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Help centre',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Guides and common questions',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            for (final (question, answer) in _answers) ...[
              Text(
                question,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                answer,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contact support without an email backend: the sheet tells the user what
/// a useful report contains and copies the app's fingerprint to the
/// clipboard so it can be pasted wherever they reach the developer.
class ProfileContactSupportSheet extends StatelessWidget {
  const ProfileContactSupportSheet({super.key});

  static String get _report =>
      'Klasify ${AppInfo.version} (build ${AppInfo.build})';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.mail_outline_rounded,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppTheme.itemGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact support',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Send a problem report',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Write down what you expected and what happened instead. Paste '
            'the app details below into your message when you send it to '
            'the developer — it makes the report reproducible.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.fromBorderSide(AppTheme.cardBorderSideOf(scheme)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _report,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _report),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied. Paste it into your report.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Copy'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
