import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'profile_shared.dart';

/// Personal details (mockup v9, frame 4): real editing, PATCH /auth/me,
/// plus the delete-account entry point.
class PersonalDetailsScreen extends StatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  State<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends State<PersonalDetailsScreen> {
  static const _emailRegex =
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$';

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _saving = false;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    _nameController.text = auth.displayName ?? '';
    _emailController.text = auth.userEmail ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String? _validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Name is required';
    if (trimmed.length > 100) return 'Name is too long';
    return null;
  }

  String? _validateEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Email is required';
    if (!RegExp(_emailRegex).hasMatch(trimmed)) {
      return 'Enter a valid email';
    }
    return null;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final nameError = _validateName(name);
    final emailError = _validateEmail(email);
    if (nameError != null || emailError != null) {
      setState(() => _emailError = emailError);
      if (nameError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(nameError)),
        );
      }
      return;
    }
    setState(() {
      _saving = true;
      _emailError = null;
    });
    final auth = AuthService.instance;
    final originalName = auth.displayName ?? '';
    final originalEmail = auth.userEmail ?? '';
    final nameChanged = name != originalName;
    final emailChanged = email != originalEmail;
    if (!nameChanged && !emailChanged) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to save.')),
      );
      setState(() => _saving = false);
      return;
    }
    try {
      await auth.updateProfile(
        displayName: nameChanged ? name : null,
        email: emailChanged ? email : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes saved.')),
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'EMAIL_EXISTS') {
        setState(() => _emailError = 'That email is already in use.');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save changes: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'Your account and its schedule copies on the server are removed. '
          'The data on this phone stays until you remove it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await AuthService.instance.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted.')),
      );
    } on AuthApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the account: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ProfileTitleBar(parent: 'Profile'),
      body: ListView(
        padding: AppTheme.pagePadding,
        children: [
          const ProfileSubhead(
            title: 'Personal details',
            tagline: 'Update the name and email on your account.',
          ),
          ProfileField(
            label: 'DISPLAY NAME',
            controller: _nameController,
            hint: 'Your name',
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppTheme.tightGap),
          ProfileField(
            label: 'EMAIL',
            controller: _emailController,
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            errorText: _emailError,
            onChanged: (_) => setState(() => _emailError = null),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save changes'),
            ),
          ),
          const SizedBox(height: 14),
          ProfileLink(
            text: 'Delete account…',
            danger: true,
            icon: Icons.delete_outline_rounded,
            center: true,
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }
}
