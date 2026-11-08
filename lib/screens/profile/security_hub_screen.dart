import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import 'profile_shared.dart';

/// Password & security hub (mockup v9, frame 5): a hub like Meta's "Login
/// and security", honest content only — no fake 2FA or passkeys.
class SecurityHubScreen extends StatelessWidget {
  const SecurityHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Scaffold(
          appBar: ProfileTitleBar(parent: 'Settings & privacy'),
          body: ListView(
            padding: AppTheme.pagePadding,
            children: [
              const ProfileSubhead(
                title: 'Password & security',
                tagline: 'How you sign in and keep your account safe.',
              ),
              ProfileGroup(
                label: 'PASSWORD',
                description: 'Manage the password you sign in with.',
                rows: [
                  ProfileRow(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change password',
                    subtitle: 'Update your sign-in password',
                    onTap: () => Navigator.of(context)
                        .pushNamed(AppRoutes.changePassword),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.sectionGap),
              ProfileGroup(
                label: 'WHERE YOU’RE SIGNED IN',
                description: 'Phones your account syncs on.',
                rows: [
                  const ProfileRow(
                    icon: Icons.sync_rounded,
                    title: 'This phone',
                    subtitle: 'Signed in automatically',
                    trailing: StatusPill(on: true, label: 'Active'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
