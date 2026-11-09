<?php
// tests/auth_test.php
// /auth/* contract parity tests. Every test starts with a fresh database.

declare(strict_types=1);

// Placeholder suite — Step 1 pins the register shape end to end;
// the full auth battery lands with the next commit in this task chain.

T()->test('register contract shape end to end', function () {
    db_reset();
    set_body([
        'email' => 'new@test.com',
        'password' => 'min12345',
        'display_name' => 'Juan Dela Cruz',
        'department' => 'IT',
    ]);
    $r = run_handler('auth_register');

    T()->eq(201, $r['status'], 'register http status');
    T()->eq(['user', 'token', 'expires_at'], array_keys($r['body']), 'response keys');
    T()->eq('new@test.com', $r['body']['user']['email'] ?? null, 'user email echo');
    T()->eq('user', $r['body']['user']['role'] ?? null, 'default role');
    T()->eq('IT', $r['body']['user']['department'] ?? null, 'department echo');
});
