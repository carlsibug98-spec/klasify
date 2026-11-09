import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import 'profile_shared.dart';

/// Admin surface: office availability + user role management.
/// Visible only to admins (role = admin or super_admin). Role changes are
/// super-admin only; department admins manage their own office statuses and
/// can post department-wide events from the normal event sheet.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static const double _contentMaxWidth = 680;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _offices = [];
  List<Map<String, dynamic>> _users = [];

  bool get _isSuper => AuthService.instance.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final offices = await AuthService.instance.adminGetOfficeStatuses();
      List<Map<String, dynamic>> users = [];
      if (_isSuper) {
        users = await AuthService.instance.adminGetUsers();
      }
      if (mounted) {
        setState(() {
          _offices = offices;
          _users = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _editOffice(Map<String, dynamic> office) async {
    final name = office['office_name'] as String? ?? '';
    final display = name.isEmpty
        ? 'Office'
        : name[0].toUpperCase() + name.substring(1);
    var status = office['status'] as String? ?? 'open';
    final note = TextEditingController(
      text: office['custom_message'] as String? ?? '',
    );

    final result = await showModalBottomSheet<({String status, String? note})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text(
                    display,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'Students see this on Today, updated at the next sync.',
                    style: Theme.of(sheetContext).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                for (final option in const [
                  ('open', 'Open', Icons.check_circle_outline_rounded),
                  ('break', 'On break', Icons.pause_circle_outline_rounded),
                  ('closed', 'Closed', Icons.cancel_outlined),
                ])
                  ListTile(
                    leading: Icon(option.$3),
                    title: Text(option.$2),
                    trailing: status == option.$1
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => setModal(() => status = option.$1),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: TextField(
                    controller: note,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Back at 2pm',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        final text = note.text.trim();
                        Navigator.pop(sheetContext, (
                          status: status,
                          note: text.isEmpty ? null : text,
                        ));
                      },
                      child: const Text('Update availability'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    note.dispose();

    if (result == null) return;
    try {
      await AuthService.instance.adminSetOfficeStatus(
        name,
        result.status,
        customMessage: result.note,
      );
      // Push the change to the server now; other phones pick it up on
      // their next pull.
      unawaited(SyncService.instance.syncNow());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final id = user['id'] as int;
    final email = user['email'] as String? ?? '';
    var role = user['role'] as String? ?? 'user';
    final dept = TextEditingController(
      text: user['department'] as String? ?? '',
    );

    final result = await showModalBottomSheet<({String role, String? dept})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    email,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final option in const [
                  ('user', 'Student', 'Sees their own schedule and events'),
                  ('admin', 'Department admin', 'Posts events to their department'),
                  ('super_admin', 'Super admin', 'Manages the whole school'),
                ])
                  ListTile(
                    title: Text(option.$2),
                    subtitle: Text(option.$3),
                    trailing: role == option.$1
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => setModal(() => role = option.$1),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: TextField(
                    controller: dept,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Department (optional)',
                      hintText: 'e.g. Senior High',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        final text = dept.text.trim();
                        Navigator.pop(sheetContext, (
                          role: role,
                          dept: text.isEmpty ? null : text,
                        ));
                      },
                      child: const Text('Save user'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    dept.dispose();

    if (result == null) return;
    try {
      if (result.role != (user['role'] as String? ?? 'user')) {
        await AuthService.instance.adminSetRole(id, result.role);
      }
      await AuthService.instance.adminSetDepartment(id, result.dept);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ProfileTitleBar(parent: 'Settings & privacy'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: AppTheme.pagePadding,
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: AppTheme.pagePadding,
                  children: [
                    const ProfileSubhead(
                      title: 'Admin',
                      tagline:
                          'Office availability and the people who help run this campus.',
                    ),
                    ProfileGroup(
                      label: 'OFFICE AVAILABILITY',
                      description:
                          'Open, on break or closed for each office. Students see this on Today.',
                      rows: _offices.isEmpty
                          ? [
                              const ProfileRow(
                                icon: Icons.info_outline_rounded,
                                title: 'No offices yet',
                                subtitle: 'Offices appear after first sync',
                              ),
                            ]
                          : _offices.map((o) {
                              final office =
                                  o['office_name'] as String? ?? '';
                              final status = o['status'] as String? ?? 'open';
                              final note =
                                  (o['custom_message'] as String?)?.trim();
                              final statusLabel = switch (status) {
                                'open' => 'Open',
                                'break' => 'On break',
                                _ => 'Closed',
                              };
                              final display = office.isEmpty
                                  ? 'Office'
                                  : office[0].toUpperCase() +
                                        office.substring(1);
                              return ProfileRow(
                                icon: Icons.meeting_room_outlined,
                                title: display,
                                subtitle: note == null || note.isEmpty
                                    ? statusLabel
                                    : '$statusLabel · $note',
                                onTap: () => unawaited(_editOffice(o)),
                              );
                            }).toList(),
                    ),
                    if (_isSuper) ...[
                      const SizedBox(height: AppTheme.sectionGap),
                      ProfileGroup(
                        label: 'USER ROLES',
                        description:
                            'Promote or demote users. Department admins post events to their own department; super admins post to the whole school.',
                        rows: _users.isEmpty
                            ? [
                                const ProfileRow(
                                  icon: Icons.info_outline_rounded,
                                  title: 'No users',
                                ),
                              ]
                            : _users.map((u) {
                                final id = u['id'] as int;
                                final email = u['email'] as String? ?? '';
                                final role = u['role'] as String? ?? 'user';
                                final dept =
                                    (u['department'] as String?)?.trim();
                                final isSelf = id ==
                                    AuthService.instance.currentUser?['id'];
                                return ProfileRow(
                                  icon: Icons.person_outline_rounded,
                                  title: email,
                                  subtitle: [
                                    switch (role) {
                                      'super_admin' => 'Super admin',
                                      'admin' => 'Department admin',
                                      _ => 'Student',
                                    },
                                    if (dept != null && dept.isNotEmpty)
                                      dept,
                                    if (isSelf) 'You',
                                  ].join(' · '),
                                  trailing: isSelf
                                      ? null
                                      : const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 18,
                                        ),
                                  onTap: isSelf
                                      ? null
                                      : () => unawaited(_editUser(u)),
                                );
                              }).toList(),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
        ),
      ),
    );
  }
}
