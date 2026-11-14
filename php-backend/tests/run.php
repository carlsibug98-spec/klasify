<?php
// tests/run.php
// Parity harness entry point. Usage:
//   & "C:\xampp\php\php.exe" php-backend\tests\run.php

declare(strict_types=1);

putenv('KLASIFY_DB_NAME=klasify_test');
// Tests read the plaintext reset code from app.log; production leaves this off.
putenv('KLASIFY_DEBUG_RESET_CODES=1');

require __DIR__ . '/bootstrap.php';

// Buffer everything: handlers call header() per send_json, and headers were
// already emitted otherwise.
ob_start();

echo "== klasify parity harness ==\n";
db_rebuild();

foreach (['auth_test.php', 'sync_test.php', 'admin_test.php', 'google_jwks_test.php'] as $file) {
    $path = __DIR__ . '/' . $file;
    if (is_file($path)) {
        require $path;
    }
}

$exitCode = T()->finish();
ob_end_flush();
exit($exitCode);
