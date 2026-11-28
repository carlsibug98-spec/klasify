import 'auth_api.dart';

/// Admin endpoints: users, roles, departments, and office availability.
///
/// The server scopes every response by the caller's role/department. These
/// methods only shape requests and unwrap the response envelopes.
class AdminApi {
  AdminApi(this._api);

  final AuthApi _api;

  /// Admin: list users (scoped by caller's role/department on the server).
  Future<List<Map<String, dynamic>>> getUsers() async {
    final data = await _api.send('GET', '/admin/users') as Map<String, dynamic>;
    return (data['users'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Admin: promote/demote a user (super_admin only).
  Future<void> setRole(int userId, String role) async {
    await _api.send('PATCH', '/admin/users/$userId/role', body: {'role': role});
  }

  /// Admin: assign a user to a department (super_admin only).
  Future<void> setDepartment(int userId, String? department) async {
    await _api.send(
      'PATCH',
      '/admin/users/$userId/department',
      body: {'department': department},
    );
  }

  /// Admin: list office statuses (scoped by caller's role/department).
  Future<List<Map<String, dynamic>>> getOfficeStatuses() async {
    final data =
        await _api.send('GET', '/admin/office-statuses')
            as Map<String, dynamic>;
    return (data['offices'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Admin: update an office's status.
  Future<void> setOfficeStatus(
    String office,
    String status, {
    String? customMessage,
    String? department,
  }) async {
    await _api.send(
      'PATCH',
      '/admin/office-statuses/${Uri.encodeComponent(office)}',
      body: {
        'status': status,
        'custom_message': customMessage,
        'department': department,
      },
    );
  }

  /// Admin: create a new school-wide office (super_admin only). Returns the
  /// created row (same shape as getOfficeStatuses rows).
  Future<Map<String, dynamic>> addOffice(String name) async {
    final data =
        await _api.send('POST', '/admin/offices', body: {'name': name})
            as Map<String, dynamic>;
    return (data['office'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Admin: rename an office (super_admin only). The old key disappears at
  /// every phone's next sync; availability and note carry over.
  Future<void> renameOffice(String office, String newName) async {
    await _api.send(
      'PATCH',
      '/admin/offices/${Uri.encodeComponent(office)}',
      body: {'name': newName},
    );
  }

  /// Admin: retire an office (super_admin only). Soft delete: students lose
  /// it at their next sync; the record stays on the server.
  Future<void> retireOffice(String office) async {
    await _api.send('DELETE', '/admin/offices/${Uri.encodeComponent(office)}');
  }
}
