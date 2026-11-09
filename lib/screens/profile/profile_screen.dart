import 'dart:async';

import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import 'profile_shared.dart';
import '../../widgets/app_notification.dart';

/// The Profile tab: identity surface with schedule + guide shortcuts.
/// MY SCHEDULE and GUIDE live directly on the tab; the hub keeps account,
/// preferences and legal management.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onReplayCoachTour});

  /// The one-time coach tour lives in the shell; Profile replays it across
  /// this callback. Null keeps the row inert (tests, signed-out state).
  final VoidCallback? onReplayCoachTour;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Narrower than the schedule surfaces: profile reads as a column.
  static const double _contentMaxWidth = 680;

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
              ),
              body: ListView(
                padding: AppTheme.pagePadding,
                children: [
                  _ProfileHero(
                    signedIn: auth.isLoggedIn,
                    displayName: auth.displayName,
                    onSignIn: () => unawaited(_pushAuth(AppRoutes.login)),
                    onCreateAccount: () =>
                        unawaited(_pushAuth(AppRoutes.signup)),
                  ),
                  const SizedBox(height: AppTheme.sectionGap),
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
                    label: 'GUIDE',
                    rows: [
                      ProfileRow(
                        icon: Icons.tour_outlined,
                        title: 'Replay the coach tour',
                        subtitle: 'The guided walkthrough of every screen',
                        onTap: widget.onReplayCoachTour,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.sectionGap),
                  ProfileGroup(
                    label: 'SETTINGS',
                    rows: [
                      ProfileRow(
                        icon: Icons.settings_outlined,
                        title: 'Settings & privacy',
                        subtitle: 'Account, preferences, legal and support',
                        onTap: () => unawaited(
                          Navigator.of(context)
                              .pushNamed(AppRoutes.settingsPrivacy),
                        ),
                      ),
                    ],
                  ),
                  if (auth.isLoggedIn) ...[
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
      final ok = await SyncService.instance.syncNow();
      if (mounted && !ok) {
        showAppNotification(
          context,
          'Sync failed. Tap "Sync now" in Settings to retry.',
          kind: AppNotificationKind.warning,
        );
      }
    }
  }
}

/// The hero: avatar (initial; the quiet guest tile when not signed in), the
/// name line, and — only when signed out — the sign-in card.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.signedIn,
    required this.displayName,
    required this.onSignIn,
    required this.onCreateAccount,
  });

  final bool signedIn;
  final String? displayName;
  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

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
          signedIn
              ? _Avatar(initial: initial, dark: dark)
              : const _GuestAvatar(),
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
            ),
          ],
        ],
      ),
    );
  }
}

/// The signed-in avatar: 88px circle, 145° two-stop gradient with the
/// approved edge colours. No edit badge — personal details are reached
/// through Settings & privacy.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    required this.dark,
  });

  final String initial;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 31,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: scheme.onSurface,
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
    final scheme = Theme.of(context).colorScheme;
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

/// The sign-in card on the signed-out hero (frame 9).
class _SignInCard extends StatelessWidget {
  const _SignInCard({
    required this.onSignIn,
    required this.onCreateAccount,
  });

  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;

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
            ],
          ),
        ),
      ),
    );
  }
}

/// Log out as its own error-coloured segment.
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
