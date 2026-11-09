<?php
// src/auth.php
// /auth routes: register, login, Google sign-in, refresh, profile edit,
// account deletion, password change, and the forgot/reset password flow.
// Routes, status codes, error codes and response shapes match
// docs/sync_api_contract.md.

const EMAIL_PATTERN = '/^[^\s@]+@[^\s@]+\.[^\s@]+\z/';

function valid_email(string $email): bool
{
    return (bool)preg_match(EMAIL_PATTERN, $email);
}

/// Public shape of a user row, as every auth response returns it.
function user_json(array $row): array
{
    $role = js_text($row['role'] ?? null);
    $department = js_string($row['department'] ?? null);
    return [
        'id' => (int)$row['id'],
        'email' => $row['email'],
        'display_name' => $row['display_name'],
        'role' => $role !== '' ? $role : 'user',
        'department' => nonempty_or_null($department),
    ];
}

function hash_password(string $password): string
{
    return password_hash($password, PASSWORD_BCRYPT, ['cost' => BCRYPT_COST]);
}

/// POST /auth/register -> 201 { user, token, expires_at }
function auth_register(): void
{
    $body = read_json_body();
    $email = trim(js_text($body['email'] ?? null));
    $password = js_text($body['password'] ?? null);
    $displayName = trim(js_text($body['display_name'] ?? null));

    if (!valid_email($email)) {
        throw new ApiError(422, 'Invalid email address', 'VALIDATION_ERROR');
    }
    if (mb_strlen($password) < 8) {
        throw new ApiError(422, 'Password must be at least 8 characters', 'VALIDATION_ERROR');
    }
    if (fetch_one('SELECT id FROM users WHERE email = ?', [$email]) !== null) {
        throw new ApiError(409, 'An account with this email already exists', 'EMAIL_EXISTS');
    }

    $department = js_truthy($body['department'] ?? null)
        ? nonempty_or_null(trim(js_string($body['department'])))
        : null;

    query(
        'INSERT INTO users (email, password_hash, display_name, department) VALUES (?, ?, ?, ?)',
        [$email, hash_password($password), $displayName, $department]
    );
    $userId = (int)db()->lastInsertId();
    $user = fetch_one(
        'SELECT id, email, password_hash, display_name, role, department, google_sub FROM users WHERE id = ?',
        [$userId]
    );

    send_json(201, [
        'user' => user_json($user),
        'token' => jwt_sign_token($userId, $email),
        'expires_at' => expires_at_iso(),
    ]);
}

/// POST /auth/login -> 200 { user, token, expires_at } | 401 INVALID_CREDENTIALS
function auth_login(): void
{
    $body = read_json_body();
    $email = trim(js_text($body['email'] ?? null));
    $password = js_text($body['password'] ?? null);

    if ($email === '' || $password === '') {
        throw new ApiError(422, 'Email and password are required', 'VALIDATION_ERROR');
    }

    $user = fetch_one(
        'SELECT id, email, password_hash, display_name, role, department FROM users WHERE email = ? AND deleted = 0 LIMIT 1',
        [$email]
    );
    if ($user === null || !password_verify($password, (string)($user['password_hash'] ?? ''))) {
        throw new ApiError(401, 'Invalid email or password', 'INVALID_CREDENTIALS');
    }

    send_json(200, [
        'user' => user_json($user),
        'token' => jwt_sign_token((int)$user['id'], $user['email']),
        'expires_at' => expires_at_iso(),
    ]);
}

/// Checks a Google ID token with Google's tokeninfo endpoint, which verifies
/// the signature and expiry for us. Returns the claims, or null if invalid.
function verify_google_id_token(string $idToken, string $clientId): ?array
{
    $ch = curl_init('https://oauth2.googleapis.com/tokeninfo?id_token=' . rawurlencode($idToken));
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 10,
        CURLOPT_SSL_VERIFYPEER => true,
    ]);
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);

    if ($raw === false || $status !== 200) {
        return null;
    }
    $claims = json_decode((string)$raw, true);
    if (!is_array($claims)) {
        return null;
    }
    if (($claims['aud'] ?? null) !== $clientId) {
        return null;
    }
    if (!in_array($claims['iss'] ?? null, ['accounts.google.com', 'https://accounts.google.com'], true)) {
        return null;
    }
    return $claims;
}

/// POST /auth/google -> 200 { user, token, expires_at }
/// mode "signin" (default) never creates an account (404 ACCOUNT_NOT_FOUND);
/// mode "signup" creates one using the display_name and department sent.
function auth_google(): void
{
    $body = read_json_body();
    $idToken = trim(js_text($body['id_token'] ?? null));
    if ($idToken === '') {
        throw new ApiError(422, 'Google ID token is required', 'VALIDATION_ERROR');
    }

    $clientId = cfg('google_client_id');
    if ($clientId === '') {
        throw new ApiError(500, 'Google sign-in is not configured on the server', 'VALIDATION_ERROR');
    }

    if (!rate_limit_allow('google', 30, 60)) {
        throw new ApiError(429, 'Too many requests, please try again later', 'RATE_LIMITED');
    }

    $claims = verify_google_id_token($idToken, $clientId);
    if ($claims === null) {
        throw new ApiError(401, 'Invalid Google token', 'INVALID_GOOGLE_TOKEN');
    }
    $verified = $claims['email_verified'] ?? null;
    if (!js_truthy($claims['email'] ?? null) || !($verified === true || $verified === 'true')) {
        throw new ApiError(401, 'Google account email is not verified', 'INVALID_GOOGLE_TOKEN');
    }

    $email = strtolower(trim(js_string($claims['email'])));
    $googleSub = js_string($claims['sub'] ?? null);
    $googleName = trim(js_text($claims['name'] ?? null));

    $wantsSignup = ($body['mode'] ?? null) === 'signup';
    $requestedName = mb_substr(trim(js_text($body['display_name'] ?? null)), 0, 100);
    $department = isset($body['department'])
        ? nonempty_or_null(mb_substr(trim(js_string($body['department'])), 0, 100))
        : null;

    $columns = 'SELECT id, email, password_hash, display_name, google_sub, role, department FROM users WHERE ';

    // Look up by Google subject first, then by email (backfilling google_sub on match).
    $user = fetch_one($columns . 'google_sub = ? AND deleted = 0 LIMIT 1', [$googleSub]);
    if ($user === null) {
        $user = fetch_one($columns . 'email = ? AND deleted = 0 LIMIT 1', [$email]);
        if ($user !== null) {
            query('UPDATE users SET google_sub = ? WHERE id = ?', [$googleSub, $user['id']]);
            $user['google_sub'] = $googleSub;
        }
    }

    if ($user === null) {
        if (!$wantsSignup) {
            throw new ApiError(
                404,
                'No Klasify account is connected to this Google account. Create an account first.',
                'ACCOUNT_NOT_FOUND'
            );
        }
        // Soft-deleted accounts still hold the unique email/google_sub keys.
        if (fetch_one('SELECT id FROM users WHERE email = ? OR google_sub = ? LIMIT 1', [$email, $googleSub]) !== null) {
            throw new ApiError(409, 'An account with this email already exists', 'EMAIL_EXISTS');
        }
        $createdName = $requestedName !== '' ? $requestedName : $googleName;
        query(
            'INSERT INTO users (email, password_hash, google_sub, display_name, department) VALUES (?, NULL, ?, ?, ?)',
            [$email, $googleSub, $createdName, $department]
        );
        $user = fetch_one(
            'SELECT id, email, password_hash, display_name, google_sub, role, department FROM users WHERE id = ?',
            [(int)db()->lastInsertId()]
        );
    }

    send_json(200, [
        'user' => user_json($user),
        'token' => jwt_sign_token((int)$user['id'], $user['email']),
        'expires_at' => expires_at_iso(),
    ]);
}

/// POST /auth/refresh: accepts an expired token and reissues a fresh one.
/// Role and department are re-read from the database.
function auth_refresh(): void
{
    $token = bearer_token();
    if ($token === null) {
        throw new ApiError(401, 'Missing token', 'UNAUTHORIZED');
    }
    $claims = jwt_verify($token, true);
    if ($claims === null || !isset($claims['user_id'])) {
        throw new ApiError(401, 'Invalid token', 'TOKEN_EXPIRED');
    }

    $user = fetch_one(
        'SELECT id, email, display_name, role, department FROM users WHERE id = ? AND deleted = 0 LIMIT 1',
        [(int)$claims['user_id']]
    );
    if ($user === null) {
        throw new ApiError(401, 'User not found', 'TOKEN_EXPIRED');
    }

    send_json(200, [
        'user' => user_json($user),
        'token' => jwt_sign_token((int)$user['id'], $user['email']),
        'expires_at' => expires_at_iso(),
    ]);
}

/// DELETE /auth/account: soft-deletes the user and their data. 204.
function auth_delete_account(): void
{
    $userId = require_auth();
    query('UPDATE users SET deleted = 1 WHERE id = ?', [$userId]);
    query('UPDATE classes SET deleted = 1 WHERE user_id = ?', [$userId]);
    query('UPDATE events SET deleted = 1 WHERE user_id = ?', [$userId]);
    query('UPDATE class_statuses SET deleted = 1 WHERE user_id = ?', [$userId]);
    query('DELETE FROM password_resets WHERE user_id = ?', [$userId]);
    send_no_content();
}

/// PATCH /auth/me: partial profile edit (display_name and/or email). 200 { user }
function auth_update_me(): void
{
    $userId = require_auth();
    $body = read_json_body();

    $sets = [];
    $params = [];

    if (array_key_exists('display_name', $body)) {
        $name = trim(js_string($body['display_name']));
        if ($name === '' || mb_strlen($name) > 100) {
            throw new ApiError(422, 'Display name must be 1-100 characters', 'VALIDATION_ERROR');
        }
        $sets[] = 'display_name = ?';
        $params[] = $name;
    }

    $newEmail = null;
    if (array_key_exists('email', $body)) {
        $newEmail = trim(js_string($body['email']));
        if (!valid_email($newEmail)) {
            throw new ApiError(422, 'Invalid email address', 'VALIDATION_ERROR');
        }
        $sets[] = 'email = ?';
        $params[] = $newEmail;
    }

    if ($sets === []) {
        throw new ApiError(422, 'Nothing to update', 'VALIDATION_ERROR');
    }

    if ($newEmail !== null
        && fetch_one('SELECT id FROM users WHERE email = ? AND id <> ? LIMIT 1', [$newEmail, $userId]) !== null
    ) {
        throw new ApiError(409, 'An account with this email already exists', 'EMAIL_EXISTS');
    }

    query('UPDATE users SET ' . implode(', ', $sets) . ' WHERE id = ?', [...$params, $userId]);

    $user = fetch_one('SELECT id, email, display_name, role, department FROM users WHERE id = ? LIMIT 1', [$userId]);
    send_json(200, ['user' => user_json($user)]);
}

/// POST /auth/change-password: needs the current password. 204
function auth_change_password(): void
{
    $userId = require_auth();
    $body = read_json_body();
    $current = js_text($body['current_password'] ?? null);
    $new = js_text($body['new_password'] ?? null);

    if (mb_strlen($new) < 8) {
        throw new ApiError(422, 'Password must be at least 8 characters', 'VALIDATION_ERROR');
    }

    $row = fetch_one('SELECT password_hash FROM users WHERE id = ? AND deleted = 0 LIMIT 1', [$userId]);
    if ($row === null || !password_verify($current, (string)($row['password_hash'] ?? ''))) {
        throw new ApiError(401, 'Current password is incorrect', 'INVALID_CREDENTIALS');
    }

    query('UPDATE users SET password_hash = ? WHERE id = ?', [hash_password($new), $userId]);
    // Any outstanding reset codes are meaningless now.
    query('DELETE FROM password_resets WHERE user_id = ?', [$userId]);
    send_no_content();
}

/// POST /auth/forgot-password: always 200 { ok: true }, so it never reveals
/// whether an email is registered. Codes last 15 minutes; 5 requests per email per hour.
function auth_forgot_password(): void
{
    $body = read_json_body();
    $email = trim(js_text($body['email'] ?? null));

    if (!valid_email($email)) {
        throw new ApiError(422, 'Invalid email address', 'VALIDATION_ERROR');
    }
    if (!rate_limit_allow('forgot:' . strtolower($email), 5, 3600)) {
        throw new ApiError(429, 'Too many requests. Try again later.', 'RATE_LIMITED');
    }

    $user = fetch_one('SELECT id FROM users WHERE email = ? AND deleted = 0 LIMIT 1', [$email]);
    if ($user !== null) {
        $userId = (int)$user['id'];
        $code = str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        query('DELETE FROM password_resets WHERE user_id = ?', [$userId]);
        query(
            'INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?, ?, ?)',
            [
                $userId,
                hash_password($code),
                utc_now()->modify('+15 minutes')->format('Y-m-d H:i:s.v'),
            ]
        );

        // No mailer is configured yet, so the code goes to the log file
        // (storage/logs/app.log) to keep the flow testable in development.
        app_log("Password reset code for {$email}: {$code}");
    }

    send_json(200, ['ok' => true]);
}

/// POST /auth/reset-password: { email, code, new_password }. 204 | 422
function auth_reset_password(): void
{
    $body = read_json_body();
    $email = trim(js_text($body['email'] ?? null));
    $code = trim(js_text($body['code'] ?? null));
    $newPassword = js_text($body['new_password'] ?? null);

    if (!valid_email($email) || !preg_match('/^\d{6}\z/', $code) || mb_strlen($newPassword) < 8) {
        throw new ApiError(
            422,
            'Check the email, 6-digit code and a password of at least 8 characters',
            'VALIDATION_ERROR'
        );
    }

    $ok = false;
    $user = fetch_one('SELECT id FROM users WHERE email = ? AND deleted = 0 LIMIT 1', [$email]);
    if ($user !== null) {
        $userId = (int)$user['id'];
        $reset = fetch_one(
            'SELECT id, code_hash, expires_at FROM password_resets WHERE user_id = ? AND used_at IS NULL ORDER BY created_at DESC LIMIT 1',
            [$userId]
        );
        if ($reset !== null
            && password_verify($code, (string)($reset['code_hash'] ?? ''))
            && is_future_utc((string)$reset['expires_at'])
        ) {
            $ok = true;
            query('UPDATE users SET password_hash = ? WHERE id = ?', [hash_password($newPassword), $userId]);
            query('DELETE FROM password_resets WHERE user_id = ?', [$userId]);
        }
    }

    if (!$ok) {
        throw new ApiError(422, 'The reset code is invalid or expired', 'VALIDATION_ERROR');
    }
    send_no_content();
}
