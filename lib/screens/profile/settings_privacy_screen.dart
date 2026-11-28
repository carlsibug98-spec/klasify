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
  int _dismissedConflictCount = 0;

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
            // The hub pill reads the real gates. Until both are loaded it
            // shows nothing rather than guessing; with only one on it reads
            // "Partial" instead of claiming everything is on.
            final remindersLoaded =
                _classEnabled != null && _eventsEnabled != null;
            final notificationsOn =
                (_classEnabled ?? false) || (_eventsEnabled ?? false);
            final notificationsPartial =
                remindersLoaded && _classEnabled != _eventsEnabled;
            return Scaffold(
              appBar: const ProfileTitleBar(parent: 'Profile'),
              body: ListView(
                padding: AppTheme.pagePadding,
                children: [
                  const ProfileSubhead(
                    title: 'Settings & privacy',
                    tagline: 'Account, preferences, legal and support.',
                  ),
                  ListenableBuilder(
                    listenable: SyncService.instance,
                    builder: (context, _) {
                      final count = SyncService.instance.lastConflictCount;
                      return count > 0 && _dismissedConflictCount != count
                          ? Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppTheme.sectionGap,
                              ),
                              child: SyncConflictNotice(
                                count: count,
                                onDismiss: () => setState(
                                  () => _dismissedConflictCount = count,
                                ),
                              ),
                            )
                          : const SizedBox.shrink();
                    },
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
                        ProfileRow(
                          icon: Icons.sync_rounded,
                          title: 'Sync & devices',
                          subtitle: 'Sync status and signed-in phones',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListenableBuilder(
                                listenable: SyncService.instance,
                                builder: (context, _) => SyncStatusPill(
                                  syncing: SyncService.instance.syncing,
                                  lastError: SyncService.instance.lastError,
                                  lastSyncAt: SyncService.instance.lastSyncAt,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ],
                          ),
                          onTap: () => unawaited(
                            Navigator.of(context)
                                .pushNamed(AppRoutes.passwordSecurity),
                          ),
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
                        trailing: remindersLoaded
                            ? StatusPill(
                                on: notificationsOn,
                                partial: notificationsPartial,
                              )
                            : null,
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
                        subtitle: 'What stays local and what syncs',
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

/// Hub's dark-mode row — the switch maps the tri-state theme picker onto the
/// two-way switch (dark ↔ light). A quiet footer link leads back to system
/// mode, which a switch alone cannot express.
class _HubDarkModeRow extends StatelessWidget {
  const _HubDarkModeRow();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeModeService.instance,
      builder: (context, _) {
        final mode = ThemeModeService.instance.mode;
        final isDark = ThemeModeService.instance.isDarkFor(
          systemIsDark:
              MediaQuery.platformBrightnessOf(context) == Brightness.dark,
        );
        final subtitle = switch (mode) {
          KlasifyThemeMode.system => 'Follows your system',
          KlasifyThemeMode.dark => 'Always on',
          KlasifyThemeMode.light => 'Always off',
        };
        return ProfileRow(
          icon: Icons.dark_mode_outlined,
          title: 'Dark mode',
          subtitle: subtitle,
          trailing: MiniSwitch(
            value: isDark,
            semanticsLabel: 'Dark mode',
            onChanged: (on) => unawaited(
              ThemeModeService.instance.setMode(
                on ? KlasifyThemeMode.dark : KlasifyThemeMode.light,
              ),
            ),
          ),
          // The switch cannot select system mode; show the way back only
          // while an explicit choice is in force.
          footer: mode == KlasifyThemeMode.system
              ? null
              : ProfileLink(
                  text: 'Use system setting',
                  onTap: () => unawaited(
                    ThemeModeService.instance.setMode(KlasifyThemeMode.system),
                  ),
                ),
        );
      },
    );
  }
}
