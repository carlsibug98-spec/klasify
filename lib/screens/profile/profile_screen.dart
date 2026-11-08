import 'dart:async';

import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/reminder_service.dart';
import '../../services/sync_service.dart';
import '../../services/theme_mode_service.dart';
import '../../theme/app_theme.dart';
import 'profile_shared.dart';
import 'profile_sheets.dart';

/// The Profile tab (mockup v9, frames 1/2/9): the signed-in account view
/// with the hero avatar and its account groups, and the signed-out state
/// with the sign-in card. The tab itself stays offline-first: every group
/// except the account ones exists with no session at all.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onReplayCoachTour});

  /// The one-time coach tour lives in the shell; Profile only asks for a
  /// replay across this callback. Null keeps the row inert (tests).
  final VoidCallback? onReplayCoachTour;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Narrower than the schedule surfaces: profile reads as a column.
  static const double _contentMaxWidth = 680;

  bool? _remindersEnabled;

  @override
  void initState() {
    super.initState();
    ReminderService.instance.addListener(_onReminderSettingsChanged);
    unawaited(_loadReminderState());
  }

  @override
  void dispose() {
    ReminderService.instance.removeListener(_onReminderSettingsChanged);
    super.dispose();
  }

  void _onReminderSettingsChanged() => unawaited(_loadReminderState());

  Future<void> _loadReminderState() async {
    final enabled = await ReminderService.instance.isEnabled;
    if (!mounted || enabled == _remindersEnabled) return;
    setState(() => _remindersEnabled = enabled);
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
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: const Text('Profile'),
                actions: [
                  IconButton(
                    tooltip: 'Settings and privacy',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () =>
                        unawaited(Navigator.of(context).pushNamed(
                      AppRoutes.settingsPrivacy,
                      arguments:
                          widget.onReplayCoachTour, // VoidCallback | null
                    )),
                  ),
                ],
              ),
              body: ListView(
                padding: AppTheme.pagePadding,
                children: [
                  _ProfileHero(
                    signedIn: auth.isLoggedIn,
                    displayName: auth.displayName,
                    onEdit: auth.isLoggedIn
                        ? () => unawaited(
                            Navigator.of(context)
                                .pushNamed(AppRoutes.personalDetails),
                          )
                        : null,
                    onSignIn: () => unawaited(_pushAuth(AppRoutes.login)),
                    onCreateAccount: () =>
                        unawaited(_pushAuth(AppRoutes.signup)),
                    onForgotPassword: () =>
                        unawaited(Navigator.of(context)
                            .pushNamed(AppRoutes.resetPassword)),
                  ),
                  const SizedBox(height: AppTheme.sectionGap),
                  if (auth.isLoggedIn) ...[
                    ProfileGroup(
                      label: 'ACCOUNT',
                      rows: [
                        ProfileRow(
                          icon: Icons.person_outline_rounded,
                          title: 'Personal details',
                          subtitle: 'Name, email, display name',
                          onTap: () => unawaited(
                            Navigator.of(context)
                                .pushNamed(AppRoutes.personalDetails),
                          ),
                        ),
                        ProfileRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'Password & security',
                          subtitle: 'Change password',
                          onTap: () => unawaited(
                            Navigator.of(context)
                                .pushNamed(AppRoutes.passwordSecurity),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.sectionGap),
                  ],
                  ProfileGroup(
                    label: 'MY SCHEDULE',
                    rows: [
                      ProfileRow(
                        icon: Icons.document_scanner_outlined,
                        title: 'Import schedule',
                        subtitle: 'From a photo or PDF',
                        onTap: () => unawaited(
                          Navigator.of(context)
                              .pushNamed(AppRoutes.importSchedule),
                        ),
                      ),
                      ProfileRow(
                        icon: Icons.settings_backup_restore_rounded,
                        title: 'Backup and restore',
                        subtitle: 'Saves automatically after every change',
                        onTap: () => unawaited(
                          Navigator.of(context).pushNamed(AppRoutes.backup),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.sectionGap),
                  ProfileGroup(
                    label: 'PREFERENCES',
                    rows: [
                      ProfileRow(
                        icon: Icons.notifications_none_rounded,
                        title: 'Class reminders',
                        subtitle: switch (_remindersEnabled) {
                          null => 'Checking status…',
                          true => 'Alerts before each class',
                          false => 'No alerts scheduled',
                        },
                        trailing: _remindersEnabled == null
                            ? null
                            : StatusPill(on: _remindersEnabled!),
                        onTap: () => unawaited(
                          Navigator.of(context).pushNamed(AppRoutes.reminders),
                        ),
                      ),
                      // Dark mode exists only while signed in (mock frames:
                      // 1/2 show it, 9 hides it together with the hero's
                      // account rows) — the group's radius logic follows
                      // the row count, so it must always be conditional.
                      if (auth.isLoggedIn) const ProfileDarkModeRow(),
                    ],
                  ),
                  if (auth.isLoggedIn) ...[
                    const SizedBox(height: AppTheme.sectionGap),
                    ProfileGroup(
                      label: 'HELP & SUPPORT',
                      rows: [
                        ProfileRow(
                          icon: Icons.menu_book_outlined,
                          title: 'How Klasify works',
                          subtitle: 'A quick tour of the basics',
                          onTap: () => unawaited(
                            Navigator.of(context).pushNamed(
                              AppRoutes.onboarding,
                              arguments: true, // replay: finishing closes it
                            ),
                          ),
                        ),
                        ProfileRow(
                          icon: Icons.widgets_outlined,
                          title: 'Home-screen widget',
                          subtitle: 'Your next class at a glance',
                          onTap: () =>
                              unawaited(showProfileWidgetHelpSheet(context)),
                        ),
                        ProfileRow(
                          icon: Icons.tour_outlined,
                          title: 'Replay the coach tour',
                          subtitle:
                              'The guided walkthrough of every screen',
                          onTap: widget.onReplayCoachTour,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.sectionGap),
                    const _LogoutRow(),
                  ],
                  const SizedBox(height: AppTheme.sectionGap),
                  const ProfileVersionLine(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Pushes a sign-in/sign-up screen; a positive result carries the first
  /// in-session sync so the account and its data are live immediately.
  Future<void> _pushAuth(String route) async {
    final result = await Navigator.pushNamed(context, route);
    if (result == true) {
      await SyncService.instance.syncNow();
    }
  }
}

/// The hero: avatar (initial, edit badge when signed in; the quiet guest
/// tile when not), the name line, and — only when signed out — the sign-in
/// card. Exactly frames 1/2 vs frame 9.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.signedIn,
    required this.displayName,
    required this.onEdit,
    required this.onSignIn,
    required this.onCreateAccount,
    required this.onForgotPassword,
  });

  final bool signedIn;
  final String? displayName;
  final VoidCallback? onEdit;
  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final initial = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim().characters.first.toUpperCase()
        : '?';
    final name = signedIn
        ? (displayName?.trim().isEmpty ?? true)
              ? 'Signed in'
              : displayName!.trim()
        : 'Not signed in';
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 24),
      child: Column(
        children: [
          Semantics(
            button: signedIn,
            label: signedIn ? 'Edit profile photo' : null,
            child: signedIn
                ? _Avatar(initial: initial, dark: dark, onTap: onEdit)
                : const _GuestAvatar(),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 24,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
          ),
          if (!signedIn) ...[
            const SizedBox(height: 20),
            _SignInCard(
              onSignIn: onSignIn,
              onCreateAccount: onCreateAccount,
              onForgotPassword: onForgotPassword,
            ),
          ],
        ],
      ),
    );
  }
}

/// The signed-in avatar: 88px circle, 145° two-stop gradient with the
/// approved edge colours, and the 29px edit button pinned bottom-right
/// with a 3px background ring. Tapping opens Personal details.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    required this.dark,
    required this.onTap,
  });

  final String initial;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF3C3C3C), Color(0xFF1C1C1C)]
                  : const [Color(0xFFECECEC), Color(0xFFD7D7D7)],
            ),
            border: Border.all(
              color: dark
                  ? const Color(0xFF383838)
                  : const Color(0xFFCFCFCF),
            ),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                initial,
                style: TextStyle(
                  fontSize: 31,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: scheme.onSurface,
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.surface,
                      width: 3,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.edit_outlined,
                    size: 13,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The signed-out hero tile: the segment fill with the user glyph.
class _GuestAvatar extends StatelessWidget {
  const _GuestAvatar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: AppTheme.cardFillColorOf(scheme),
        border: Border.all(color: scheme.outlineVariant),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.person_outline_rounded,
        size: 38,
        color: AppTheme.placeholderFor(scheme),
      ),
    );
  }
}

/// The sign-in card on the signed-out hero (frame 9). Same segment edge as
/// the rows, radius 18, copy exact.
class _SignInCard extends StatelessWidget {
  const _SignInCard({
    required this.onSignIn,
    required this.onCreateAccount,
    required this.onForgotPassword,
  });

  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Material(
        color: AppTheme.cardFillColorOf(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: AppTheme.cardBorderSideOf(scheme),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
          child: Column(
            children: [
              Text(
                'Sync across devices',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Sign in only if you want your schedule on another phone.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  height: 1.55,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('profile-signin-cta'),
                  onPressed: onSignIn,
                  child: const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const ValueKey('profile-signup-cta'),
                  onPressed: onCreateAccount,
                  child: const Text('Create account'),
                ),
              ),
              ProfileLink(
                text: 'Forgot password?',
                onTap: onForgotPassword,
                center: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark-mode row: the switch is real — it maps the tri-state theme
/// picker onto the two-way switch (dark ↔ light); the system default is
/// what the app ships with, which is what the subtitle describes.
/// Shared by the Profile tab and the Settings & privacy hub.
class ProfileDarkModeRow extends StatelessWidget {
  const ProfileDarkModeRow();

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

/// Log out as its own error-coloured segment. Confirm first; local schedule
/// data always stays, so we never warn about "losing data".
class _LogoutRow extends StatelessWidget {
  const _LogoutRow();

  Future<void> _confirm(BuildContext context) async {
    final auth = AuthService.instance;
    final email = auth.userEmail;
    final name = auth.displayName;
    final who = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : (email ?? 'this account');
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          'Your schedule stays on this phone and sync picks it back up '
          'when you sign in to $who again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (sure == true && context.mounted) {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Material(
        color: AppTheme.cardFillColorOf(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: AppTheme.cardBorderSideOf(scheme),
        ),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: () => unawaited(_confirm(context)),
            child: SizedBox(
              height: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.logout_rounded,
                    size: 17,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Log out',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: scheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
