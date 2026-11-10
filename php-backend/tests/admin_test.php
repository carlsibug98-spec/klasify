<?php
// tests/admin_test.php
// /admin/* contract parity tests. Office rows are the school-wide set
// (department IS NULL); created_at/updated_at pass through as RAW
// DATETIME(3) strings (no Z suffix) — that dialect is frozen in the
// contract and pinned here.

declare(strict_types=1);

/// Raw DATETIME(3) dialect, e.g. '2026-11-09 12:34:56.789' (note: NO 'Z').
const RAWDT_RX = '/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\z/';

T()->test('admin caller guards: non-admin 403, unknown-user 401', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'u@test.com', 'role' => 'user']);
    act_as($uid);
    $r = run_handler('admin_list_users');
    T()->eq(403, $r['status'], 'non-admin list status');
    T()->eq('Admin access required', $r['body']['error'] ?? null, 'non-admin message');
    T()->eq('FORBIDDEN', $r['body']['code'] ?? null, 'non-admin code');

    // Token for a user that does not exist (fresh table, id 999).
    db_reset();
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . jwt_sign_token(999, 'nobody@test.com');
    $r = run_handler('admin_list_users');
    T()->eq(401, $r['status'], 'unknown caller status');
    T()->eq('User not found', $r['body']['error'] ?? null, 'unknown caller message');
    T()->eq('UNAUTHORIZED', $r['body']['code'] ?? null, 'unknown caller code');
});

T()->test('super admin sees all, raw created_at passthrough', function () {
    db_reset();
    seed_user(['email' => 's1@test.com', 'role' => 'super_admin']);
    seed_user(['email' => 'a2@test.com', 'role' => 'admin', 'department' => 'IT']);
    seed_user(['email' => 'u3@test.com', 'role' => 'user']);
    act_as(1);
    $r = run_handler('admin_list_users');
    T()->eq(200, $r['status'], 'list status');
    T()->truthy(count($r['body']['users'] ?? []) === 3, 'super sees all three');
    $first = $r['body']['users'][0];
    T()->eq(['id', 'email', 'display_name', 'role', 'department', 'created_at'], array_keys($first), 'user row keys');
    T()->truthy(preg_match(RAWDT_RX, (string)$first['created_at']) === 1, 'created_at raw DATETIME(3) (no Z)');
});

T()->test('dept admin sees dept+self, deptless admin sees self only', function () {
    db_reset();
    // ids: 1 super(NULL), 2 admin(IT), 3 user(IT), 4 user(NULL), 5 user(EDUC)
    seed_user(['email' => 's@test.com', 'role' => 'super_admin']);
    seed_user(['email' => 'a-it@test.com', 'role' => 'admin', 'department' => 'IT']);
    seed_user(['email' => 'u-it@test.com', 'role' => 'user', 'department' => 'IT']);
    seed_user(['email' => 'u-nodept@test.com', 'role' => 'user']);
    seed_user(['email' => 'u-educ@test.com', 'role' => 'user', 'department' => 'EDUC']);
    seed_user(['email' => 'a-nodept@test.com', 'role' => 'admin']);

    act_as(2); // IT dept admin
    $r = run_handler('admin_list_users');
    $ids = array_column($r['body']['users'] ?? [], 'id');
    sort($ids);
    T()->eq([2, 3], $ids, 'IT admin sees self + own dept');

    act_as(1); // super sees everyone
    $r = run_handler('admin_list_users');
    T()-> truthy(count($r['body']['users'] ?? []) === 6, 'super sees all');

    act_as(6); // deptless admin: self only
    $r = run_handler('admin_list_users');
    $ids = array_column($r['body']['users'] ?? [], 'id');
    T()->eq([6], $ids, 'deptless admin sees only self');
});

T()->test('role change happy path + boundaries', function () {
    db_reset();
    seed_user(['email' => 'sa@test.com', 'role' => 'super_admin']);
    seed_user(['email' => 't1@test.com', 'role' => 'user']);   // id 2 target
    seed_user(['email' => 'da@test.com', 'role' => 'admin', 'department' => 'IT']); // id 3

    act_as(1);
    set_body(['role' => 'admin']);
    $r = run_handler('admin_set_role', '2');
    T()->eq(200, $r['status'], 'set role status');
    T()->eq(['ok' => true], $r['body'], 'set role body');
    T()->eq('admin', fetch_one('SELECT role FROM users WHERE id = 2')['role'], 'role persisted');

    set_body(['role' => 'boss']);
    $r = run_handler('admin_set_role', '2');
    T()->eq(422, $r['status'], 'invalid role status');
    T()->eq('Invalid role', $r['body']['error'] ?? null, 'invalid role message');

    set_body(['role' => 'admin']);
    $r = run_handler('admin_set_role', '1'); // self-demote
    T()->eq(422, $r['status'], 'self-demote status');
    T()->eq('Cannot demote yourself', $r['body']['error'] ?? null, 'self-demote message');

    act_as(3); // dept admin
    set_body(['role' => 'admin']);
    $r = run_handler('admin_set_role', '2');
    T()->eq(403, $r['status'], 'dept admin set role status');
    T()->eq('Super admin required', $r['body']['error'] ?? null, 'dept admin set role message');
});

T()->test('NON-NUMERIC id returns 404 USER_NOT_FOUND (TDD patch driver)', function () {
    db_reset();
    seed_user(['email' => 'sa2@test.com', 'role' => 'super_admin']);
    act_as(1);

    set_body(['role' => 'admin']);
    $r = run_handler('admin_set_role', 'abc');
    T()->eq(404, $r['status'], 'non-numeric role target status');
    T()->eq('User not found', $r['body']['error'] ?? null, 'non-numeric role target message');
    T()->eq('USER_NOT_FOUND', $r['body']['code'] ?? null, 'non-numeric role target code');

    set_body(['department' => 'AIS']);
    $r = run_handler('admin_set_department', '12th');
    T()->eq(404, $r['status'], 'non-numeric dept target status');
    T()->eq('USER_NOT_FOUND', $r['body']['code'] ?? null, 'non-numeric dept target code');
});

T()->test('department assignment incl. clearing and Node-parity missing id', function () {
    db_reset();
    seed_user(['email' => 'sa3@test.com', 'role' => 'super_admin']);
    seed_user(['email' => 't2@test.com', 'role' => 'user']); // id 2

    act_as(1);
    set_body(['department' => 'AIS']);
    $r = run_handler('admin_set_department', '2');
    T()->eq(200, $r['status'], 'set department status');
    T()->eq('AIS', fetch_one('SELECT department FROM users WHERE id = 2')['department'], 'department persisted');

    set_body(['department' => null]);
    $r = run_handler('admin_set_department', '2');
    T()->eq(200, $r['status'], 'clear department status');
    T()->truthy(fetch_one('SELECT department FROM users WHERE id = 2')['department'] === null, 'department cleared');

    // Node parity: numeric-but-missing id still answers {ok:true}
    // (UPDATE matches 0 rows; not a "fix" candidate).
    set_body(['department' => 'AIS']);
    $r = run_handler('admin_set_department', '999');
    T()->eq(200, $r['status'], 'missing numeric id status');
    T()->eq(['ok' => true], $r['body'], 'missing numeric id body');
});

T()->test('office list: no seeding, empty is valid', function () {
    db_reset();
    seed_user(['email' => 'oa@test.com', 'role' => 'super_admin']);
    act_as(1);
    $r = run_handler('admin_list_offices');
    T()->eq(200, $r['status'], 'list status');
    T()->eq([], $r['body']['offices'] ?? null, 'fresh DB yields empty list');
});

T()->test('add office: 201 + row shape', function () {
    db_reset();
    seed_user(['email' => 'oa2@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Library']);
    $r = run_handler('admin_add_office');
    T()->eq(201, $r['status'], 'create status');
    $o = $r['body']['office'] ?? [];
    T()->eq(['id', 'office_name', 'status', 'custom_message', 'user_id', 'updated_at'], array_keys($o), 'row keys');
    T()->eq('Library', $o['office_name'], 'name kept verbatim');
    T()->eq('open', $o['status'], 'new offices start open');
    T()->truthy($o['custom_message'] === null, 'note null');
    T()->truthy($o['user_id'] === 1, 'creator user_id');
    T()->truthy(preg_match(RAWDT_RX, (string)$o['updated_at']) === 1, 'raw updated_at');
    $r = run_handler('admin_list_offices');
    T()->eq(['Library'], array_column($r['body']['offices'] ?? [], 'office_name'), 'appears in list');
});

T()->test('add office: duplicate case-insensitive -> 409 OFFICE_EXISTS', function () {
    db_reset();
    seed_user(['email' => 'oa3@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Library']);
    run_handler('admin_add_office');
    set_body(['name' => 'library']);
    $r = run_handler('admin_add_office');
    T()->eq(409, $r['status'], 'dup status');
    T()->eq('OFFICE_EXISTS', $r['body']['code'] ?? null, 'dup code');
    set_body(['name' => '  Library  ']);
    $r = run_handler('admin_add_office');
    T()->eq(409, $r['status'], 'padded dup status');
});

T()->test('add office: name validation -> 422', function () {
    db_reset();
    seed_user(['email' => 'oa4@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => '   ']);
    $r = run_handler('admin_add_office');
    T()->eq(422, $r['status'], 'blank name status');
    T()->eq('VALIDATION_ERROR', $r['body']['code'] ?? null, 'blank name code');
    set_body(['name' => str_repeat('x', 41)]);
    $r = run_handler('admin_add_office');
    T()->eq(422, $r['status'], '41-char name status');
    set_body(['name' => str_repeat('x', 40)]);
    T()->eq(201, run_handler('admin_add_office')['status'], '40-char name ok');
});

T()->test('rename office: keeps status+note, tombstones old key', function () {
    db_reset();
    seed_user(['email' => 'oa5@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Library']);
    run_handler('admin_add_office');
    set_body(['status' => 'break', 'custom_message' => 'Back at 2pm']);
    run_handler('admin_update_office', 'Library');
    set_body(['name' => 'Learning Commons']);
    $r = run_handler('admin_rename_office', 'Library');
    T()->eq(200, $r['status'], 'rename status');
    T()->eq(['ok' => true], $r['body'], 'rename body');
    $r = run_handler('admin_list_offices');
    T()->eq(['Learning Commons'], array_column($r['body']['offices'] ?? [], 'office_name'), 'only new key listed');
    $new = fetch_one("SELECT status, custom_message FROM office_statuses WHERE office_name = 'Learning Commons'");
    T()->eq('break', $new['status'], 'status carried over');
    T()->eq('Back at 2pm', $new['custom_message'], 'note carried over');
    T()->eq(1, (int)fetch_one("SELECT deleted FROM office_statuses WHERE office_name = 'Library'")['deleted'], 'old key tombstoned');
});

T()->test('rename office: dup -> 409, unknown -> 404', function () {
    db_reset();
    seed_user(['email' => 'oa6@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Alpha']); run_handler('admin_add_office');
    set_body(['name' => 'Beta']);  run_handler('admin_add_office');
    set_body(['name' => 'beta']);
    $r = run_handler('admin_rename_office', 'Alpha');
    T()->eq(409, $r['status'], 'rename onto existing status');
    T()->eq('OFFICE_EXISTS', $r['body']['code'] ?? null, 'rename onto existing code');
    set_body(['name' => 'Whatever']);
    $r = run_handler('admin_rename_office', 'Nope');
    T()->eq(404, $r['status'], 'rename unknown status');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'rename unknown code');
    $r = run_handler('admin_retire_office', 'Nope');
    T()->eq(404, $r['status'], 'retire unknown status');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'retire unknown code');
});

T()->test('retire office: soft-deletes, list empties, availability PATCH then 404', function () {
    db_reset();
    seed_user(['email' => 'oa7@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['name' => 'Clinic']); run_handler('admin_add_office');
    $r = run_handler('admin_retire_office', 'Clinic');
    T()->eq(200, $r['status'], 'retire status');
    T()->eq(['ok' => true], $r['body'], 'retire body');
    T()->eq([], run_handler('admin_list_offices')['body']['offices'], 'gone from list');
    T()->eq(1, (int)fetch_one("SELECT deleted FROM office_statuses WHERE office_name = 'Clinic'")['deleted'], 'record kept, deleted=1');
    set_body(['status' => 'closed']);
    $r = run_handler('admin_update_office', 'Clinic');
    T()->eq(404, $r['status'], 'availability PATCH on retired office');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'retired office code');
});

T()->test('office CRUD is super_admin only', function () {
    db_reset();
    seed_user(['email' => 's@test.com', 'role' => 'super_admin']);
    seed_user(['email' => 'a@test.com', 'role' => 'admin', 'department' => 'IT']);
    set_body(['name' => 'Library']);
    act_as(2);
    $r = run_handler('admin_add_office');
    T()->eq(403, $r['status'], 'dept admin add');
    T()->eq('FORBIDDEN', $r['body']['code'] ?? null, 'dept admin add code');
    set_body(['name' => 'X']);
    T()->eq(403, run_handler('admin_rename_office', 'Guidance')['status'], 'dept admin rename');
    T()->eq(403, run_handler('admin_retire_office', 'Guidance')['status'], 'dept admin retire');
});

T()->test('availability update: unknown office 404, invalid status 422, non-admin 403', function () {
    db_reset();
    seed_user(['email' => 'oa8@test.com', 'role' => 'super_admin']);
    act_as(1);
    set_body(['status' => 'closed']);
    $r = run_handler('admin_update_office', 'gym');
    T()->eq(404, $r['status'], 'unknown office now 404');
    T()->eq('OFFICE_NOT_FOUND', $r['body']['code'] ?? null, 'unknown office code');
    set_body(['name' => 'Guidance']); run_handler('admin_add_office');
    set_body(['status' => 'nonsense']);
    T()->eq(422, run_handler('admin_update_office', 'Guidance')['status'], 'invalid status');
    $uid = (int)seed_user(['email' => 'u@test.com', 'role' => 'user']);
    act_as($uid);
    set_body(['status' => 'open']);
    T()->eq(403, run_handler('admin_update_office', 'Guidance')['status'], 'non-admin');
});

T()->test('admin routes carry no rate limit', function () {
    db_reset();
    seed_user(['email' => 'oa5@test.com', 'role' => 'super_admin']);
    act_as(1);
    $codes = [];
    for ($i = 0; $i < 40; $i++) {
        $codes[] = run_handler('admin_list_users')['status'];
    }
    T()->truthy(max($codes) === 200 && min($codes) === 200, '40 rapid admin GETs all 200');
});
