<?php
// src/common.php
// Shared helpers for the Klasify PHP API: database access, JSON in/out,
// JWT (HS256), rate limiting, logging, and small helpers that mirror the
// JavaScript coercions the original Node API relied on, so every route
// behaves the same as before.

date_default_timezone_set('UTC');

const TOKEN_TTL_SECONDS = 7 * 24 * 3600; // 7 days, same as the Node API
const BCRYPT_COST = 12;

/// An error that maps straight onto the contract's error response.
final class ApiError extends RuntimeException
{
    public function __construct(public int $status, string $message, public string $errorCode)
    {
        parent::__construct($message);
    }
}

function cfg(string $key): string
{
    static $settings = null;
    $settings ??= require __DIR__ . '/../config.php';
    return (string)($settings[$key] ?? '');
}

function db(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            cfg('db_host'),
            (int)cfg('db_port'),
            cfg('db_name')
        );
        $pdo = new PDO($dsn, cfg('db_user'), cfg('db_pass'), [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        // All DATETIME columns hold UTC values.
        $pdo->exec("SET time_zone = '+00:00'");
    }
    return $pdo;
}

function query(string $sql, array $params = []): PDOStatement
{
    $statement = db()->prepare($sql);
    $statement->execute($params);
    return $statement;
}

function fetch_one(string $sql, array $params = []): ?array
{
    $row = query($sql, $params)->fetch();
    return $row === false ? null : $row;
}

function fetch_all(string $sql, array $params = []): array
{
    return query($sql, $params)->fetchAll();
}

// ---------------------------------------------------------------------
// JSON in and out
// ---------------------------------------------------------------------

function send_json(int $status, mixed $data): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(
        $data,
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_THROW_ON_ERROR
    );
}

function send_no_content(): void
{
    http_response_code(204);
}

/// Parses the JSON request body once per request. An empty body is {}.
/// Malformed JSON is rejected with 422, like the Express parser did.
function read_json_body(): array
{
    // Test seam (adoption, 2026-11-09): the parity harness injects request
    // bodies from CLI (php://input is not writable there). Production never
    // sets this key, so behavior below is unchanged.
    if (isset($GLOBALS['KLASIFY_TEST_BODY'])) {
        return $GLOBALS['KLASIFY_TEST_BODY'];
    }
    static $body = null;
    if ($body !== null) {
        return $body;
    }
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return $body = [];
    }
    if (strlen($raw) > 4 * 1024 * 1024) {
        throw new ApiError(422, 'Request body is too large', 'VALIDATION_ERROR');
    }
    try {
        $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        throw new ApiError(422, 'Malformed JSON body', 'VALIDATION_ERROR');
    }
    if (!is_array($decoded)) {
        throw new ApiError(422, 'Malformed JSON body', 'VALIDATION_ERROR');
    }
    return $body = $decoded;
}

// ---------------------------------------------------------------------
// JavaScript-compatible coercions (String(), Number(), truthiness)
// ---------------------------------------------------------------------

/// String(v ?? '') in JavaScript.
function js_string(mixed $v): string
{
    if ($v === null) {
        return '';
    }
    if (is_bool($v)) {
        return $v ? 'true' : 'false';
    }
    if (is_array($v)) {
        return '';
    }
    return (string)$v;
}

/// String(v || '') in JavaScript: falsy values become ''.
function js_text(mixed $v): string
{
    return js_truthy($v) ? js_string($v) : '';
}

/// JavaScript truthiness: null, false, 0, NaN and '' are falsy; '0' is truthy.
function js_truthy(mixed $v): bool
{
    if ($v === null || $v === false || $v === '') {
        return false;
    }
    if (is_int($v) || is_float($v)) {
        return $v != 0 && !is_nan((float)$v);
    }
    return true;
}

/// Number(v) in JavaScript.
function js_number(mixed $v): float
{
    if ($v === null) {
        return 0.0;
    }
    if (is_bool($v)) {
        return $v ? 1.0 : 0.0;
    }
    if (is_int($v) || is_float($v)) {
        return (float)$v;
    }
    if (is_string($v)) {
        $t = trim($v);
        if ($t === '') {
            return 0.0;
        }
        return is_numeric($t) ? (float)$t : NAN;
    }
    return NAN;
}

function is_js_integer(float $n): bool
{
    return is_finite($n) && floor($n) === $n;
}

/// '' becomes null; anything else is returned as-is.
function nonempty_or_null(string $s): ?string
{
    return $s === '' ? null : $s;
}

// ---------------------------------------------------------------------
// Timestamps. Stored as UTC DATETIME(3); sent over the wire as ISO 8601.
// ---------------------------------------------------------------------

function utc_now(): DateTimeImmutable
{
    return new DateTimeImmutable('now', new DateTimeZone('UTC'));
}

/// 'YYYY-MM-DD HH:MM:SS.mmm' in UTC, the format the database stores.
function now_mysql(): string
{
    return utc_now()->format('Y-m-d H:i:s.v');
}

/// 'YYYY-MM-DDTHH:MM:SS.mmmZ', the same shape as JavaScript's toISOString().
function now_iso(): string
{
    return utc_now()->format('Y-m-d\TH:i:s.v\Z');
}

function expires_at_iso(): string
{
    return utc_now()->modify('+' . TOKEN_TTL_SECONDS . ' seconds')->format('Y-m-d\TH:i:s.v\Z');
}

/// Any ISO-ish string (or DateTime) to 'YYYY-MM-DD HH:MM:SS.mmm' in UTC. Null if unparseable.
function to_mysql_ts(mixed $value): ?string
{
    if (!is_string($value) || trim($value) === '') {
        return null;
    }
    try {
        $dt = new DateTimeImmutable(trim($value));
    } catch (Exception) {
        return null;
    }
    return $dt->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s.v');
}

/// 'YYYY-MM-DD HH:MM:SS.mmm' (from the database) to 'YYYY-MM-DDTHH:MM:SS.mmmZ'.
function from_mysql_ts_to_iso(mixed $value): ?string
{
    if (!is_string($value)) {
        return null;
    }
    if (!preg_match('/^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})(?:\.(\d{1,3}))?$/', $value, $m)) {
        return null;
    }
    $millis = str_pad($m[3] ?? '', 3, '0', STR_PAD_RIGHT);
    return $m[1] . 'T' . $m[2] . '.' . $millis . 'Z';
}

/// True when a UTC database timestamp is still in the future.
function is_future_utc(string $mysqlTimestamp): bool
{
    return new DateTimeImmutable($mysqlTimestamp, new DateTimeZone('UTC')) > utc_now();
}

// ---------------------------------------------------------------------
// JWT (HS256). Tokens carry { user_id, email, iat, exp }, the same claims
// the Node API issued, so existing sessions keep working when the secret
// is unchanged.
// ---------------------------------------------------------------------

function b64url_encode(string $raw): string
{
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

function b64url_decode(string $encoded): string
{
    $encoded = strtr($encoded, '-_', '+/');
    $pad = strlen($encoded) % 4;
    if ($pad) {
        $encoded .= str_repeat('=', 4 - $pad);
    }
    return (string)base64_decode($encoded, true);
}

function jwt_sign_token(int $userId, string $email): string
{
    $header = b64url_encode(json_encode(['alg' => 'HS256', 'typ' => 'JWT'], JSON_THROW_ON_ERROR));
    $now = time();
    $payload = b64url_encode(json_encode([
        'user_id' => $userId,
        'email' => $email,
        'iat' => $now,
        'exp' => $now + TOKEN_TTL_SECONDS,
    ], JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES));
    $signature = b64url_encode(hash_hmac('sha256', "$header.$payload", cfg('jwt_secret'), true));
    return "$header.$payload.$signature";
}

/// Returns the claims, or null when the signature is bad or the token is malformed.
/// Expired tokens are rejected unless $ignoreExpiry is true (used by /auth/refresh).
function jwt_verify(string $token, bool $ignoreExpiry = false): ?array
{
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        return null;
    }
    [$header, $payload, $signature] = $parts;

    $expected = b64url_encode(hash_hmac('sha256', "$header.$payload", cfg('jwt_secret'), true));
    if (!hash_equals($expected, $signature)) {
        return null;
    }

    $headerData = json_decode(b64url_decode($header), true);
    if (!is_array($headerData) || ($headerData['alg'] ?? null) !== 'HS256') {
        return null;
    }

    $claims = json_decode(b64url_decode($payload), true);
    if (!is_array($claims)) {
        return null;
    }
    if (!$ignoreExpiry && (!isset($claims['exp']) || (int)$claims['exp'] < time())) {
        return null;
    }
    return $claims;
}

function bearer_token(): ?string
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null;
    if ($header === null && function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        $header = $headers['Authorization'] ?? $headers['authorization'] ?? null;
    }
    if ($header === null) {
        return null;
    }
    return preg_match('/^Bearer\s+(.+)$/i', $header, $m) ? $m[1] : null;
}

/// Requires a valid Bearer token and returns the user id it carries.
function require_auth(): int
{
    $token = bearer_token();
    if ($token === null) {
        throw new ApiError(401, 'Missing authorization token', 'UNAUTHORIZED');
    }
    $claims = jwt_verify($token);
    if ($claims === null || !isset($claims['user_id'])) {
        throw new ApiError(401, 'Invalid or expired token', 'TOKEN_EXPIRED');
    }
    return (int)$claims['user_id'];
}

// ---------------------------------------------------------------------
// Rate limiting. Stored in the database so the limit holds across requests
// (PHP does not keep memory between requests the way a Node process does).
// ---------------------------------------------------------------------

/// Records a hit and returns true, or returns false when the bucket is full.
function rate_limit_allow(string $bucket, int $max, int $windowSeconds): bool
{
    static $ready = false;
    if (!$ready) {
        db()->exec(
            'CREATE TABLE IF NOT EXISTS rate_limit_hits (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                bucket VARCHAR(300) NOT NULL,
                hit_at DATETIME(3) NOT NULL,
                KEY idx_rl_bucket_time (bucket, hit_at)
            ) ENGINE=InnoDB'
        );
        $ready = true;
    }

    $since = utc_now()->modify("-{$windowSeconds} seconds")->format('Y-m-d H:i:s.v');
    $count = (int)query(
        'SELECT COUNT(*) FROM rate_limit_hits WHERE bucket = ? AND hit_at >= ?',
        [$bucket, $since]
    )->fetchColumn();
    if ($count >= $max) {
        return false;
    }

    query('INSERT INTO rate_limit_hits (bucket, hit_at) VALUES (?, ?)', [$bucket, now_mysql()]);

    // Housekeeping: now and then, drop hits older than a day.
    if (random_int(1, 100) === 1) {
        $cutoff = utc_now()->modify('-1 day')->format('Y-m-d H:i:s.v');
        query('DELETE FROM rate_limit_hits WHERE hit_at < ?', [$cutoff]);
    }
    return true;
}

// ---------------------------------------------------------------------
// Logging. Password-reset codes are written here while no mailer is set up.
// ---------------------------------------------------------------------

function app_log(string $message): void
{
    $dir = __DIR__ . '/../storage/logs';
    if (!is_dir($dir)) {
        @mkdir($dir, 0775, true);
    }
    file_put_contents($dir . '/app.log', '[' . now_iso() . '] ' . $message . PHP_EOL, FILE_APPEND | LOCK_EX);
}
