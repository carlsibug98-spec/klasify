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

T()->test('office list auto-seeds all 3 with raw updated_at', function () {
    db_reset();
    seed_user(['email' => 'oa@test.com', 'role' => 'admin']);
    act_as(1);
    $r = run_handler('admin_list_offices');
    T()->eq(200, $r['status'], 'office list status');
    $offices = $r['body']['offices'] ?? [];
    T()->eq(['clinic', 'guidance', 'registrar'], array_column($offices, 'office_name'), 'office names ordered by name');
    foreach ($offices as $o) {
        T()->eq('open', $o['status'], "office {$o['office_name']} seeded open");
        T()->truthy($o['user_id'] !== null && $o['user_id'] > 0, "office {$o['office_name']} has seeder user_id");
        T()->truthy(preg_match(RAWDT_RX, (string)$o['updated_at']) === 1, "office {$o['office_name']} raw updated_at");
        T()->truthy($o['custom_message'] === null, "office {$o['office_name']} message null");
    }
});

T()->test('office upsert update branch', function () {
    db_reset();
    seed_user(['email' => 'oa2@test.com', 'role' => 'admin']);
    act_as(1);
    run_handler('admin_list_offices'); // seed

    set_body(['status' => 'break', 'custom_message' => 'Back at 2pm']);
    $r = run_handler('admin_update_office', 'guidance');
    T()->eq(200, $r['status'], 'office update status');
    T()->eq(['ok' => true], $r['body'], 'office update body');

    $r = run_handler('admin_list_offices');
    $g = null;
    foreach ($r['body']['offices'] ?? [] as $o) {
        if ($o['office_name'] === 'guidance') {
            $g = $o;
        }
    }
    T()->truthy($g !== null, 'guidance still listed');
    T()->eq('break', $g['status'], 'guidance status updated');
    T()->eq('Back at 2pm', $g['custom_message'], 'guidance custom_message updated');
    T()->eq(1, $g['user_id'], 'guidance editor recorded');
});

T()->test('office upsert create branch after hard delete', function () {
    db_reset();
    seed_user(['email' => 'oa3@test.com', 'role' => 'admin']);
    act_as(1);
    run_handler('admin_list_offices'); // seed

    query("DELETE FROM office_statuses WHERE office_name = 'guidance'");
    T()->truthy(
        fetch_one("SELECT id FROM office_statuses WHERE office_name = 'guidance'") === null,
        'guidance really gone'
    );

    set_body(['status' => 'closed']);
    $r = run_handler('admin_update_office', 'guidance');
    T()->eq(200, $r['status'], 'office recreate status');

    $r = run_handler('admin_list_offices');
    T()->eq(['clinic', 'guidance', 'registrar'], array_column($r['body']['offices'] ?? [], 'office_name'), '3 offices again');
    T()->eq('closed', fetch_one("SELECT status FROM office_statuses WHERE office_name = 'guidance'")['status'], 'recreated with status');
});

T()->test('office boundaries: unknown office, invalid status, non-admin', function () {
    db_reset();
    seed_user(['email' => 'oa4@test.com', 'role' => 'admin']);
    act_as(1);

    set_body(['status' => 'open']);
    $r = run_handler('admin_update_office', 'gym');
    T()->eq(422, $r['status'], 'unknown office status');
    T()->eq('Unknown office', $r['body']['error'] ?? null, 'unknown office message');

    set_body(['status' => 'vacant']);
    $r = run_handler('admin_update_office', 'guidance');
    T()->eq(422, $r['status'], 'invalid status code path');
    T()->eq('Invalid status', $r['body']['error'] ?? null, 'invalid status message');

    db_reset();
    $uid = (int)seed_user(['email' => 'plain@test.com', 'role' => 'user']);
    act_as($uid);
    set_body(['status' => 'open']);
    $r = run_handler('admin_update_office', 'guidance');
    T()->eq(403, $r['status'], 'non-admin office status');
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
