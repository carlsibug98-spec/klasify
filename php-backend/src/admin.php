<?php
// src/admin.php
// /admin routes: user list, role and department changes, office availability,
// and office management (add/rename/retire). Every route needs a signed-in
// admin. Department admins see only their department; role and department
// changes plus office management are super_admin only.

const ADMIN_ROLES = ['user', 'admin', 'super_admin'];
const OFFICE_STATUSES = ['open', 'closed', 'break'];

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

/// admin_caller() + super_admin requirement. Returns the caller array.
function admin_super_caller(): array
{
    $caller = admin_caller();
    if ($caller['role'] !== 'super_admin') {
        throw new ApiError(403, 'Super admin required', 'FORBIDDEN');
    }
    return $caller;
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

/// GET /admin/office-statuses -> { offices: [...] }. No seeding; an empty list is valid.
function admin_list_offices(): void
{
    admin_caller();
    $select = 'SELECT id, office_name, status, custom_message, user_id, updated_at FROM office_statuses WHERE deleted = 0 AND department IS NULL ORDER BY office_name';

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
    $office = office_row_or_404($office);

    $body = read_json_body();
    $status = trim(js_text($body['status'] ?? null));
    if (!in_array($status, OFFICE_STATUSES, true)) {
        throw new ApiError(422, 'Invalid status', 'VALIDATION_ERROR');
    }
    $customMessage = isset($body['custom_message']) ? trim(js_string($body['custom_message'])) : null;

    query(
        'UPDATE office_statuses SET status = ?, custom_message = ?, user_id = ? WHERE id = ?',
        [$status, $customMessage, $caller['id'], $office['id']]
    );
    send_json(200, ['ok' => true]);
}

/// Trims an office name; empty or longer than 40 chars is a 422.
function office_name_or_422(string $raw): string
{
    $name = trim($raw);
    if ($name === '' || mb_strlen($name) > 40) {
        throw new ApiError(422, 'Invalid office name', 'VALIDATION_ERROR');
    }
    return $name;
}

/// Rejects a name already used by an active school-wide office (case-insensitive).
function office_assert_unique(string $name, ?int $excludeId = null): void
{
    $sql = 'SELECT id FROM office_statuses WHERE LOWER(office_name) = LOWER(?) AND department IS NULL AND deleted = 0';
    $params = [$name];
    if ($excludeId !== null) {
        $sql .= ' AND id <> ?';
        $params[] = $excludeId;
    }
    if (fetch_one($sql . ' LIMIT 1', $params) !== null) {
        throw new ApiError(409, 'Office already exists', 'OFFICE_EXISTS');
    }
}

/// Loads the active school-wide office named by a path key. 404 when it is gone.
function office_row_or_404(string $key): array
{
    $name = trim(rawurldecode($key));
    $row = fetch_one(
        'SELECT id, office_name, status, custom_message FROM office_statuses WHERE office_name = ? AND department IS NULL AND deleted = 0 LIMIT 1',
        [$name]
    );
    if ($row === null) {
        throw new ApiError(404, 'Office not found', 'OFFICE_NOT_FOUND');
    }
    return $row;
}

/// POST /admin/offices  body: { name } -> 201 { office: {...} }
function admin_add_office(): void
{
    $caller = admin_super_caller();
    $name = office_name_or_422(js_text(read_json_body()['name'] ?? null));
    office_assert_unique($name);

    query(
        'INSERT INTO office_statuses (user_id, office_name, department, status) VALUES (?,?,NULL,?)',
        [$caller['id'], $name, 'open']
    );
    $row = fetch_one(
        'SELECT id, office_name, status, custom_message, user_id, updated_at FROM office_statuses WHERE id = ? LIMIT 1',
        [(int)db()->lastInsertId()]
    );

    send_json(201, ['office' => [
        'id' => (int)$row['id'],
        'office_name' => $row['office_name'],
        'status' => $row['status'],
        'custom_message' => $row['custom_message'],
        'user_id' => nullable_int($row['user_id']),
        'updated_at' => $row['updated_at'],
    ]]);
}

/// PATCH /admin/offices/{office}  body: { name } -> 200 { ok: true }
function admin_rename_office(string $office): void
{
    $caller = admin_super_caller();
    $row = office_row_or_404($office);
    $newName = office_name_or_422(js_text(read_json_body()['name'] ?? null));
    office_assert_unique($newName, (int)$row['id']);

    // Tombstone the old key and re-create it under the new name so the
    // availability row keeps its status and note.
    query(
        'UPDATE office_statuses SET deleted = 1, updated_at = CURRENT_TIMESTAMP(3) WHERE id = ?',
        [$row['id']]
    );
    query(
        'INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (?,?,NULL,?,?)',
        [$caller['id'], $newName, $row['status'], $row['custom_message']]
    );
    send_json(200, ['ok' => true]);
}

/// DELETE /admin/offices/{office} -> 200 { ok: true }. Soft delete, permanent in-app.
function admin_retire_office(string $office): void
{
    admin_super_caller();
    $row = office_row_or_404($office);

    query(
        'UPDATE office_statuses SET deleted = 1, updated_at = CURRENT_TIMESTAMP(3) WHERE id = ?',
        [$row['id']]
    );
    send_json(200, ['ok' => true]);
}
