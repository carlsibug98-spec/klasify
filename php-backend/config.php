<?php
// Klasify API settings. These defaults match XAMPP out of the box:
// MySQL/MariaDB on 127.0.0.1:3306, user root, empty password.
// Change the JWT secret to a long random string before any real use.
// Each value can also be overridden with an environment variable of the same name.

return [
    'db_host'          => getenv('KLASIFY_DB_HOST') ?: '127.0.0.1',
    'db_port'          => getenv('KLASIFY_DB_PORT') ?: '3306',
    'db_name'          => getenv('KLASIFY_DB_NAME') ?: 'klasify_sync',
    'db_user'          => getenv('KLASIFY_DB_USER') ?: 'root',
    'db_pass'          => getenv('KLASIFY_DB_PASS') ?: '',
    'jwt_secret'       => getenv('KLASIFY_JWT_SECRET') ?: 'change-this-to-a-long-random-string-in-production',
    'google_client_id' => getenv('GOOGLE_CLIENT_ID') ?: '359657054360-0v7f3rlt56caci4h78v6kc0me91v2s4m.apps.googleusercontent.com',
];
