<?php
// tests/auth_test.php
// /auth/* contract parity tests (docs/sync_api_contract.md is the source of
// truth). Every test starts from a fresh database via db_reset().

declare(strict_types=1);

T()->test('register contract shape + tokens', function () {
    db_reset();
    set_body([
        'email' => 'juan@test.com',
        'password' => 'min12345',
        'display_name' => 'Juan Dela Cruz',
        'department' => 'IT',
    ]);
    $r = run_handler('auth_register');

    T()->eq(201, $r['status'], 'register http status');
    T()->eq(['user', 'token', 'expires_at'], array_keys($r['body']), 'response keys');
    T()->eq('juan@test.com', $r['body']['user']['email'], 'user email echo');
    T()->eq('Juan Dela Cruz', $r['body']['user']['display_name'], 'display name echo');
    T()->eq('user', $r['body']['user']['role'], 'default role');
    T()->eq('IT', $r['body']['user']['department'], 'department echo');
    T()->truthy(preg_match(Isozrx(), (string)$r['body']['expires_at']) === 1, 'expires_at ISO-Z millis');

    $claims = json_decode(b64url_decode(explode('.', $r['body']['token'])[1]), true);
    T()->truthy(isset($claims['user_id']) && isset($claims['email']) && isset($claims['iat']) && isset($claims['exp']), 'jwt claims present');
    T()->eq($r['body']['user']['id'], $claims['user_id'], 'jwt user_id matches');
    T()->eq(TOKEN_TTL_SECONDS, $claims['exp'] - $claims['iat'], 'jwt ttl 7 days');
});

T()->test('register department and name are optional server-side', function () {
    db_reset();
    set_body(['email' => 'bare@test.com', 'password' => 'min12345']);
    $r = run_handler('auth_register');
    T()->eq(201, $r['status'], 'bare register status');
    T()->truthy(array_key_exists('department', $r['body']['user']), 'department key present');
    T()->truthy($r['body']['user']['department'] === null, 'department null when omitted');
});

T()->test('register duplicate email 409', function () {
    db_reset();
    seed_user(['email' => 'dup@test.com']);
    set_body(['email' => 'dup@test.com', 'password' => 'min12345', 'display_name' => 'D']);
    $r = run_handler('auth_register');
    T()->eq(409, $r['status'], 'duplicate register status');
    T()->eq('EMAIL_EXISTS', $r['body']['code'] ?? null, 'duplicate register code');
});

T()->test('register over soft-deleted account 409 (unique keys across tombstones)', function () {
    db_reset();
    seed_user(['email' => 'gone@test.com', 'deleted' => 1]);
    set_body(['email' => 'gone@test.com', 'password' => 'min12345', 'display_name' => 'G']);
    $r = run_handler('auth_register');
    T()->eq(409, $r['status'], 'soft-deleted register status');
    T()->eq('EMAIL_EXISTS', $r['body']['code'] ?? null, 'soft-deleted register code');
});

T()->test('register validation errors', function () {
    db_reset();

    set_body(['email' => 'not-an-email', 'password' => 'min12345', 'display_name' => 'X']);
    $r = run_handler('auth_register');
    T()->eq(422, $r['status'], 'bad email status');
    T()->eq('VALIDATION_ERROR', $r['body']['code'] ?? null, 'bad email code');

    set_body(['email' => 'ok@test.com', 'password' => 'short', 'display_name' => 'X']);
    $r = run_handler('auth_register');
    T()->eq(422, $r['status'], 'short password status');
    T()->eq('Password must be at least 8 characters', $r['body']['error'] ?? null, 'short password message');
});

T()->test('login ok + wrong password + unknown + soft-deleted', function () {
    db_reset();
    $id = seed_user(['email' => 'login@test.com', 'password' => 'correct123']);

    set_body(['email' => 'login@test.com', 'password' => 'correct123']);
    $r = run_handler('auth_login');
    T()->eq(200, $r['status'], 'login status');
    T()->eq((int)$id, $r['body']['user']['id'], 'login user id');
    T()->truthy(preg_match(Isozrx(), (string)$r['body']['expires_at']) === 1, 'login expires_at dialect');
    T()->truthy(is_string($r['body']['token']) && $r['body']['token'] !== '', 'login token');

    set_body(['email' => 'login@test.com', 'password' => 'wrong-pass']);
    $r = run_handler('auth_login');
    T()->eq(401, $r['status'], 'wrong password status');
    T()->eq('INVALID_CREDENTIALS', $r['body']['code'] ?? null, 'wrong password code');

    set_body(['email' => 'unknown@test.com', 'password' => 'correct123']);
    $r = run_handler('auth_login');
    T()->eq(401, $r['status'], 'unknown email status');

    set_body(['email' => '', 'password' => '']);
    $r = run_handler('auth_login');
    T()->eq(422, $r['status'], 'empty login status');
    T()->eq('Email and password are required', $r['body']['error'] ?? null, 'empty login message');

    db_reset();
    seed_user(['email' => 'ghost@test.com', 'deleted' => 1]);
    set_body(['email' => 'ghost@test.com', 'password' => 'password123']);
    $r = run_handler('auth_login');
    T()->eq(401, $r['status'], 'soft-deleted login status');
});

T()->test('login accepts a bcrypt hash stored outside the harness default', function () {
    db_reset();
    seed_user([
        'email' => 'hashbase@test.com',
        'password_hash' => password_hash('oldpass', PASSWORD_BCRYPT, ['cost' => 12]),
    ]);
    set_body(['email' => 'hashbase@test.com', 'password' => 'oldpass']);
    $r = run_handler('auth_login');
    T()->eq(200, $r['status'], 'hashbase login status');
});

T()->test('refresh accepts an expired token and returns fresh role', function () {
    db_reset();
    $id = seed_user(['email' => 'reissue@test.com', 'role' => 'user']);
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . make_expired_token((int)$id, 'reissue@test.com');
    query("UPDATE users SET role = 'admin' WHERE id = ?", [$id]);
    set_body(null);
    $r = run_handler('auth_refresh');
    T()->eq(200, $r['status'], 'refresh on expired token status');
    T()->eq('admin', $r['body']['user']['role'] ?? null, 'refresh role from DB');
    T()->truthy(preg_match(Isozrx(), (string)$r['body']['expires_at']) === 1, 'refresh expires_at dialect');
});

T()->test('refresh harsh cases', function () {
    db_reset();
    seed_user(['email' => 'refreshable@test.com']);
    $token = jwt_sign_token((int)1, 'refreshable@test.com');
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $token . 'tampered';
    set_body(null);
    $r = run_handler('auth_refresh');
    T()->eq(401, $r['status'], 'garbage token status');
    T()->eq('TOKEN_EXPIRED', $r['body']['code'] ?? null, 'garbage token code');

    db_reset();
    $id = seed_user(['email' => 'tombstoned@test.com', 'deleted' => 1]);
    query('UPDATE users SET deleted = 1 WHERE id = ?', [$id]);
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . jwt_sign_token((int)$id, 'tombstoned@test.com');
    $r = run_handler('auth_refresh');
    T()->eq(401, $r['status'], 'soft-deleted refresh status');
    T()->eq('User not found', $r['body']['error'] ?? null, 'soft-deleted refresh message');
    T()->eq('TOKEN_EXPIRED', $r['body']['code'] ?? null, 'soft-deleted refresh code');
});

T()->test('me partial edits + duplicate email + empty body', function () {
    db_reset();
    $id = seed_user(['email' => 'me@test.com', 'display_name' => 'Before']);
    seed_user(['email' => 'other@test.com']);
    act_as((int)$id);
    set_body(null);

    set_body(['display_name' => 'After']);
    $r = run_handler('auth_update_me');
    T()->eq(200, $r['status'], 'me display_name status');
    T()->eq('After', $r['body']['user']['display_name'] ?? null, 'me display_name echoed');

    set_body(['email' => 'other@test.com']);
    $r = run_handler('auth_update_me');
    T()->eq(409, $r['status'], 'me email dup status');
    T()->eq('EMAIL_EXISTS', $r['body']['code'] ?? null, 'me email dup code');

    set_body([]);
    $r = run_handler('auth_update_me');
    T()->eq(422, $r['status'], 'me empty body status');
    T()->eq('Nothing to update', $r['body']['error'] ?? null, 'me empty body message');
});

T()->test('change-password cycle incl. reset-code purge', function () {
    db_reset();
    $id = seed_user(['email' => 'pw@test.com', 'password' => 'current123']);
    $row = fetch_one('SELECT id FROM users WHERE email = ? LIMIT 1', ['pw@test.com']);
    $uid = (int)$row['id'];

    // wrong current password path
    act_as($uid);
    set_body(['current_password' => 'wrong-pass', 'new_password' => 'changed123']);
    $r = run_handler('auth_change_password');
    T()->eq(401, $r['status'], 'wrong current password status');
    T()->eq('Current password is incorrect', $r['body']['error'] ?? null, 'wrong current message');

    // correct path: leaves no outstanding reset codes behind
    query("INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?,?,?)", [
        $uid, hash_password('999999'), '2100-01-01 00:00:00.000',
    ]);
    set_body(['current_password' => 'current123', 'new_password' => 'changed123']);
    $r = run_handler('auth_change_password');
    T()->eq(204, $r['status'], 'change-password status 204');
    T()->eq('', $r['raw'], 'change-password empty body');
    T()->truthy(
        fetch_one('SELECT id FROM password_resets WHERE user_id = ?', [$uid]) === null,
        'outstanding reset codes purged on password change'
    );

    act_as(0);
    set_body(['email' => 'pw@test.com', 'password' => 'changed123']);
    $r = run_handler('auth_login');
    T()->eq(200, $r['status'], 'login with NEW password');
});

T()->test('account deletion cascades tombstones', function () {
    db_reset();
    $id = seed_user(['email' => 'bye@test.com']);
    $uid = (int)$id;
    act_as($uid);
    query(
        'INSERT INTO classes (user_id, local_id, subject, room, professor, day, start_minutes, end_minutes) VALUES (?,?,?,?,?,?,?,?)',
        [$uid, 7, 'IT 101', 'L201', 'Sir A', 1, 480, 540]
    );
    query(
        'INSERT INTO events (user_id, local_id, title, venue, event_date, start_minutes, category) VALUES (?,?,?,?,?,?,?)',
        [$uid, 8, 'Quiz 1', 'L201', '2026-11-10', 600, 'school']
    );
    query(
        'INSERT INTO class_statuses (user_id, local_id, class_id, local_class_id, status, start_date, end_date) VALUES (?,?,?,?,?,?,?)',
        [$uid, 9, 1, 7, 'cancelled', '2026-11-10', '2026-11-10']
    );
    query(
        'INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?,?,?)',
        [$uid, hash_password('000000'), '2100-01-01 00:00:00.000']
    );

    set_body(null);
    $r = run_handler('auth_delete_account');
    T()->eq(204, $r['status'], 'delete account status');
    T()->eq('', $r['raw'], 'delete account empty body');
    T()->truthy((int)query('SELECT deleted FROM users WHERE id = ?', [$uid])->fetchColumn() === 1, 'users tombstone');
    T()->truthy((int)query('SELECT deleted FROM classes WHERE user_id = ?', [$uid])->fetchColumn() === 1, 'classes tombstone');
    T()->truthy((int)query('SELECT deleted FROM events WHERE user_id = ?', [$uid])->fetchColumn() === 1, 'events tombstone');
    T()->truthy((int)query('SELECT deleted FROM class_statuses WHERE user_id = ?', [$uid])->fetchColumn() === 1, 'class_statuses tombstone');
    T()->truthy(
        fetch_one('SELECT id FROM password_resets WHERE user_id = ?', [$uid]) === null,
        'password_resets purged on account delete'
    );

    act_as(0);
    set_body(['email' => 'bye@test.com', 'password' => 'password123']);
    $r = run_handler('auth_login');
    T()->eq(401, $r['status'], 'login after delete rejected');
});

T()->test('forgot + reset round trip', function () {
    db_reset();
    seed_user(['email' => 'reset@test.com', 'password' => 'firstpass']);
    set_body(['email' => 'reset@test.com']);
    $r = run_handler('auth_forgot_password');
    T()->eq(200, $r['status'], 'forgot status');
    T()->eq(['ok' => true], $r['body'], 'forgot body no-leak shape');

    $code = last_log_code();
    T()->truthy(preg_match('/^\d{6}\z/', $code) === 1, 'forgot code is 6 digits');

    set_body(['email' => 'reset@test.com', 'code' => $code, 'new_password' => 'secondpass']);
    $r = run_handler('auth_reset_password');
    T()->eq(204, $r['status'], 'reset status 204');

    set_body(['email' => 'reset@test.com', 'password' => 'secondpass']);
    $r = run_handler('auth_login');
    T()->eq(200, $r['status'], 'login with reset password');

    set_body(['email' => 'reset@test.com', 'code' => $code, 'new_password' => 'thirdpass4']);
    $r = run_handler('auth_reset_password');
    T()->eq(422, $r['status'], 'stale code rejected');
    T()->eq('The reset code is invalid or expired', $r['body']['error'] ?? null, 'stale code message');
});

T()->test('forgot for unknown email same 200 shape (no existence leak)', function () {
    db_reset();
    set_body(['email' => 'no-such-user@test.com']);
    $r = run_handler('auth_forgot_password');
    T()->eq(200, $r['status'], 'unknown forgot status');
    T()->eq(['ok' => true], $r['body'], 'unknown forgot body identical');
});

T()->test('forgot rate limit 429 (5 per email, forgot: bucket)', function () {
    db_reset();
    seed_user(['email' => 'throttle@test.com']);
    $statuses = [];
    for ($i = 0; $i < 6; $i++) {
        set_body(['email' => 'throttle@test.com']);
        $statuses[] = run_handler('auth_forgot_password')['status'];
    }
    T()->eq([200, 200, 200, 200, 200, 429], $statuses, 'forgot throttle sequence');
    set_body(['email' => 'throttle@test.com']);
    $r = run_handler('auth_forgot_password');
    T()->eq('RATE_LIMITED', $r['body']['code'] ?? null, 'forgot throttle code');
});

T()->test('google rate limit 429 (30 per minute, google bucket)', function () {
    db_reset();
    $statuses = [];
    for ($i = 0; $i < 31; $i++) {
        set_body(['id_token' => 'x']);
        $statuses[] = run_handler('auth_google')['status'];
    }
    $first30 = array_slice($statuses, 0, 30);
    T()->truthy(max($first30) === 401 && min($first30) === 401, 'first 30 google calls 401');
    T()->eq(429, $statuses[30], '31st google call throttled');
});

/// ISO-8601 with milliseconds + Z (the sync/auth dialect).
function Isozrx(): string
{
    return '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/';
}
