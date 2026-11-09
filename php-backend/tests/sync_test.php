<?php
// tests/sync_test.php
// /sync/push + /sync/pull contract parity tests.

declare(strict_types=1);

const CLASS_UPD = '2026-11-01T08:00:00.123Z';     // client dialect (ISO-Z millis)
const CLASS_UPD_DB = '2026-11-01 08:00:00.123';  // server dialect (raw DATETIME(3))

T()->test('push inserts class and echoes client timestamp verbatim', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c1a@test.com']);
    act_as($uid);
    set_body([
        'device_id' => 'dev1',
        'classes' => [[
            'local_id' => 1,
            'subject' => 'IT 101',
            'room' => 'L201',
            'professor' => 'Sir A',
            'day' => 1,
            'start_minutes' => 480,
            'end_minutes' => 540,
            'deleted' => false,
            'updated_at' => CLASS_UPD,
        ]],
        'events' => [],
        'class_statuses' => [],
    ]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'push status');
    T()->eq(['local_id' => 1, 'server_id' => 1, 'updated_at' => CLASS_UPD], $r['body']['classes'][0] ?? null, 'class echo verbatim');
    $row = fetch_one('SELECT local_id, subject, updated_at, deleted FROM classes WHERE id = 1');
    T()->eq('IT 101', $row['subject'], 'class stored subject');
    T()->eq(CLASS_UPD_DB, $row['updated_at'], 'class stored UTC timestamp');
    T()->truthy((int)$row['deleted'] === 0, 'class not deleted');
    T()->truthy((int)$row['local_id'] === 1, 'class local_id stored');
});

T()->test('push updates row by server id then by local id', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c2a@test.com']);
    act_as($uid);

    set_body(['classes' => [['local_id' => 1, 'subject' => 'V1', 'room' => 'R', 'professor' => 'Prof A', 'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD]]]);
    $r1 = run_handler('sync_push');
    T()->eq(200, $r1['status'], 'first push status');
    T()->eq(1, $r1['body']['classes'][0]['server_id'] ?? null, 'first push server id');

    $sid = $r1['body']['classes'][0]['server_id'];
    set_body(['classes' => [['server_id' => $sid, 'local_id' => 1, 'subject' => 'V2', 'room' => 'R', 'professor' => 'Prof A', 'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD]]]);
    $r2 = run_handler('sync_push');
    T()->eq(200, $r2['status'], 'second push status');
    T()->eq($sid, $r2['body']['classes'][0]['server_id'] ?? null, 'update by server id keeps id');
    T()->eq('V2', fetch_one('SELECT subject FROM classes WHERE id = ?', [$sid])['subject'], 'update by server id applied');

    set_body(['classes' => [['local_id' => 1, 'subject' => 'V3', 'room' => 'R', 'professor' => 'Prof A', 'day' => 1, 'start_minutes' => 480, 'end_minutes' => 540, 'updated_at' => CLASS_UPD]]]);
    $r3 = run_handler('sync_push');
    T()->eq(200, $r3['status'], 'third push status');
    T()->eq($sid, $r3['body']['classes'][0]['server_id'] ?? null, 'update by local id keeps id');
    T()->eq('V3', fetch_one('SELECT subject FROM classes WHERE id = ?', [$sid])['subject'], 'update by local id applied');
});

T()->test('push tombstone deletes class', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c3a@test.com']);
    act_as($uid);
    set_body([
        'classes' => [[
            'local_id' => 3, 'subject' => 'Subj', 'room' => 'R', 'professor' => 'Prof A',
            'day' => 2, 'start_minutes' => 600, 'end_minutes' => 660,
            'deleted' => true, 'updated_at' => CLASS_UPD,
        ]],
        'events' => [],
        'class_statuses' => [],
    ]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'tombstone push status');
    T()->truthy((int)fetch_one('SELECT deleted FROM classes WHERE id = 1')['deleted'] === 1, 'tombstone stored');
});

T()->test('push events: personal demote, admin broadcast, superadmin school-wide', function () {
    db_reset();
    $uidUser = (int)seed_user(['email' => 'c4a@test.com', 'role' => 'user', 'department' => 'IT']);
    act_as($uidUser);

    // Non-admin wants to broadcast is demoted to personal.
    set_body([ 'events' => [
        ['local_id' => 10, 'title' => 'Announce', 'venue' => 'V', 'event_date' => '2026-11-11', 'start_minutes' => 480,
            'category' => 'school', 'broadcast' => true, 'department' => 'IT', 'reminder_enabled' => true, 'lead_minutes' => 15,
            'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'demote push status');
    $row = fetch_one('SELECT user_id, broadcast, department FROM events WHERE id = 1');
    T()->truthy((int)$row['user_id'] === $uidUser, 'demoted event stays personal (user_id set)');
    T()->truthy((int)$row['broadcast'] === 0, 'demoted event broadcast=0');
    T()->truthy($row['department'] === null, 'demoted event department=null');
    // Actually the lead_minutes=15 option set is stored as int(15)
    T()->truthy((int)fetch_one('SELECT lead_minutes FROM events WHERE id = 1')['lead_minutes'] === 15, 'lead 15 stored');

    // Department admin broadcasts to own dept regardless of requested department.
    $uidDeptAdmin = (int)seed_user(['email' => 'c4b@test.com', 'role' => 'admin', 'department' => 'IT']);
    act_as($uidDeptAdmin);
    set_body(['events' => [
        ['local_id' => 11, 'title' => 'IT Broadcast', 'venue' => 'C', 'event_date' => '2026-11-12', 'start_minutes' => 900,
            'category' => 'school', 'broadcast' => true, 'department' => 'EDUC', 'reminder_enabled' => false, 'lead_minutes' => 30,
            'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'dept admin push status');
    $row = fetch_one('SELECT user_id, broadcast, department FROM events WHERE id = 2');
    T()->truthy($row['user_id'] === null, 'broadcast row user_id NULL');
    T()->truthy((int)$row['broadcast'] === 1, 'broadcast flag stored');
    T()->eq('IT', $row['department'], 'dept admin broadcast pinned to OWN dept');

    // Super admin may school-wide broadcast (department absent -> NULL).
    $uidSuper = (int)seed_user(['email' => 'c4c@test.com', 'role' => 'super_admin']);
    act_as($uidSuper);
    set_body(['events' => [
        ['local_id' => 12, 'title' => 'School Broadcast', 'venue' => 'C', 'event_date' => '2026-11-13', 'start_minutes' => 1020,
            'category' => 'school', 'broadcast' => true, 'department' => null, 'reminder_enabled' => true, 'lead_minutes' => 10,
            'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'super admin push status');
    $row = fetch_one('SELECT user_id, department FROM events WHERE id = 3');
    T()->truthy($row['user_id'] === null, 'school-wide user_id NULL');
    T()->truthy($row['department'] === null, 'school-wide department NULL');
});

T()->test('push lead_minutes outside [5,10,15,30] row skipped', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c5bad@test.com']);
    act_as($uid);
    set_body(['events' => [
        ['local_id' => 14, 'title' => 'Bad lead', 'venue' => 'V', 'event_date' => '2026-11-14', 'start_minutes' => 480,
            'category' => 'personal', 'broadcast' => false, 'reminder_enabled' => true, 'lead_minutes' => 99, 'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'bad lead push status');
    T()->truthy(empty($r['body']['events']), 'skipped event not echoed');
    T()->truthy(
        fetch_one('SELECT id FROM events WHERE local_id = 14') === null,
        'bad lead row not stored'
    );
});

T()->test('push foreign broadcast event skipped (echoed with foreign server id)', function () {
    db_reset();
    $otherId = (int)seed_user(['email' => 'c6owner@test.com', 'role' => 'super_admin']);
    // Seed a broadcast row the caller can never edit.
    query(
        'INSERT INTO events (user_id, local_id, title, venue, event_date, start_minutes, category, department, broadcast) VALUES (?,?,?,?,?,?,?,?,?)',
        [null, 7, 'Owned Broadcast', 'X', '2026-11-15', 480, 'school', 'EDUC', 1]
    );
    $bridgeId = (int)db()->lastInsertId();

    $uid = (int)seed_user(['email' => 'c6caller@test.com', 'department' => 'IT']);
    act_as($uid);
    // Override the ROW by its server id -> must be skipped.
    set_body(['events' => [
        ['server_id' => $bridgeId, 'local_id' => 20, 'title' => 'Hijack Attempt', 'venue' => 'H', 'event_date' => '2026-11-15',
            'start_minutes' => 480, 'category' => 'personal', 'user_id' => $uid, 'broadcast' => false, 'reminder_enabled' => false, 'lead_minutes' => 30,
            'deleted' => false, 'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'foreign push status');
    $entry = $r['body']['events'][0] ?? null;
    T()->truthy(is_array($entry), 'foreign push echoed (this is Node-parity behavior)');
    T()->eq($bridgeId, $entry['server_id'] ?? null, 'echoed foreign server id');
    T()->eq('Owned Broadcast', fetch_one("SELECT title FROM events WHERE id = ?", [$bridgeId])['title'], 'broadcast title NOT overwritten');
    T()->truthy(
        (int)query('SELECT COUNT(*) FROM events WHERE title = ? AND user_id = ?', ['Hijack Attempt', $uid])->fetchColumn() === 0,
        'caller did not gain a personal copy'
    );
});

T()->test('push status row skip when class unknown', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c7a@test.com']);
    act_as($uid);
    set_body(['classes' => [], 'events' => [], 'class_statuses' => [
        ['local_id' => 30, 'local_class_id' => 999, 'status' => 'cancelled',
            'start_date' => '2026-11-16', 'end_date' => '2026-11-16', 'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'unknown-class push status');
    T()->truthy(empty($r['body']['class_statuses']), 'unknown class echo skipped');
    T()->truthy(
        fetch_one('SELECT id FROM class_statuses WHERE local_id = 30') === null,
        'unknown class status not stored'
    );

    // After the class exists, the same push succeeds.
    query(
        'INSERT INTO classes (user_id, local_id, subject, room, professor, day, start_minutes, end_minutes) VALUES (?,?,?,?,?,?,?,?)',
        [$uid, 999, 'PreExist', 'R', 'P', 3, 480, 540]
    );
    set_body(['classes' => [], 'events' => [], 'class_statuses' => [
        ['local_id' => 30, 'local_class_id' => 999, 'status' => 'cancelled',
            'start_date' => '2026-11-16', 'end_date' => '2026-11-16', 'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'known-class push status');
    $entry = $r['body']['class_statuses'][0] ?? null;
    T()->truthy(is_array($entry), 'known class status echoed');
    T()->truthy((int)($entry['server_id'] ?? 0) > 0, 'known class status server id assigned');
    T()->truthy((int)fetch_one('SELECT class_id FROM class_statuses WHERE local_id = 30')['class_id'] > 0, 'status class_id resolved');
});

T()->test('push cursor upsert per user+device', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c8a@test.com']);
    act_as($uid);
    set_body(['device_id' => 'phA', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    run_handler('sync_push');
    set_body(['device_id' => 'phB', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    run_handler('sync_push');
    T()->truthy(
        (int)query('SELECT COUNT(*) FROM sync_cursors WHERE user_id = ?', [$uid])->fetchColumn() === 2,
        'two cursors after two devices'
    );

    // Missing device_id defaults to 'unknown' (js_string at sync.php:336)
    set_body(null);
    run_handler('sync_push');
    $row = fetch_one('SELECT device_id FROM sync_cursors WHERE user_id = ? AND device_id = ?', [$uid, 'unknown']);
    T()->truthy(is_array($row), 'default device_id stored');
});

T()->test('pull on empty database + default since', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c9a@test.com']);
    act_as($uid);
    $_GET = [];
    set_body(null);
    $r = run_handler('sync_pull');
    T()->eq(200, $r['status'], 'pull status');
    T()->eq(['server_time', 'classes', 'events', 'class_statuses', 'office_statuses'], array_keys($r['body']), 'pull keys');
    T()->truthy(preg_match(Isozrx(), (string)$r['body']['server_time']) === 1, 'pull server_time dialect');
    T()->eq([], $r['body']['classes'], 'pull classes empty');
    T()->truthy(
        (int)query('SELECT COUNT(*) FROM sync_cursors WHERE user_id = ?', [$uid])->fetchColumn() === 1,
        'pull cursor upserted'
    );
});

T()->test('pull since inclusive and deleted rows visible', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c9b@test.com']);
    act_as($uid);
    query(
        'INSERT INTO classes (user_id, local_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [$uid, 40, 'Old', 'R', 'P', 1, 480, 540, 1, '2026-01-01 08:00:00.000']
    );
    query(
        'INSERT INTO classes (user_id, local_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [$uid, 41, 'Mid', 'R', 'P', 1, 600, 660, 0, '2026-01-01 08:01:00.000']
    );

    // Since 0: both visible, deleted included.
    $_GET = ['since' => '1970-01-01T00:00:00.000Z'];
    $r = run_handler('sync_pull');
    T()->eq(200, $r['status'], 'pull-all status');
    T()->truthy(count($r['body']['classes'] ?? []) === 2, 'both classes pulled');
    T()->truthy(
        !empty(array_filter($r['body']['classes'], fn (array $x) => $x['deleted'] === true)),
        'tombstone included in delta'
    );
    $row = $r['body']['classes'][0];
    T()->truthy(preg_match(Isozrx(), (string)$row['updated_at']) === 1, 'delta updated_at dialect ISO-Z');

    // Since row2's updated_at (inclusive): only row2 again.
    $_GET = ['since' => '2026-01-01T08:01:00.000Z'];
    $r = run_handler('sync_pull');
    T()->truthy(count($r['body']['classes'] ?? []) === 1, 'inclusive since pulls row2');
    T()->eq('Mid', $r['body']['classes'][0]['subject'] ?? null, 'inclusive since only row2');
});

T()->test('pull office rows scoped to caller dept', function () {
    db_reset();
    seed_user(['email' => 'c9c-owner@test.com']);
    query("INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (1,'guidance',NULL,'open',NULL)");
    query("INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (1,'guidance','IT','break','lunch')");
    query("INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (1,'registrar','EDUC','open',NULL)");

    $uid = (int)seed_user(['email' => 'c9c@test.com', 'department' => 'IT']);
    act_as($uid);
    $_GET = ['since' => '1970-01-01T00:00:00.000Z'];
    $r = run_handler('sync_pull');
    $offices = array_column($r['body']['office_statuses'] ?? [], 'office_name', 'department');
    T()->truthy(count($offices) === 2, 'only NULL-dept + own-dept offices pulled');
    T()->truthy(isset($offices['IT']), 'own-dept office pulled');

    $uidEd = (int)seed_user(['email' => 'c9c-educ@test.com', 'department' => 'EDUC']);
    act_as($uidEd);
    $r = run_handler('sync_pull');
    $offices = array_column($r['body']['office_statuses'] ?? [], 'office_name', 'department');
    T()->truthy(count($offices) === 2, 'EDUC caller sees NULL-dept + own');
    T()->truthy(isset($offices['EDUC']) && !isset($offices['IT']), 'EDUC sees own + school-wide only');
});

T()->test('pull broadcasts by dept', function () {
    db_reset();
    seed_user(['email' => 'c9d-owner@test.com']);
    query(
        "INSERT INTO events (user_id, local_id, title, venue, event_date, start_minutes, category, department, broadcast) VALUES (NULL, 50, 'IT Broadcast', 'V', '2026-11-17', 480, 'school', 'IT', 1)"
    );
    $uidIt = (int)seed_user(['email' => 'c9d-it@test.com', 'department' => 'IT']);
    act_as($uidIt);
    $_GET = ['since' => '1970-01-01T00:00:00.000Z'];
    $r = run_handler('sync_pull');
    $titles = array_column($r['body']['events'] ?? [], 'title');
    T()->truthy(in_array('IT Broadcast', $titles, true), 'IT caller sees IT broadcast');

    $uidEd = (int)seed_user(['email' => 'c9d-educ@test.com', 'department' => 'EDUC']);
    act_as($uidEd);
    $r = run_handler('sync_pull');
    $titles = array_column($r['body']['events'] ?? [], 'title');
    T()->truthy(!in_array('IT Broadcast', $titles, true), 'EDUC caller cannot see IT broadcast');
});

T()->test('unauthenticated syncs 401', function () {
    db_reset();
    seed_user(['email' => 'c9e@test.com']);
    act_as(0);
    set_body(null);
    $_GET = [];
    $r = run_handler('sync_pull');
    T()->eq(401, $r['status'], 'pull unauthorized status');
    T()->eq('UNAUTHORIZED', $r['body']['code'] ?? null, 'pull unauthorized code');

    set_body(['classes' => [], 'events' => [], 'class_statuses' => []]);
    $r = run_handler('sync_push');
    T()->eq(401, $r['status'], 'push unauthorized status');
});
