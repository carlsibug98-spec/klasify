<?php
// tests/normalization_test.php
// Strict-normalization regressions: account-scoped devices, typed local-id
// maps, derived ownership, departments, offices, reset TTLs, and the split
// rate-limit key. Each test states the relation it protects.

declare(strict_types=1);

/// Assert a write is rejected by a database constraint.
function expect_pdo_code(int $code, callable $fn, string $label): void
{
    try {
        $fn();
    } catch (PDOException $e) {
        T()->eq($code, (int)($e->errorInfo[1] ?? 0), $label . ' (SQLSTATE ' . $e->getCode() . ')');
        return;
    }
    T()->fail($label . ': statement was accepted');
}

T()->test('device id is required on push and pull', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd1@test.com']);
    act_as($uid);

    set_body(['classes' => [], 'events' => [], 'class_statuses' => []]);
    $r = run_handler('sync_push');
    T()->eq(422, $r['status'], 'push without device_id status');
    T()->eq('DEVICE_REQUIRED', $r['body']['code'] ?? null, 'push without device_id code');

    $_GET = [];
    set_body(null);
    $r = run_handler('sync_pull');
    T()->eq(422, $r['status'], 'pull without device_id status');
    T()->eq('DEVICE_REQUIRED', $r['body']['code'] ?? null, 'pull without device_id code');

    T()->eq(
        0,
        (int)query('SELECT COUNT(*) FROM sync_devices')->fetchColumn(),
        'no device registered by a rejected request'
    );
});

T()->test('a device id owned by another account is 409', function () {
    db_reset();
    $a = (int)seed_user(['email' => 'nd2a@test.com']);
    $b = (int)seed_user(['email' => 'nd2b@test.com']);

    act_as($a);
    set_body(['device_id' => 'shared-phone', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    T()->eq(200, run_handler('sync_push')['status'], 'owner registers device');

    act_as($b);
    set_body(['device_id' => 'shared-phone', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    $r = run_handler('sync_push');
    T()->eq(409, $r['status'], 'second account rejected');
    T()->eq('DEVICE_CONFLICT', $r['body']['code'] ?? null, 'conflict code');
    T()->eq(
        $a,
        (int)query('SELECT user_id FROM sync_devices WHERE device_id = ?', ['shared-phone'])->fetchColumn(),
        'device owner unchanged'
    );
});

T()->test('two devices may use the same local id without touching each other', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd3@test.com']);
    act_as($uid);

    $class = fn (string $subject) => [
        'local_id' => 1, 'subject' => $subject, 'room' => 'R', 'professor' => 'Prof A',
        'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD,
    ];

    set_body(['device_id' => 'devA', 'classes' => [$class('From A')]]);
    $r1 = run_handler('sync_push');
    $idA = $r1['body']['classes'][0]['server_id'] ?? 0;

    set_body(['device_id' => 'devB', 'classes' => [$class('From B')]]);
    $r2 = run_handler('sync_push');
    $idB = $r2['body']['classes'][0]['server_id'] ?? 0;

    T()->truthy($idA > 0 && $idB > 0 && $idA !== $idB, 'two classes created');
    T()->eq('From A', fetch_one('SELECT subject FROM classes WHERE id = ?', [$idA])['subject'], 'device A row intact');
    T()->eq('From B', fetch_one('SELECT subject FROM classes WHERE id = ?', [$idB])['subject'], 'device B row separate');
    T()->eq(
        $idA,
        (int)query('SELECT class_id FROM class_local_map WHERE device_id = ? AND local_id = 1', ['devA'])->fetchColumn(),
        'map A points at A'
    );
    T()->eq(
        $idB,
        (int)query('SELECT class_id FROM class_local_map WHERE device_id = ? AND local_id = 1', ['devB'])->fetchColumn(),
        'map B points at B'
    );

    // One local id per row, and one row per local id: the second key holds.
    expect_pdo_code(1062, function () use ($idA) {
        query('INSERT INTO class_local_map (device_id, local_id, class_id) VALUES (?,?,?)', ['devA', 2, $idA]);
    }, 'a device cannot map two local ids to one class');
});

T()->test('a reinstall does not overwrite the previous install', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd4@test.com']);
    act_as($uid);

    set_body(['device_id' => 'install-1', 'classes' => [[
        'local_id' => 1, 'subject' => 'Original', 'room' => 'R', 'professor' => 'Prof A',
        'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD,
    ]]]);
    $r1 = run_handler('sync_push');
    $originalId = $r1['body']['classes'][0]['server_id'] ?? 0;

    set_body(['device_id' => 'install-2', 'classes' => [[
        'local_id' => 1, 'subject' => 'Reinstall', 'room' => 'R', 'professor' => 'Prof A',
        'day' => 2, 'start_minutes' => 600, 'end_minutes' => 660, 'updated_at' => CLASS_UPD,
    ]]]);
    $r2 = run_handler('sync_push');
    $newId = $r2['body']['classes'][0]['server_id'] ?? 0;

    T()->truthy($newId > 0 && $newId !== $originalId, 'reinstall gets its own row');
    T()->eq('Original', fetch_one('SELECT subject FROM classes WHERE id = ?', [$originalId])['subject'], 'old install untouched');
});

T()->test('a status on a class pulled to a second device is stored', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd5@test.com']);
    act_as($uid);

    set_body(['device_id' => 'devA', 'classes' => [[
        'local_id' => 1, 'subject' => 'Shared', 'room' => 'R', 'professor' => 'Prof A',
        'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD,
    ]]]);
    $pushed = run_handler('sync_push');
    $classId = $pushed['body']['classes'][0]['server_id'] ?? 0;

    // Device B pulls the class: it has a server id but no local id for B.
    $_GET = ['device_id' => 'devB', 'since' => '1970-01-01T00:00:00.000Z'];
    set_body(null);
    $pulled = run_handler('sync_pull');
    $pulledClass = $pulled['body']['classes'][0] ?? [];
    T()->truthy(array_key_exists('local_id', $pulledClass) && $pulledClass['local_id'] === null, 'foreign device gets no local id');

    // Device B marks it, naming the class by its server id.
    set_body(['device_id' => 'devB', 'class_statuses' => [[
        'local_id' => 40, 'server_class_id' => $classId, 'local_class_id' => 1,
        'status' => 'cancelled', 'start_date' => '2026-11-16', 'end_date' => '2026-11-16',
        'updated_at' => CLASS_UPD,
    ]]]);
    $r = run_handler('sync_push');
    T()->truthy(!empty($r['body']['class_statuses']), 'status accepted');
    T()->eq(
        $classId,
        (int)query('SELECT class_id FROM class_statuses WHERE id = ?', [$r['body']['class_statuses'][0]['server_id']])->fetchColumn(),
        'status attached to the shared class'
    );
    T()->eq(
        $r['body']['class_statuses'][0]['server_id'],
        (int)query('SELECT class_status_id FROM status_local_map WHERE device_id = ? AND local_id = 40', ['devB'])->fetchColumn(),
        'status map written for device B'
    );
});

T()->test('a status on an offline class resolves through the map', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd6@test.com']);
    act_as($uid);

    set_body([
        'device_id' => 'devOffline',
        'classes' => [[
            'local_id' => 3, 'subject' => 'Offline', 'room' => 'R', 'professor' => 'Prof A',
            'day' => 3, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD,
        ]],
        'class_statuses' => [[
            'local_id' => 4, 'local_class_id' => 3, 'status' => 'finished',
            'start_date' => '2026-11-17', 'updated_at' => CLASS_UPD,
        ]],
    ]);
    $r = run_handler('sync_push');
    T()->eq(1, (int)query('SELECT COUNT(*) FROM classes')->fetchColumn(), 'class created first');
    T()->eq(1, (int)query('SELECT COUNT(*) FROM class_statuses')->fetchColumn(), 'status stored through the map');
    T()->eq(
        (int)query('SELECT class_id FROM class_local_map WHERE device_id = ? AND local_id = 3', ['devOffline'])->fetchColumn(),
        (int)query('SELECT class_id FROM class_statuses LIMIT 1')->fetchColumn(),
        'status points at the mapped class'
    );
});

T()->test('a status for another account\'s class is skipped', function () {
    db_reset();
    $a = (int)seed_user(['email' => 'nd7a@test.com']);
    $b = (int)seed_user(['email' => 'nd7b@test.com']);

    act_as($a);
    set_body(['device_id' => 'devA', 'classes' => [[
        'local_id' => 1, 'subject' => 'Private', 'room' => 'R', 'professor' => 'Prof A',
        'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD,
    ]]]);
    $classId = run_handler('sync_push')['body']['classes'][0]['server_id'] ?? 0;

    act_as($b);
    set_body(['device_id' => 'devB', 'class_statuses' => [[
        'local_id' => 9, 'server_class_id' => $classId, 'status' => 'cancelled',
        'start_date' => '2026-11-18', 'updated_at' => CLASS_UPD,
    ]]]);
    $r = run_handler('sync_push');
    T()->truthy(empty($r['body']['class_statuses']), 'foreign status not echoed');
    T()->eq(0, (int)query('SELECT COUNT(*) FROM class_statuses')->fetchColumn(), 'foreign status not stored');
});

T()->test('account deletion tombstones marks through the class and releases devices', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd8@test.com']);
    act_as($uid);
    set_body([
        'device_id' => 'devDel',
        'classes' => [[
            'local_id' => 1, 'subject' => 'Doomed', 'room' => 'R', 'professor' => 'Prof A',
            'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD,
        ]],
        'class_statuses' => [[
            'local_id' => 2, 'local_class_id' => 1, 'status' => 'finished',
            'start_date' => '2026-11-18', 'updated_at' => CLASS_UPD,
        ]],
    ]);
    run_handler('sync_push');
    T()->eq(1, (int)query('SELECT COUNT(*) FROM class_statuses')->fetchColumn(), 'mark stored');

    set_body(null);
    $r = run_handler('auth_delete_account');
    T()->eq(204, $r['status'], 'delete status');
    T()->eq(1, (int)query('SELECT deleted FROM class_statuses LIMIT 1')->fetchColumn(), 'mark tombstoned without a user_id');
    T()->eq(0, (int)query('SELECT COUNT(*) FROM sync_devices')->fetchColumn(), 'devices released');
    T()->eq(0, (int)query('SELECT COUNT(*) FROM sync_cursors')->fetchColumn(), 'cursors cascaded');
    T()->eq(0, (int)query('SELECT COUNT(*) FROM class_local_map')->fetchColumn(), 'maps cascaded');
});

T()->test('broadcast is a virtual generated column', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd9@test.com']);
    query(
        'INSERT INTO events (user_id, title, venue, event_date, start_minutes, category) VALUES (?,?,?,?,?,?)',
        [$uid, 'Personal', '', '2026-11-18', 480, 'personal']
    );
    query(
        "INSERT INTO events (user_id, title, venue, event_date, start_minutes, category) VALUES (NULL,'Broadcast','','2026-11-18',480,'school')"
    );
    T()->eq(0, (int)query('SELECT broadcast FROM events WHERE user_id = ?', [$uid])->fetchColumn(), 'owned row is personal');
    T()->eq(1, (int)query('SELECT broadcast FROM events WHERE user_id IS NULL')->fetchColumn(), 'unowned row is a broadcast');
    $extra = (string)query(
        "SELECT EXTRA FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'events' AND COLUMN_NAME = 'broadcast'"
    )->fetchColumn();
    T()->truthy(stripos($extra, 'VIRTUAL') !== false, 'generated column is VIRTUAL: ' . $extra);
});

T()->test('office key is total and a rename keeps the id', function () {
    db_reset();
    $super = (int)seed_user(['email' => 'nd10@test.com', 'role' => 'super_admin']);
    act_as($super);

    set_body(['name' => 'guidance']);
    $created = run_handler('admin_add_office');
    T()->eq(201, $created['status'], 'office created');
    $officeId = (int)$created['body']['office']['id'];

    expect_pdo_code(1062, function () {
        query("INSERT INTO office_statuses (office_name) VALUES ('guidance')");
    }, 'duplicate school-wide name rejected by the key');

    $it = seed_department('IT');
    query('INSERT INTO office_statuses (office_name, department_id) VALUES (?,?)', ['guidance', $it]);
    T()->eq(2, (int)query("SELECT COUNT(*) FROM office_statuses WHERE office_name = 'guidance'")->fetchColumn(), 'same name in a department allowed');

    set_body(['name' => 'registrar']);
    $r = run_handler('admin_rename_office', 'guidance');
    T()->eq(200, $r['status'], 'rename status');
    T()->eq(
        $officeId,
        (int)query("SELECT id FROM office_statuses WHERE office_name = 'registrar' AND department_id IS NULL")->fetchColumn(),
        'rename keeps the id'
    );
    T()->eq(0, (int)query("SELECT COUNT(*) FROM office_statuses WHERE office_name = 'guidance' AND department_id IS NULL")->fetchColumn(), 'old name gone');
});

T()->test('departments are one relation with one spelling', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd11@test.com', 'role' => 'super_admin', 'department' => 'IT']);
    seed_department('it');
    T()->eq(1, (int)query('SELECT COUNT(*) FROM departments')->fetchColumn(), 'case-insensitive single row');

    query('UPDATE departments SET name = ? WHERE id = ?', ['Information Technology', (int)query('SELECT id FROM departments LIMIT 1')->fetchColumn()]);
    act_as($uid);
    $r = run_handler('admin_list_users');
    T()->eq('Information Technology', $r['body']['users'][0]['department'] ?? null, 'rename visible on read');

    expect_pdo_code(1451, function () {
        query('DELETE FROM departments WHERE id = ?', [(int)query('SELECT id FROM departments LIMIT 1')->fetchColumn()]);
    }, 'department with dependants cannot be deleted');
});

T()->test('two forgot requests leave one row and only the newest code works', function () {
    db_reset();
    seed_user(['email' => 'nd12@test.com', 'password' => 'firstpass']);

    set_body(['email' => 'nd12@test.com']);
    run_handler('auth_forgot_password');
    $first = last_log_code();

    set_body(['email' => 'nd12@test.com']);
    run_handler('auth_forgot_password');
    $second = last_log_code();

    T()->eq(1, (int)query('SELECT COUNT(*) FROM password_resets')->fetchColumn(), 'one live code row');
    T()->eq(1, (int)query('SELECT COUNT(*) FROM password_resets WHERE ttl_seconds = 900')->fetchColumn(), 'ttl stored once');
    $columns = array_column(fetch_all("SHOW COLUMNS FROM password_resets"), 'Field');
    T()->truthy(!in_array('expires_at', $columns, true) && !in_array('used_at', $columns, true), 'no derived or dead columns');

    if ($first !== $second) {
        set_body(['email' => 'nd12@test.com', 'code' => $first, 'new_password' => 'newpass123']);
        T()->eq(422, run_handler('auth_reset_password')['status'], 'superseded code rejected');
    }
    set_body(['email' => 'nd12@test.com', 'code' => $second, 'new_password' => 'newpass123']);
    T()->eq(204, run_handler('auth_reset_password')['status'], 'newest code accepted');
    T()->eq(0, (int)query('SELECT COUNT(*) FROM password_resets')->fetchColumn(), 'code consumed');
});

T()->test('an expired code is rejected from stored facts', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd13@test.com', 'password' => 'firstpass']);
    query(
        'INSERT INTO password_resets (user_id, code_hash, created_at, ttl_seconds) VALUES (?,?,?,?)',
        [$uid, hash_password('123456'), utc_now()->modify('-16 minutes')->format('Y-m-d H:i:s.v'), 900]
    );
    set_body(['email' => 'nd13@test.com', 'code' => '123456', 'new_password' => 'newpass123']);
    $r = run_handler('auth_reset_password');
    T()->eq(422, $r['status'], '16-minute-old code rejected');
    T()->truthy(
        password_verify('firstpass', (string)query('SELECT password_hash FROM users WHERE id = ?', [$uid])->fetchColumn()),
        'password unchanged'
    );
});

T()->test('rate limiting keys on scope and subject', function () {
    db_reset();
    T()->truthy(rate_limit_allow('login', 'email:a@test.com', 1, 60), 'first hit allowed');
    T()->truthy(!rate_limit_allow('login', 'email:a@test.com', 1, 60), 'same subject limited');
    T()->truthy(rate_limit_allow('login', 'email:b@test.com', 1, 60), 'different subject independent');
    T()->eq(2, (int)query("SELECT COUNT(*) FROM rate_limit_hits WHERE scope = 'login'")->fetchColumn(), 'two scoped hits');
    $columns = array_column(fetch_all('SHOW COLUMNS FROM rate_limit_hits'), 'Field');
    T()->truthy(!in_array('bucket', $columns, true), 'no packed bucket column');
});

T()->test('sync cursors are keyed by the device only', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'nd14@test.com']);
    act_as($uid);
    set_body(['device_id' => 'cursor-dev', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    run_handler('sync_push');
    $_GET = ['device_id' => 'cursor-dev'];
    set_body(null);
    run_handler('sync_pull');
    T()->eq(1, (int)query('SELECT COUNT(*) FROM sync_cursors')->fetchColumn(), 'one cursor row per device');
    T()->truthy(
        fetch_one('SELECT last_push_at FROM sync_cursors WHERE device_id = ?', ['cursor-dev'])['last_push_at'] !== null,
        'push cursor recorded'
    );
    $columns = array_column(fetch_all('SHOW COLUMNS FROM sync_cursors'), 'Field');
    T()->truthy(!in_array('user_id', $columns, true), 'owner derived through sync_devices');
});

