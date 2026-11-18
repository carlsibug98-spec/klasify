<?php
// Klasify API settings. These defaults match XAMPP out of the box:
// MySQL/MariaDB on 127.0.0.1:3306, user root, empty password.
// Change the JWT secret to a long random string before any real use.
// Each value can also be overridden with an environment variable of the same name.

$debugResetCodes = getenv('KLASIFY_DEBUG_RESET_CODES') === '1';

return [
    'db_host'          => getenv('KLASIFY_DB_HOST') ?: '127.0.0.1',
    'db_port'          => getenv('KLASIFY_DB_PORT') ?: '3306',
    'db_name'          => getenv('KLASIFY_DB_NAME') ?: 'klasify_sync',
    'db_user'          => getenv('KLASIFY_DB_USER') ?: 'root',
    'db_pass'          => getenv('KLASIFY_DB_PASS') ?: '',
    'jwt_secret'       => getenv('KLASIFY_JWT_SECRET') ?: 'change-this-to-a-long-random-string-in-production',
    'google_client_id' => getenv('GOOGLE_CLIENT_ID') ?: '359657054360-0v7f3rlt56caci4h78v6kc0me91v2s4m.apps.googleusercontent.com',
    'google_verify'     => getenv('KLASIFY_GOOGLE_VERIFY') ?: 'jwt_jwks',

    // Development-only: write plaintext password-reset codes to app.log and
    // make "log" the default transport. Never enable this in production.
    'debug_reset_codes' => $debugResetCodes ? '1' : '0',

    // Password-reset delivery. "smtp" needs a host; "mail" uses PHP mail();
    // "log" is the debug-only transport selected by the flag above.
    'mail_transport'   => getenv('KLASIFY_MAIL_TRANSPORT') ?: ($debugResetCodes ? 'log' : 'smtp'),
    'smtp_host'        => getenv('KLASIFY_SMTP_HOST') ?: '',
    'smtp_port'        => getenv('KLASIFY_SMTP_PORT') ?: '587',
    'smtp_secure'      => getenv('KLASIFY_SMTP_SECURE') ?: 'tls', // tls | ssl | none
    'smtp_user'        => getenv('KLASIFY_SMTP_USER') ?: '',
    'smtp_pass'        => getenv('KLASIFY_SMTP_PASS') ?: '',
    'smtp_verify_peer' => getenv('KLASIFY_SMTP_VERIFY_PEER') === '0' ? '0' : '1',
    'smtp_timeout'     => getenv('KLASIFY_SMTP_TIMEOUT') ?: '10',
    'mail_from'        => getenv('KLASIFY_MAIL_FROM') ?: 'no-reply@klasify.local',
    'mail_from_name'   => getenv('KLASIFY_MAIL_FROM_NAME') ?: 'Klasify',
];
