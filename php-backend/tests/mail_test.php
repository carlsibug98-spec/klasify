<?php
// tests/mail_test.php
// Password-reset delivery: message construction, transport selection, and a
// real SMTP round trip against tests/smtp_capture_server.php. The existing
// auth tests cover the log transport used in development.

/// Sets (or with null, unsets) mail-related environment variables.
function mail_env(array $values): void
{
    foreach ($values as $key => $value) {
        putenv($value === null ? $key : $key . '=' . $value);
    }
}

T()->test('reset email sanitizes headers and dot-stuffs the body', function () {
    $settings = [
        'from' => "no-reply@klasify.test\r\nBcc: evil@example.com",
        'from_name' => "Klasify\r\nBcc: evil@example.com",
    ];
    $message = smtp_build_message(
        $settings,
        "student@test.com\r\nBcc: evil@example.com",
        "Your code\r\nBcc: evil@example.com",
        ".hidden first line\nsecond line"
    );

    $parts = explode("\r\n\r\n", $message, 2);
    T()->truthy(count($parts) === 2, 'message has headers and body');
    T()->truthy(!str_contains($parts[0], "\r\nBcc:"), 'no injected header');
    T()->truthy(
        str_starts_with($parts[1], "..hidden first line\r\n"),
        'leading dot is stuffed so DATA cannot end early'
    );
    T()->truthy(str_contains($parts[0], 'Subject: Your code'), 'subject kept');
});

T()->test('mail transport availability follows configuration', function () {
    // run.php sets KLASIFY_DEBUG_RESET_CODES=1, so the log transport is usable.
    mail_env(['KLASIFY_MAIL_TRANSPORT' => 'log']);
    T()->truthy(mail_available(), 'debug log transport is available');

    mail_env(['KLASIFY_MAIL_TRANSPORT' => 'smtp', 'KLASIFY_SMTP_HOST' => '']);
    T()->truthy(!mail_available(), 'smtp without a host is unavailable');

    mail_env(['KLASIFY_SMTP_HOST' => '127.0.0.1']);
    T()->truthy(mail_available(), 'smtp with a host is available');

    mail_env(['KLASIFY_MAIL_TRANSPORT' => 'mail']);
    T()->truthy(mail_available(), 'mail() transport is available');

    mail_env([
        'KLASIFY_MAIL_TRANSPORT' => null,
        'KLASIFY_SMTP_HOST' => null,
    ]);
    T()->eq('log', mail_transport(), 'config falls back to the debug log transport');
});

T()->test('smtp delivers the reset code and the code resets the password', function () {
    db_reset();
    seed_user(['email' => 'smtp-reset@test.com', 'password' => 'firstpass']);

    $capture = (string)tempnam(sys_get_temp_dir(), 'klasify_smtp_');
    $script = __DIR__ . '/smtp_capture_server.php';
    $process = proc_open(
        [PHP_BINARY, $script, '0', $capture],
        [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
        $pipes
    );
    T()->truthy(is_resource($process), 'capture server started');

    try {
        $ready = fgets($pipes[1]);
        T()->truthy(
            preg_match('/^READY (\d+)\z/', trim((string)$ready), $match) === 1,
            'capture server ready: ' . trim((string)$ready)
        );
        $port = (int)$match[1];

        mail_env([
            'KLASIFY_MAIL_TRANSPORT' => 'smtp',
            'KLASIFY_SMTP_HOST' => '127.0.0.1',
            'KLASIFY_SMTP_PORT' => (string)$port,
            'KLASIFY_SMTP_SECURE' => 'none',
            'KLASIFY_SMTP_USER' => '',
            'KLASIFY_SMTP_PASS' => '',
            'KLASIFY_SMTP_TIMEOUT' => '5',
            'KLASIFY_MAIL_FROM' => 'no-reply@klasify.test',
            'KLASIFY_MAIL_FROM_NAME' => 'Klasify Test',
        ]);

        set_body(['email' => 'smtp-reset@test.com']);
        $forgot = run_handler('auth_forgot_password');
        T()->eq(200, $forgot['status'], 'forgot status');
        T()->eq(['ok' => true], $forgot['body'], 'forgot body');

        fclose($pipes[1]);
        $stderr = stream_get_contents($pipes[2]);
        fclose($pipes[2]);
        T()->eq(0, proc_close($process), 'capture server exit: ' . trim((string)$stderr));

        $raw = (string)file_get_contents($capture);
        T()->truthy(str_contains($raw, 'To: <smtp-reset@test.com>'), 'message addressed to the user');
        T()->truthy(str_contains($raw, 'From: "Klasify Test" <no-reply@klasify.test>'), 'sender header');
        T()->truthy(
            str_contains($raw, 'Subject: Your Klasify password reset code'),
            'subject header'
        );

        $body = explode("\r\n\r\n", $raw, 2)[1] ?? '';
        T()->truthy(preg_match('/(\d{6})/', $body, $codeMatch) === 1, '6-digit code in the body');
        $code = $codeMatch[1];

        // The database must hold a hash, never the code itself.
        $stored = (string)query(
            'SELECT code_hash FROM password_resets WHERE user_id = '
            . '(SELECT id FROM users WHERE email = ?) ORDER BY id DESC LIMIT 1',
            ['smtp-reset@test.com']
        )->fetchColumn();
        T()->truthy($stored !== '' && !str_contains($stored, $code), 'code stored hashed');
        T()->truthy(password_verify($code, $stored), 'stored hash matches the emailed code');

        set_body([
            'email' => 'smtp-reset@test.com',
            'code' => $code,
            'new_password' => 'smtp-pass-1',
        ]);
        $reset = run_handler('auth_reset_password');
        T()->eq(204, $reset['status'], 'reset with the emailed code');

        set_body(['email' => 'smtp-reset@test.com', 'password' => 'smtp-pass-1']);
        T()->eq(200, run_handler('auth_login')['status'], 'login with the new password');
    } finally {
        mail_env([
            'KLASIFY_MAIL_TRANSPORT' => null,
            'KLASIFY_SMTP_HOST' => null,
            'KLASIFY_SMTP_PORT' => null,
            'KLASIFY_SMTP_SECURE' => null,
            'KLASIFY_SMTP_USER' => null,
            'KLASIFY_SMTP_PASS' => null,
            'KLASIFY_SMTP_TIMEOUT' => null,
            'KLASIFY_MAIL_FROM' => null,
            'KLASIFY_MAIL_FROM_NAME' => null,
        ]);
        @unlink($capture);
        if (is_resource($process)) {
            @proc_terminate($process);
            @proc_close($process);
        }
    }
});

T()->test('delivery failure keeps the forgot response identical (no leak)', function () {
    db_reset();
    seed_user(['email' => 'unreachable@test.com', 'password' => 'firstpass']);

    mail_env([
        'KLASIFY_MAIL_TRANSPORT' => 'smtp',
        'KLASIFY_SMTP_HOST' => '127.0.0.1',
        'KLASIFY_SMTP_PORT' => '1',
        'KLASIFY_SMTP_SECURE' => 'none',
        'KLASIFY_SMTP_TIMEOUT' => '3',
    ]);

    try {
        set_body(['email' => 'unreachable@test.com']);
        $r = run_handler('auth_forgot_password');
        T()->eq(200, $r['status'], 'failure still returns 200');
        T()->eq(['ok' => true], $r['body'], 'failure body matches the no-leak shape');
    } finally {
        mail_env([
            'KLASIFY_MAIL_TRANSPORT' => null,
            'KLASIFY_SMTP_HOST' => null,
            'KLASIFY_SMTP_PORT' => null,
            'KLASIFY_SMTP_SECURE' => null,
            'KLASIFY_SMTP_TIMEOUT' => null,
        ]);
    }
});
