<?php
// tests/bootstrap.php
// Zero-Composer parity harness for the Klasify PHP backend. Mirrors what
// index.php does in production (requires, error -> {error, code} JSON) so
// route handlers are tested exactly the way Apache serves them.
//
// Tests run against the disposable klasify_test database; db_rebuild()
// re-imports docs/mysql_schema.sql (renamed) so the schema the harness
// exercises is literally the documented one.

declare(strict_types=1);

require dirname(__DIR__) . '/src/common.php';
require dirname(__DIR__) . '/src/auth.php';
require dirname(__DIR__) . '/src/sync.php';
require dirname(__DIR__) . '/src/admin.php';
require dirname(__DIR__) . '/src/google_jwks.php';

/// Minimal test runner: immediate execution, pass/fail counters, CLI output.
final class T
{
    public int $pass = 0;
    public int $fail = 0;

    public function test(string $name, callable $fn): void
    {
        try {
            $fn();
            $this->pass++;
            echo "[ok]   {$name}\n";
        } catch (Throwable $e) {
            $this->fail++;
            echo "[FAIL] {$name} — " . $e->getMessage() . "\n";
        }
    }

    public function eq(mixed $expected, mixed $actual, string $label = ''): void
    {
        if (is_array($expected) && is_array($actual)) {
            $this->truthy(count($expected) === count($actual), $label . ' (array size)');
            $keys = array_unique(array_merge(array_keys($expected), array_keys($actual)));
            foreach ($keys as $k) {
                $this->eq($expected[$k] ?? null, $actual[$k] ?? null, $label . (is_string($k) ? ".{$k}" : '#' . (string)$k));
            }
            return;
        }
        $this->truthy(
            $expected === $actual,
            $label . ' — expected ' . var_export($expected, true) . ', got ' . var_export($actual, true)
        );
    }

    public function truthy(bool $cond, string $label): void
    {
        if (!$cond) {
            throw new RuntimeException($label);
        }
    }

    public function fail(string $label): void
    {
        throw new RuntimeException($label);
    }

    public function finish(): int
    {
        echo "\npassed {$this->pass}, failed {$this->fail}\n";
        return $this->fail;
    }
}

/// Global accessor for the runner (plain function, callable from any scope —
/// closures in test files use T()->eq(...) and never need `use ($T)`).
function T(): T
{
    static $runner = null;
    return $runner ??= new T();
}

function db_setup(): void
{
    $pdo = new PDO(
        sprintf('mysql:host=%s;port=%d;charset=utf8mb4', cfg('db_host'), (int)cfg('db_port')),
        cfg('db_user'),
        cfg('db_pass'),
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    $pdo->exec('DROP DATABASE IF EXISTS klasify_test');

    // Execute the documented schema verbatim, with the database renamed.
    $schema = file_get_contents(dirname(__DIR__, 2) . '/docs/mysql_schema.sql');
    if ($schema === false) {
        fwrite(STDERR, "bootstrap: cannot read docs/mysql_schema.sql\n");
        exit(1);
    }
    $schema = str_replace('klasify_sync', 'klasify_test', $schema);
    // Strip whole-line and inline ``--`` comments before splitting into
    // statements: comments may contain semicolons (e.g. "cost 12; NULL").
    // Verified safe: no quoted string literal in this schema contains "--".
    $stripped = [];
    foreach (explode("\n", $schema) as $line) {
        $pos = strpos($line, '--');
        $stripped[] = $pos === false ? $line : substr($line, 0, $pos);
    }
    $withoutComments = implode("\n", $stripped);
    foreach (array_filter(explode(';', $withoutComments), fn (string $s) => trim($s) !== '') as $stmt) {
        $pdo->exec($stmt);
    }

    // The rate_limit_hits DDL added with the adoption must be present.
    $found = $pdo->query("SHOW TABLES LIKE 'rate_limit_hits'")->fetchColumn();
    if ($found === false) {
        fwrite(STDERR, "bootstrap: rate_limit_hits missing after db_rebuild\n");
        exit(1);
    }
}

/// Rebuild the whole test database from the schema file. Once per suite run.
function db_rebuild(): void
{
    db_setup();
    db_reset();
}

const RESET_TABLES = [
    'users',
    'classes',
    'events',
    'office_statuses',
    'class_statuses',
    'password_resets',
    'sync_cursors',
    'rate_limit_hits',
];

/// Empty every table between tests and reset AUTO_INCREMENT. Note: with
/// FOREIGN_KEY_CHECKS=0 MariaDB allows TRUNCATE on referenced parent tables
/// but silently SKIPS the AUTO_INCREMENT reset — so ALTER it explicitly to
/// keep seeded ids deterministic (1, 2, 3, ...).
function db_reset(): void
{
    db()->exec('SET FOREIGN_KEY_CHECKS=0');
    foreach (RESET_TABLES as $table) {
        db()->exec("TRUNCATE TABLE `{$table}`");
        db()->exec("ALTER TABLE `{$table}` AUTO_INCREMENT = 1");
    }
    db()->exec('SET FOREIGN_KEY_CHECKS=1');
}

/// Seed one user row; returns the new id.
function seed_user(array $fields = []): int
{
    query(
        'INSERT INTO users (email, password_hash, display_name, role, department, google_sub, deleted) VALUES (?,?,?,?,?,?,?)',
        [
            $fields['email'],
            $fields['password_hash']
                ?? password_hash($fields['password'] ?? 'password123', PASSWORD_BCRYPT, ['cost' => 12]),
            $fields['display_name'] ?? 'Test User',
            $fields['role'] ?? 'user',
            $fields['department'] ?? null,
            $fields['google_sub'] ?? null,
            $fields['deleted'] ?? 0,
        ]
    );
    return (int)db()->lastInsertId();
}

/// Become a signed-in user (id 0 = anonymous).
function act_as(int $userId): void
{
    if ($userId === 0) {
        unset($_SERVER['HTTP_AUTHORIZATION']);
        return;
    }
    $row = fetch_one('SELECT email, token_version FROM users WHERE id = ?', [$userId]);
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . jwt_sign_token(
        $userId,
        (string)($row['email'] ?? ''),
        (int)($row['token_version'] ?? 0)
    );
}

/// Inject the request body for read_json_body() (the adopted test seam).
/// null clears the seam.
function set_body(?array $body): void
{
    if ($body === null) {
        unset($GLOBALS['KLASIFY_TEST_BODY']);
    } else {
        $GLOBALS['KLASIFY_TEST_BODY'] = $body;
    }
}

/// Mirrors index.php's dispatch + catch chain and captures the response.
function run_handler(callable $handler, mixed ...$args): array
{
    http_response_code(200);
    ob_start();
    try {
        $handler(...$args);
    } catch (ApiError $e) {
        send_json($e->status, ['error' => $e->getMessage(), 'code' => $e->errorCode]);
    } catch (Throwable $e) {
        app_log('ERROR ' . get_class($e) . ': ' . $e->getMessage() . ' in ' . $e->getFile() . ':' . $e->getLine());
        send_json(500, ['error' => 'Internal server error', 'code' => 'SERVER_ERROR']);
    }
    $raw = (string)ob_get_clean();
    $body = $raw === '' ? [] : (json_decode($raw, true) ?? []);
    return ['status' => http_response_code() ?: 200, 'body' => $body, 'raw' => $raw];
}

/// HS256 token in the same shape as jwt_sign_token, with backdated claims,
/// for the /auth/refresh paths. `$expiredSecondsAgo` controls how far past
/// expiry the token is (used to prove the refresh grace window is bounded).
function make_expired_token(
    int $userId,
    string $email,
    int $tokenVersion = 0,
    int $expiredSecondsAgo = 10
): string {
    $header = b64url_encode(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
    $now = time();
    $exp = $now - $expiredSecondsAgo;
    $payload = b64url_encode(json_encode([
        'user_id' => $userId,
        'email' => $email,
        'tv' => $tokenVersion,
        'iat' => $exp - TOKEN_TTL_SECONDS,
        'exp' => $exp,
    ], JSON_UNESCAPED_SLASHES));
    $sig = b64url_encode(hash_hmac('sha256', "$header.$payload", cfg('jwt_secret'), true));
    return "$header.$payload.$sig";
}

/// RS256 fixture for the JWKS tests: generate a keypair, build a JWKS doc
/// and a matching signed id_token with the given claims.
function make_rs256_fixture(array $claims, string $kid = 'test-kid-1'): array
{
    $privKey = openssl_pkey_new([
        'digest_alg' => 'sha256',
        'private_key_bits' => 2048,
        'private_key_type' => OPENSSL_KEYTYPE_RSA,
        'config' => 'C:/xampp/php/extras/openssl/openssl.cnf',
    ]);
    if ($privKey === false) {
        $privKey = openssl_pkey_new([
            'digest_alg' => 'sha256',
            'private_key_bits' => 2048,
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
            'config' => 'C:/xampp/apache/conf/openssl.cnf',
        ]);
    }
    $details = openssl_pkey_get_details($privKey);
    $b64url = fn (string $bin) => rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
    // JWK wants the modulus as an unsigned octet string (no leading zeros).
    $n = ltrim($details['rsa']['n'], "\x00");
    $jwks = json_encode([
        'keys' => [[
            'kty' => 'RSA',
            'kid' => $kid,
            'use' => 'sig',
            'alg' => 'RS256',
            'n' => $b64url($n),
            'e' => $b64url($details['rsa']['e']),
        ]],
    ], JSON_UNESCAPED_SLASHES);

    $header = b64url_encode(json_encode(['alg' => 'RS256', 'kid' => $kid]));
    $payload = b64url_encode(json_encode($claims, JSON_UNESCAPED_SLASHES));
    $input = $header . '.' . $payload;
    openssl_sign($input, $sig, $privKey, OPENSSL_ALGO_SHA256);

    return ['token' => $input . '.' . b64url_encode($sig), 'jwks' => (string)$jwks, 'priv' => $privKey];
}

/// Tail of app.log: the most recent 6-digit run (the forgot-password code).
function last_log_code(): string
{
    $log = dirname(__DIR__) . '/storage/logs/app.log';
    $text = @file_get_contents($log) ?: '';
    preg_match_all('/(\d{6})/', $text, $m);
    throw_unless(!empty($m[1]), 'last_log_code: no 6-digit code in app.log');
    return (string)end($m[1]);
}

/// Tiny assert helper for boolean guards in tests.
function throw_unless(bool $cond, string $message): void
{
    if (!$cond) {
        throw new RuntimeException($message);
    }
}
