import 'dart:async';

import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/reminder_service.dart';
import '../../services/sync_service.dart';
import '../../services/theme_mode_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_notification.dart';
import 'profile_shared.dart';
import 'profile_sheets.dart';

/// Settings & privacy (mockup v9, frame 3): the hub the gear on Profile
/// opens. Same row language as the tab, but the hub carries the gray group
/// descriptions — that pattern belongs to hub screens only.
class SettingsPrivacyScreen extends StatefulWidget {
  const SettingsPrivacyScreen({super.key});

  @override
  State<SettingsPrivacyScreen> createState() => _SettingsPrivacyScreenState();
}

class _SettingsPrivacyScreenState extends State<SettingsPrivacyScreen> {
  /// Narrower than the schedule surfaces: the hub reads as a column.
  static const double _contentMaxWidth = 680;

  bool? _classEnabled;
  bool? _eventsEnabled;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    ReminderService.instance.addListener(_onReminderSettingsChanged);
    unawaited(_loadReminderState());
    // Roles/departments can change while the app stays open; a Settings
    // visit is the natural point to re-check the account. The screen already
    // listens to AuthService, so a promotion reveals ADMIN immediately.
    if (AuthService.instance.isLoggedIn) {
      unawaited(AuthService.instance.refreshSession());
    }
  }

  @override
  void dispose() {
    ReminderService.instance.removeListener(_onReminderSettingsChanged);
    super.dispose();
  }

  void _onReminderSettingsChanged() => unawaited(_loadReminderState());

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final ok = await SyncService.instance.syncNow();
    if (mounted) {
      setState(() => _syncing = false);
      showAppNotification(
        context,
        ok ? 'Synced.' : 'Sync failed. Try again later.',
        kind: ok ? AppNotificationKind.success : AppNotificationKind.error,
      );
    }
  }

  Future<void> _loadReminderState() async {
    final classEnabled = await ReminderService.instance.isEnabled;
    final eventsEnabled = await ReminderService.instance.eventsEnabled;
    if (!mounted ||
        (classEnabled == _classEnabled && eventsEnabled == _eventsEnabled)) {
      return;
    }
    setState(() {
      _classEnabled = classEnabled;
      _eventsEnabled = eventsEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: ListenableBuilder(
          listenable: AuthService.instance,
          builder: (context, _) {
            final auth = AuthService.instance;
            final name = auth.displayName?.trim();
            final email = auth.userEmail;
            final contact = [
              if (name != null && name.isNotEmpty) name,
              if (email != null && email.isNotEmpty) email,
            ].join(' · ');
            // The hub pill reads the real gate: anything giving you a
            // reminder right now — class or event — lights the pill.
            final notificationsOn =
                (_classEnabled ?? false) || (_eventsEnabled ?? true);
            return Scaffold(
              appBar: const ProfileTitleBar(parent: 'Profile'),
              body: ListView(
                padding: AppTheme.pagePadding,
                children: [
                  const ProfileSubhead(
                    title: 'Settings & privacy',
                    tagline: 'Account, preferences, legal and support.',
                  ),
                  // ACCOUNT is a signed-in group: without a session there
                  // are no account details to manage, so the hub shows the
                  // account, preferences and legal worlds only.
                  if (auth.isLoggedIn && AuthService.instance.isAdmin) ...[
                    ProfileGroup(
                      label: 'ADMIN',
                      description: AuthService.instance.isSuperAdmin
                          ? 'Office availability, user roles and departments.'
                          : 'Office availability for the campus.',
                      rows: [
                        ProfileRow(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Admin panel',
                          subtitle: AuthService.instance.isSuperAdmin
                              ? 'Manage offices and users'
                              : 'Manage campus offices',
                          onTap: () => unawaited(
                            Navigator.of(context).pushNamed(AppRoutes.admin),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.sectionGap),
                  ],
                  if (auth.isLoggedIn) ...[
                    ProfileGroup(
                      label: 'ACCOUNT',
                      description: 'Your details, password and sync.',
                      rows: [
                        ProfileRow(
                          icon: Icons.person_outline_rounded,
                          title: 'Personal details',
                          subtitle:
                              contact.isEmpty ? 'Name and email' : contact,
                          onTap: () => unawaited(
                            Navigator.of(context)
                                .pushNamed(AppRoutes.personalDetails),
                          ),
                        ),
                        ProfileRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'Password & security',
                          subtitle: 'Password and signed-in devices',
                          onTap: () => unawaited(
                            Navigator.of(context)
                                .pushNamed(AppRoutes.passwordSecurity),
                          ),
                        ),
                        const ProfileRow(
                          icon: Icons.sync_rounded,
                          title: 'Sync & devices',
                          subtitle: 'Syncs after you sign in',
                          trailing: StatusPill(on: true),
                        ),
                        ProfileRow(
                          icon: Icons.sync_rounded,
                          title: 'Sync now',
                          subtitle: _syncing ? 'Syncing…' : 'Push and pull changes',
                          trailing: _syncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                          onTap: _syncing ? null : () => unawaited(_syncNow()),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.sectionGap),
                  ],
                  ProfileGroup(
                    label: 'PREFERENCES',
                    description: 'Reminders and appearance.',
                    rows: [
                      ProfileRow(
                        icon: Icons.notifications_none_rounded,
                        title: 'Notifications',
                        subtitle: 'Class reminders · event alerts',
                        trailing: StatusPill(on: notificationsOn),
                        onTap: () => unawaited(
                          Navigator.of(context).pushNamed(AppRoutes.reminders),
                        ),
                      ),
                      const _HubDarkModeRow(),
                    ],
                  ),
                  const SizedBox(height: AppTheme.sectionGap),
                  ProfileGroup(
                    label: 'COMMUNITY STANDARDS & LEGAL',
                    description: 'The policies that govern Klasify.',
                    rows: [
                      ProfileRow(
                        icon: Icons.description_outlined,
                        title: 'Terms of Service',
                        onTap: () => unawaited(
                          Navigator.of(context).pushNamed(AppRoutes.legalTerms),
                        ),
                      ),
                      ProfileRow(
                        icon: Icons.shield_outlined,
                        title: 'Privacy Policy',
                        subtitle: 'What is stored on each device',
                        onTap: () => unawaited(
                          Navigator.of(context)
                              .pushNamed(AppRoutes.legalPrivacy),
                        ),
                      ),
                      ProfileRow(
                        icon: Icons.groups_2_outlined,
                        title: 'Community standards',
                        onTap: () => unawaited(
                          Navigator.of(context)
                              .pushNamed(AppRoutes.legalStandards),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.sectionGap),
                  ProfileGroup(
                    label: 'HELP & SUPPORT',
                    description: 'Guides and answers.',
                    rows: [
                      ProfileRow(
                        icon: Icons.help_outline_rounded,
                        title: 'Help centre',
                        subtitle: 'Guides and common questions',
                        onTap: () =>
                            unawaited(showProfileHelpCentreSheet(context)),
                      ),
                      ProfileRow(
                        icon: Icons.mail_outline_rounded,
                        title: 'Contact support',
                        subtitle: 'Send a problem report',
                        onTap: () =>
                            unawaited(showProfileContactSupportSheet(context)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Hub's dark-mode row — the switch is real, mapping the tri-state theme
/// picker onto the two-way switch (dark ↔ light).
class _HubDarkModeRow extends StatelessWidget {
  const _HubDarkModeRow();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeModeService.instance,
      builder: (context, _) {
        final mode = ThemeModeService.instance.mode;
        return ProfileRow(
          icon: Icons.dark_mode_outlined,
          title: 'Dark mode',
          subtitle: 'Follows your system by default',
          trailing: MiniSwitch(
            value: mode == KlasifyThemeMode.dark,
            semanticsLabel: 'Dark mode',
            onChanged: (on) => unawaited(
              ThemeModeService.instance.setMode(
                on ? KlasifyThemeMode.dark : KlasifyThemeMode.light,
              ),
            ),
          ),
        );
      },
    );
  }
}
