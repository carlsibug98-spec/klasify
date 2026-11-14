import 'dart:async';

import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'profile_shared.dart';

/// Change password (mockup v9, frame 6): the form sits one level under the
/// security hub. The "Forgot your password?" link sits between the fields
/// and the button, per the Facebook pattern (v8 rule).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _saving = false;
  String? _currentError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateNew(String value) {
    if (value.isEmpty) return 'New password is required';
    if (value.length < 8) return 'At least 8 characters';
    return null;
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;
    if (current.isEmpty) {
      setState(() => _currentError = 'Current password is required');
      return;
    }
    final newError = _validateNew(next);
    if (newError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newError)),
      );
      return;
    }
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The new passwords do not match.')),
      );
      return;
    }
    setState(() {
      _saving = true;
      _currentError = null;
    });
    try {
      await AuthService.instance.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Please sign in again.'),
        ),
      );
      // The session is gone, so the security hub's "Active" panel would be
      // stale. Return to the profile tab, which reflects the signed-out state.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'INVALID_CREDENTIALS') {
        setState(() => _currentError = 'Current password is incorrect');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the password: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ProfileTitleBar(parent: 'Password & security'),
      body: ListView(
        padding: AppTheme.pagePadding,
        children: [
          const ProfileSubhead(
            title: 'Change password',
            tagline: 'Use this password the next time you sign in.',
          ),
          ProfileField(
            label: 'CURRENT PASSWORD',
            controller: _currentController,
            hint: 'Enter your current password',
            obscure: true,
            textInputAction: TextInputAction.next,
            errorText: _currentError,
            onChanged: (_) => setState(() => _currentError = null),
          ),
          const SizedBox(height: AppTheme.tightGap),
          ProfileField(
            label: 'NEW PASSWORD',
            controller: _newController,
            hint: 'At least 8 characters',
            obscure: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppTheme.tightGap),
          ProfileField(
            label: 'CONFIRM NEW PASSWORD',
            controller: _confirmController,
            hint: 'Re-enter the new password',
            obscure: true,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 16),
          ProfileLink(
            text: 'Forgot your password?',
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.resetPassword,
              arguments: 'Password & security',
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Updating…' : 'Update password'),
            ),
          ),
        ],
      ),
    );
  }
}
