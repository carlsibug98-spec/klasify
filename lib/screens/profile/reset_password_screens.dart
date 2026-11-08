import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'profile_shared.dart';

/// Step 1 of the reset flow (mockup v9, frame 10): ask for the email.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _emailRegex = r'^[^\s@]+@[^\s@]+\.[^\s@]+$';

  final _emailController = TextEditingController();
  bool _sending = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !RegExp(_emailRegex).hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email');
      return;
    }
    setState(() {
      _sending = true;
      _emailError = null;
    });
    try {
      await AuthService.instance.requestPasswordReset(email: email);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
        AppRoutes.resetPasswordConfirm,
        arguments: email,
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'RATE_LIMITED') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      } else {
        setState(() => _emailError = e.message);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send the code: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = ModalRoute.of(context)?.settings.arguments;
    final backLabel = parent is String ? parent : 'Sign in';
    return Scaffold(
      appBar: ProfileTitleBar(parent: backLabel),
      body: ListView(
        padding: AppTheme.pagePadding,
        children: [
          const ProfileSubhead(
            title: 'Reset password',
            tagline: 'Enter your email and we’ll send you a code to reset it.',
          ),
          ProfileField(
            label: 'EMAIL',
            controller: _emailController,
            hint: 'Enter your sign-in email',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            errorText: _emailError,
            onChanged: (_) => setState(() => _emailError = null),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              child: Text(_sending ? 'Sending…' : 'Send reset code'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2 of the reset flow (mockup v9, frame 11): enter the code + new password.
class ResetPasswordConfirmScreen extends StatefulWidget {
  const ResetPasswordConfirmScreen({super.key});

  @override
  State<ResetPasswordConfirmScreen> createState() =>
      _ResetPasswordConfirmScreenState();
}

class _ResetPasswordConfirmScreenState
    extends State<ResetPasswordConfirmScreen> {
  final _codeController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _codeError;

  @override
  void dispose() {
    _codeController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final next = _newController.text;
    final confirm = _confirmController.text;
    if (code.length != 6 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _codeError = 'Enter the 6-digit code');
      return;
    }
    if (next.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least 8 characters')),
      );
      return;
    }
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The new passwords do not match.')),
      );
      return;
    }
    final email = ModalRoute.of(context)?.settings.arguments;
    if (email is! String || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing email address.')),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _codeError = null;
    });
    try {
      await AuthService.instance.confirmPasswordReset(
        email: email,
        code: code,
        newPassword: next,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset.')),
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'VALIDATION_ERROR') {
        setState(() => _codeError = e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reset the password: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ProfileTitleBar(parent: 'Reset password'),
      body: ListView(
        padding: AppTheme.pagePadding,
        children: [
          const ProfileSubhead(
            title: 'Enter reset code',
            tagline:
                'Enter the code we sent to your email, then pick a new password.',
          ),
          ProfileField(
            label: 'RESET CODE',
            controller: _codeController,
            hint: '6 digits',
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofillHints: const ['one-time-code'],
            textInputAction: TextInputAction.next,
            errorText: _codeError,
            onChanged: (_) => setState(() => _codeError = null),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 6),
            Text(
              'Dev builds: the code appears in the API console '
              '(docker logs klasify-api).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.placeholderFor(
                      Theme.of(context).colorScheme,
                    ),
                  ),
            ),
          ],
          const SizedBox(height: AppTheme.tightGap),
          ProfileField(
            label: 'NEW PASSWORD',
            controller: _newController,
            hint: 'Enter a new password',
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
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Resetting…' : 'Reset password'),
            ),
          ),
        ],
      ),
    );
  }
}
