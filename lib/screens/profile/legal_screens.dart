import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'profile_shared.dart';

/// One legal document screen (mockup v9, frame 8 layout: meta line + h3
/// sections). Privacy Policy and Community standards reuse this layout.
class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({
    super.key,
    required this.title,
    required this.tagline,
    this.meta,
    required this.sections,
  });

  final String title;
  final String tagline;
  final String? meta;
  final List<(String heading, List<String> paragraphs)> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: ProfileTitleBar(parent: 'Settings & privacy'),
      body: ListView(
        padding: AppTheme.pagePadding,
        children: [
          ProfileSubhead(title: title, tagline: tagline),
          if (meta != null) ...[
            Text(
              meta!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: AppTheme.groupLabelColorOf(scheme),
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final (heading, paragraphs) in sections) ...[
            Text(
              heading,
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            for (final paragraph in paragraphs) ...[
              Text(
                paragraph,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Terms of Service (mockup v9, frame 8 sections verbatim).
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocScreen(
      title: 'Terms of Service',
      tagline: 'How Klasify works and what you agree to.',
      meta: 'VERSION 1.4.0 · UPDATED NOVEMBER 2026',
      sections: [
        (
          '1 · Your schedule stays yours',
          [
            'Klasify stores your classes, events and marks on your phone. '
                'The schedule works fully offline, and nothing leaves the '
                'device unless you sign in and enable sync.',
            'When sync is on, only your schedule data and account details '
                'are copied to the Klasify server. We do not sell it, share '
                'it, or use it for advertising.',
          ],
        ),
        (
          '2 · Your account',
          [
            'You are responsible for the email you register and for keeping '
                'your password safe. You may edit your name or email in '
                'Personal details, or delete your account entirely. '
                'Deleting removes your schedule copies on the server; local '
                'copies on your phone stay until you remove them.',
          ],
        ),
        (
          '3 · Acceptable use',
          [
            'Do not use Klasify to post or sync content that is illegal, '
                'harassing, or that impersonates other people. Accounts that '
                'abuse the service may be removed.',
          ],
        ),
        (
          '4 · Changes to these terms',
          [
            'If these terms change, the app shows the new version before '
                'you continue. Continued use after that counts as acceptance.',
          ],
        ),
      ],
    );
  }
}

/// Privacy Policy — adapted from the Terms layout, with the "Removing it"
/// section rewritten for the real delete-account flow.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocScreen(
      title: 'Privacy Policy',
      tagline: 'What is stored on each device.',
      meta: 'VERSION 1.4.0 · UPDATED NOVEMBER 2026',
      sections: [
        (
          '1 · What stays on your phone',
          [
            'Klasify stores your classes, events and marks on this device. '
                'They work fully offline and are never sent anywhere unless '
                'you sign in and enable sync.',
            'Permissions you grant (notifications, alarms) stay on the '
                'device and are not collected by Klasify.',
          ],
        ),
        (
          '2 · What sync copies',
          [
            'When you sign in, your schedule data and account details are '
                'copied to the Klasify server so you can reach them from '
                'another phone. We do not sell it, share it, or use it for '
                'advertising.',
            'Sync is automatic: right after sign-in, after every change, '
                'and whenever you reopen the app.',
          ],
        ),
        (
          '3 · Your account',
          [
            'Your account holds your name, email and password. You can edit '
                'your name and email in Personal details at any time.',
          ],
        ),
        (
          '4 · Removing it',
          [
            'Delete account in Personal details removes your account and its '
                'schedule copies on the server. The data on this phone stays '
                'until you remove it — clear the app data or uninstall to '
                'wipe it.',
          ],
        ),
      ],
    );
  }
}

/// Community standards — the rules that keep Klasify useful for everyone.
class CommunityStandardsScreen extends StatelessWidget {
  const CommunityStandardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocScreen(
      title: 'Community standards',
      tagline: 'How everyone keeps Klasify helpful.',
      meta: 'VERSION 1.4.0 · UPDATED NOVEMBER 2026',
      sections: [
        (
          '1 · Respect',
          [
            'Be kind to the people you share a schedule with. Do not use '
                'Klasify to harass, bully or impersonate others.',
          ],
        ),
        (
          '2 · Acceptable use',
          [
            'Do not post or sync content that is illegal, offensive or '
                'misleading. Accounts that abuse the service may be removed.',
          ],
        ),
        (
          '3 · Reporting',
          [
            'If something is wrong, use Contact support in Settings & '
                'privacy to send a problem report with the app version '
                'included.',
          ],
        ),
      ],
    );
  }
}
