<?php
// tests/sync_test.php
// /sync/push + /sync/pull contract parity tests.

declare(strict_types=1);

const CLASS_UPD = '2026-11-01T08:00:00.123Z';     // client dialect (ISO-Z millis)
const CLASS_UPD_DB = '2026-11-01 08:00:00.123';  // server dialect (raw DATETIME(3))

/// A class push row with the fields the server validates.
function class_row(int $localId, string $subject, array $overrides = []): array
{
    return array_merge([
        'local_id' => $localId,
        'subject' => $subject,
        'room' => 'R',
        'professor' => 'Prof A',
        'day' => 1,
        'start_minutes' => 480,
        'end_minutes' => 540,
        'deleted' => false,
        'updated_at' => CLASS_UPD,
    ], $overrides);
}

/// Department name for an event row (the wire keeps names, the DB keeps ids).
function event_department_name(int $eventId): ?string
{
    $row = fetch_one(
        'SELECT d.name AS department FROM events e LEFT JOIN departments d ON d.id = e.department_id WHERE e.id = ?',
        [$eventId]
    );
    return $row['department'] ?? null;
}

T()->test('push inserts class, stores the map, and echoes the client timestamp', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c1a@test.com']);
    act_as($uid);
    set_body([
        'device_id' => 'dev1',
        'classes' => [class_row(1, 'IT 101', ['room' => 'L201'])],
        'events' => [],
        'class_statuses' => [],
    ]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'push status');
    T()->eq(['local_id' => 1, 'server_id' => 1, 'updated_at' => CLASS_UPD], $r['body']['classes'][0] ?? null, 'class echo verbatim');
    $row = fetch_one('SELECT subject, updated_at, deleted FROM classes WHERE id = 1');
    T()->eq('IT 101', $row['subject'], 'class stored subject');
    T()->eq(CLASS_UPD_DB, $row['updated_at'], 'class stored UTC timestamp');
    T()->truthy((int)$row['deleted'] === 0, 'class not deleted');
    T()->eq(
        1,
        (int)query('SELECT COUNT(*) FROM class_local_map WHERE device_id = ? AND local_id = 1 AND class_id = 1', ['dev1'])->fetchColumn(),
        'local id lives in the map, not the entity'
    );
});

T()->test('push updates row by server id then by local id', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c2a@test.com']);
    act_as($uid);

    set_body(['device_id' => 'dev2', 'classes' => [class_row(1, 'V1')]]);
    $r1 = run_handler('sync_push');
    T()->eq(200, $r1['status'], 'first push status');
    T()->eq(1, $r1['body']['classes'][0]['server_id'] ?? null, 'first push server id');

    $sid = $r1['body']['classes'][0]['server_id'];
    set_body(['device_id' => 'dev2', 'classes' => [class_row(1, 'V2', ['server_id' => $sid])]]);
    $r2 = run_handler('sync_push');
    T()->eq(200, $r2['status'], 'second push status');
    T()->eq($sid, $r2['body']['classes'][0]['server_id'] ?? null, 'update by server id keeps id');
    T()->eq('V2', fetch_one('SELECT subject FROM classes WHERE id = ?', [$sid])['subject'], 'update by server id applied');

    set_body(['device_id' => 'dev2', 'classes' => [class_row(1, 'V3')]]);
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
        'device_id' => 'dev3',
        'classes' => [class_row(3, 'Subj', ['day' => 2, 'start_minutes' => 600, 'end_minutes' => 660, 'deleted' => true])],
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
    set_body(['device_id' => 'dev4', 'events' => [
        ['local_id' => 10, 'title' => 'Announce', 'venue' => 'V', 'event_date' => '2026-11-11', 'start_minutes' => 480,
            'category' => 'school', 'broadcast' => true, 'department' => 'IT', 'reminder_enabled' => true, 'lead_minutes' => 15,
            'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'demote push status');
    $row = fetch_one('SELECT user_id, broadcast, department_id FROM events WHERE id = 1');
    T()->truthy((int)$row['user_id'] === $uidUser, 'demoted event stays personal (user_id set)');
    T()->truthy((int)$row['broadcast'] === 0, 'demoted event broadcast=0');
    T()->truthy($row['department_id'] === null, 'demoted event department=null');
    T()->truthy((int)fetch_one('SELECT lead_minutes FROM events WHERE id = 1')['lead_minutes'] === 15, 'lead 15 stored');

    // Department admin broadcasts to own dept regardless of requested department.
    $uidDeptAdmin = (int)seed_user(['email' => 'c4b@test.com', 'role' => 'admin', 'department' => 'IT']);
    act_as($uidDeptAdmin);
    set_body(['device_id' => 'dev4b', 'events' => [
        ['local_id' => 11, 'title' => 'IT Broadcast', 'venue' => 'C', 'event_date' => '2026-11-12', 'start_minutes' => 900,
            'category' => 'school', 'broadcast' => true, 'department' => 'EDUC', 'reminder_enabled' => false, 'lead_minutes' => 30,
            'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'dept admin push status');
    $row = fetch_one('SELECT user_id, broadcast FROM events WHERE id = 2');
    T()->truthy($row['user_id'] === null, 'broadcast row user_id NULL');
    T()->truthy((int)$row['broadcast'] === 1, 'broadcast flag derived');
    T()->eq('IT', event_department_name(2), 'dept admin broadcast pinned to OWN dept');

    // Super admin may school-wide broadcast (department absent -> NULL).
    $uidSuper = (int)seed_user(['email' => 'c4c@test.com', 'role' => 'super_admin']);
    act_as($uidSuper);
    set_body(['device_id' => 'dev4c', 'events' => [
        ['local_id' => 12, 'title' => 'School Broadcast', 'venue' => 'C', 'event_date' => '2026-11-13', 'start_minutes' => 1020,
            'category' => 'school', 'broadcast' => true, 'department' => null, 'reminder_enabled' => true, 'lead_minutes' => 10,
            'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'super admin push status');
    $row = fetch_one('SELECT user_id, department_id FROM events WHERE id = 3');
    T()->truthy($row['user_id'] === null, 'school-wide user_id NULL');
    T()->truthy($row['department_id'] === null, 'school-wide department NULL');
});

T()->test('push lead_minutes outside [5,10,15,30] row skipped', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c5bad@test.com']);
    act_as($uid);
    set_body(['device_id' => 'dev5', 'events' => [
        ['local_id' => 14, 'title' => 'Bad lead', 'venue' => 'V', 'event_date' => '2026-11-14', 'start_minutes' => 480,
            'category' => 'personal', 'broadcast' => false, 'reminder_enabled' => true, 'lead_minutes' => 99, 'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'bad lead push status');
    T()->truthy(empty($r['body']['events']), 'skipped event not echoed');
    T()->truthy(
        (int)query('SELECT COUNT(*) FROM events')->fetchColumn() === 0,
        'bad lead row not stored, no map written'
    );
});

T()->test('push foreign broadcast event skipped (echoed with foreign server id)', function () {
    db_reset();
    $otherId = (int)seed_user(['email' => 'c6owner@test.com', 'role' => 'super_admin']);
    $educ = seed_department('EDUC');
    // Seed a broadcast row the caller can never edit.
    query(
        'INSERT INTO events (user_id, title, venue, event_date, start_minutes, category, department_id) VALUES (?,?,?,?,?,?,?)',
        [null, 'Owned Broadcast', 'X', '2026-11-15', 480, 'school', $educ]
    );
    $bridgeId = (int)db()->lastInsertId();

    $uid = (int)seed_user(['email' => 'c6caller@test.com', 'department' => 'IT']);
    act_as($uid);
    // Override the ROW by its server id -> must be skipped.
    set_body(['device_id' => 'dev6', 'events' => [
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

T()->test('push status row skip when class unknown, then resolves through the map', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c7a@test.com']);
    act_as($uid);
    set_body(['device_id' => 'dev7', 'classes' => [], 'events' => [], 'class_statuses' => [
        ['local_id' => 30, 'local_class_id' => 999, 'status' => 'cancelled',
            'start_date' => '2026-11-16', 'end_date' => '2026-11-16', 'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'unknown-class push status');
    T()->truthy(empty($r['body']['class_statuses']), 'unknown class echo skipped');
    T()->eq(0, (int)query('SELECT COUNT(*) FROM class_statuses')->fetchColumn(), 'unknown class status not stored');

    // The class exists on this device: a push creates the map, then the same
    // status resolves through it.
    set_body(['device_id' => 'dev7', 'classes' => [class_row(999, 'PreExist', ['day' => 3])]]);
    run_handler('sync_push');

    set_body(['device_id' => 'dev7', 'classes' => [], 'events' => [], 'class_statuses' => [
        ['local_id' => 30, 'local_class_id' => 999, 'status' => 'cancelled',
            'start_date' => '2026-11-16', 'end_date' => '2026-11-16', 'updated_at' => CLASS_UPD],
    ]]);
    $r = run_handler('sync_push');
    T()->eq(200, $r['status'], 'known-class push status');
    $entry = $r['body']['class_statuses'][0] ?? null;
    T()->truthy(is_array($entry), 'known class status echoed');
    T()->truthy((int)($entry['server_id'] ?? 0) > 0, 'known class status server id assigned');
    $statusId = (int)$entry['server_id'];
    T()->truthy((int)fetch_one('SELECT class_id FROM class_statuses WHERE id = ?', [$statusId])['class_id'] > 0, 'status class_id resolved');
    T()->eq(
        $statusId,
        (int)query('SELECT class_status_id FROM status_local_map WHERE device_id = ? AND local_id = 30', ['dev7'])->fetchColumn(),
        'status map written'
    );
});

T()->test('push cursor upsert per device', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c8a@test.com']);
    act_as($uid);
    set_body(['device_id' => 'phA', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    run_handler('sync_push');
    set_body(['device_id' => 'phB', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    run_handler('sync_push');
    T()->eq(2, (int)query('SELECT COUNT(*) FROM sync_cursors')->fetchColumn(), 'two cursors after two devices');
    T()->eq(
        2,
        (int)query('SELECT COUNT(*) FROM sync_devices WHERE user_id = ?', [$uid])->fetchColumn(),
        'both devices registered to the caller'
    );

    // A missing id is a contract error now, not an 'unknown' bucket.
    set_body(['classes' => [], 'events' => [], 'class_statuses' => []]);
    $r = run_handler('sync_push');
    T()->eq(422, $r['status'], 'missing device_id rejected');
    T()->eq(2, (int)query('SELECT COUNT(*) FROM sync_cursors')->fetchColumn(), 'rejected push wrote no cursor');
});

T()->test('pull on empty database + default since', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c9a@test.com']);
    act_as($uid);
    $_GET = ['device_id' => 'pullA'];
    set_body(null);
    $r = run_handler('sync_pull');
    T()->eq(200, $r['status'], 'pull status');
    T()->eq(['server_time', 'classes', 'events', 'class_statuses', 'office_statuses'], array_keys($r['body']), 'pull keys');
    T()->truthy(preg_match(Isozrx(), (string)$r['body']['server_time']) === 1, 'pull server_time dialect');
    T()->eq([], $r['body']['classes'], 'pull classes empty');
    T()->eq(1, (int)query('SELECT COUNT(*) FROM sync_cursors WHERE device_id = ?', ['pullA'])->fetchColumn(), 'pull cursor upserted');
});

T()->test('pull since inclusive, deleted rows visible, local id scoped to device', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c9b@test.com']);
    act_as($uid);
    query(
        'INSERT INTO classes (user_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
        [$uid, 'Old', 'R', 'P', 1, 480, 540, 1, '2026-01-01 08:00:00.000']
    );
    query(
        'INSERT INTO classes (user_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
        [$uid, 'Mid', 'R', 'P', 1, 600, 660, 0, '2026-01-01 08:01:00.000']
    );

    // Since 0: both visible, deleted included.
    $_GET = ['device_id' => 'pullB', 'since' => '1970-01-01T00:00:00.000Z'];
    $r = run_handler('sync_pull');
    T()->eq(200, $r['status'], 'pull-all status');
    T()->eq(2, count($r['body']['classes'] ?? []), 'both classes pulled');
    T()->truthy(
        !empty(array_filter($r['body']['classes'], fn (array $x) => $x['deleted'] === true)),
        'tombstone included in delta'
    );
    $row = $r['body']['classes'][0];
    T()->truthy(preg_match(Isozrx(), (string)$row['updated_at']) === 1, 'delta updated_at dialect ISO-Z');
    T()->truthy(array_key_exists('local_id', $row) && $row['local_id'] === null, 'a device that never pushed sees no local id');

    // Since row2's updated_at (inclusive): only row2 again.
    $_GET = ['device_id' => 'pullB', 'since' => '2026-01-01T08:01:00.000Z'];
    $r = run_handler('sync_pull');
    T()->eq(1, count($r['body']['classes'] ?? []), 'inclusive since pulls row2');
    T()->eq('Mid', $r['body']['classes'][0]['subject'] ?? null, 'inclusive since only row2');
});

T()->test('pull office rows scoped to caller dept', function () {
    db_reset();
    seed_user(['email' => 'c9c-owner@test.com']);
    $it = seed_department('IT');
    $educ = seed_department('EDUC');
    query("INSERT INTO office_statuses (user_id, office_name, department_id, status, custom_message) VALUES (1,'guidance',NULL,'open',NULL)");
    query("INSERT INTO office_statuses (user_id, office_name, department_id, status, custom_message) VALUES (1,'guidance',?,'break','lunch')", [$it]);
    query("INSERT INTO office_statuses (user_id, office_name, department_id, status, custom_message) VALUES (1,'registrar',?,'open',NULL)", [$educ]);

    $uid = (int)seed_user(['email' => 'c9c@test.com', 'department' => 'IT']);
    act_as($uid);
    $_GET = ['device_id' => 'office-it', 'since' => '1970-01-01T00:00:00.000Z'];
    $r = run_handler('sync_pull');
    $offices = array_column($r['body']['office_statuses'] ?? [], 'office_name', 'department');
    T()->eq(2, count($offices), 'only NULL-dept + own-dept offices pulled');
    T()->truthy(isset($offices['IT']), 'own-dept office pulled');

    $uidEd = (int)seed_user(['email' => 'c9c-educ@test.com', 'department' => 'EDUC']);
    act_as($uidEd);
    $_GET = ['device_id' => 'office-educ'];
    $r = run_handler('sync_pull');
    $offices = array_column($r['body']['office_statuses'] ?? [], 'office_name', 'department');
    T()->eq(2, count($offices), 'EDUC caller sees NULL-dept + own');
    T()->truthy(isset($offices['EDUC']) && !isset($offices['IT']), 'EDUC sees own + school-wide only');
});

T()->test('pull offices is not filtered by since', function () {
    db_reset();
    $uid = (int)seed_user(['email' => 'c9c2@test.com']);
    act_as($uid);
    query("INSERT INTO office_statuses (office_name, updated_at) VALUES ('guidance', '2020-01-01 00:00:00.000')");
    $_GET = ['device_id' => 'office-since', 'since' => '2026-01-01T00:00:00.000Z'];
    $r = run_handler('sync_pull');
    T()->eq(1, count($r['body']['office_statuses'] ?? []), 'old office still delivered in full');
});

T()->test('pull broadcasts by dept', function () {
    db_reset();
    seed_user(['email' => 'c9d-owner@test.com']);
    $it = seed_department('IT');
    query(
        'INSERT INTO events (user_id, title, venue, event_date, start_minutes, category, department_id) VALUES (NULL,?,?,?,?,?,?)',
        ['IT Broadcast', 'V', '2026-11-17', 480, 'school', $it]
    );
    $uidIt = (int)seed_user(['email' => 'c9d-it@test.com', 'department' => 'IT']);
    act_as($uidIt);
    $_GET = ['device_id' => 'bc-it', 'since' => '1970-01-01T00:00:00.000Z'];
    $r = run_handler('sync_pull');
    $titles = array_column($r['body']['events'] ?? [], 'title');
    T()->truthy(in_array('IT Broadcast', $titles, true), 'IT caller sees IT broadcast');

    $uidEd = (int)seed_user(['email' => 'c9d-educ@test.com', 'department' => 'EDUC']);
    act_as($uidEd);
    $_GET = ['device_id' => 'bc-educ'];
    $r = run_handler('sync_pull');
    $titles = array_column($r['body']['events'] ?? [], 'title');
    T()->truthy(!in_array('IT Broadcast', $titles, true), 'EDUC caller cannot see IT broadcast');
});

T()->test('unauthenticated syncs 401', function () {
    db_reset();
    seed_user(['email' => 'c9e@test.com']);
    act_as(0);
    set_body(null);
    $_GET = ['device_id' => 'anon'];
    $r = run_handler('sync_pull');
    T()->eq(401, $r['status'], 'pull unauthorized status');
    T()->eq('UNAUTHORIZED', $r['body']['code'] ?? null, 'pull unauthorized code');

    set_body(['device_id' => 'anon', 'classes' => [], 'events' => [], 'class_statuses' => []]);
    $r = run_handler('sync_push');
    T()->eq(401, $r['status'], 'push unauthorized status');
});
