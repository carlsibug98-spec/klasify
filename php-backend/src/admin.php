<?php
// src/admin.php
// /admin routes: user list, role and department changes, and office availability.
// Every route needs a signed-in admin. Department admins see only their department;
// role and department changes are super_admin only.

const ADMIN_ROLES = ['user', 'admin', 'super_admin'];
const OFFICE_STATUSES = ['open', 'closed', 'break'];
const OFFICES = ['guidance', 'clinic', 'registrar'];

/// Authenticates the caller and confirms they are an admin. Returns their id, role and department.
function admin_caller(): array
{
    $userId = require_auth();
    $row = fetch_one('SELECT id, role, department FROM users WHERE id = ? AND deleted = 0 LIMIT 1', [$userId]);
    if ($row === null) {
        throw new ApiError(401, 'User not found', 'UNAUTHORIZED');
    }
    if (!in_array($row['role'], ['admin', 'super_admin'], true)) {
        throw new ApiError(403, 'Admin access required', 'FORBIDDEN');
    }
    return ['id' => $userId, 'role' => $row['role'], 'department' => $row['department']];
}

/// GET /admin/users -> { users: [...] } (limit 200)
function admin_list_users(): void
{
    $caller = admin_caller();

    $sql = 'SELECT id, email, display_name, role, department, created_at FROM users WHERE deleted = 0';
    $params = [];
    if ($caller['role'] !== 'super_admin') {
        if (js_truthy($caller['department'])) {
            $sql .= ' AND (department = ? OR id = ?)';
            $params = [$caller['department'], $caller['id']];
        } else {
            // A department admin with no department manages only themselves.
            $sql .= ' AND id = ?';
            $params = [$caller['id']];
        }
    }
    $sql .= ' ORDER BY created_at DESC LIMIT 200';

    $users = array_map(fn (array $r) => [
        'id' => (int)$r['id'],
        'email' => $r['email'],
        'display_name' => $r['display_name'],
        'role' => $r['role'],
        'department' => $r['department'],
        'created_at' => $r['created_at'],
    ], fetch_all($sql, $params));

    send_json(200, ['users' => $users]);
}

/// PATCH /admin/users/{id}/role  body: { role }
function admin_set_role(string $id): void
{
    $caller = admin_caller();
    // Hardening patch (2026-11-09, Task 5): a non-numeric path id must not
    // silently become user 0 and answer {ok:true}. Node did the same cast
    // but was unreachable with non-numeric ids; making the failure explicit.
    if (!ctype_digit($id)) {
        throw new ApiError(404, 'User not found', 'USER_NOT_FOUND');
    }
    $targetId = (int)$id;
    $role = trim(js_text(read_json_body()['role'] ?? null));

    if (!in_array($role, ADMIN_ROLES, true)) {
        throw new ApiError(422, 'Invalid role', 'VALIDATION_ERROR');
    }
    if ($caller['role'] !== 'super_admin') {
        throw new ApiError(403, 'Super admin required', 'FORBIDDEN');
    }
    if ($targetId === $caller['id'] && $role !== 'super_admin') {
        throw new ApiError(422, 'Cannot demote yourself', 'VALIDATION_ERROR');
    }

    query('UPDATE users SET role = ? WHERE id = ? AND deleted = 0', [$role, $targetId]);
    send_json(200, ['ok' => true]);
}

/// PATCH /admin/users/{id}/department  body: { department } or { department: null }
function admin_set_department(string $id): void
{
    $caller = admin_caller();
    if (!ctype_digit($id)) {
        throw new ApiError(404, 'User not found', 'USER_NOT_FOUND');
    }
    $targetId = (int)$id;
    $body = read_json_body();

    if ($caller['role'] !== 'super_admin') {
        throw new ApiError(403, 'Super admin required', 'FORBIDDEN');
    }
    $department = nonempty_or_null(trim(js_text($body['department'] ?? null)));

    query('UPDATE users SET department = ? WHERE id = ? AND deleted = 0', [$department, $targetId]);
    send_json(200, ['ok' => true]);
}

/// GET /admin/office-statuses -> { offices: [...] }. Seeds any missing office as "open".
function admin_list_offices(): void
{
    $caller = admin_caller();
    $select = 'SELECT id, office_name, status, custom_message, user_id, updated_at FROM office_statuses WHERE deleted = 0 AND department IS NULL ORDER BY office_name';

    $present = array_column(fetch_all($select), 'office_name');
    foreach (OFFICES as $office) {
        if (!in_array($office, $present, true)) {
            query(
                'INSERT INTO office_statuses (user_id, office_name, department, status) VALUES (?,?,NULL,?)',
                [$caller['id'], $office, 'open']
            );
        }
    }

    $offices = array_map(fn (array $r) => [
        'id' => (int)$r['id'],
        'office_name' => $r['office_name'],
        'status' => $r['status'],
        'custom_message' => $r['custom_message'],
        'user_id' => nullable_int($r['user_id']),
        'updated_at' => $r['updated_at'],
    ], fetch_all($select));

    send_json(200, ['offices' => $offices]);
}

/// PATCH /admin/office-statuses/{office}  body: { status, custom_message? }
function admin_update_office(string $office): void
{
    $caller = admin_caller();
    $office = trim(rawurldecode($office));
    if (!in_array($office, OFFICES, true)) {
        throw new ApiError(422, 'Unknown office', 'VALIDATION_ERROR');
    }

    $body = read_json_body();
    $status = trim(js_text($body['status'] ?? null));
    if (!in_array($status, OFFICE_STATUSES, true)) {
        throw new ApiError(422, 'Invalid status', 'VALIDATION_ERROR');
    }
    $customMessage = isset($body['custom_message']) ? trim(js_string($body['custom_message'])) : null;

    $existing = fetch_one(
        'SELECT id FROM office_statuses WHERE office_name = ? AND department IS NULL AND deleted = 0 LIMIT 1',
        [$office]
    );
    if ($existing !== null) {
        query(
            'UPDATE office_statuses SET status = ?, custom_message = ?, user_id = ? WHERE id = ?',
            [$status, $customMessage, $caller['id'], $existing['id']]
        );
    } else {
        query(
            'INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (?,?,NULL,?,?)',
            [$caller['id'], $office, $status, $customMessage]
        );
    }
    send_json(200, ['ok' => true]);
}
