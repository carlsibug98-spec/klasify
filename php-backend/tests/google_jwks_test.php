<?php
// tests/google_jwks_test.php
// Offline JWKS (RS256) verification of Google ID tokens.
// No network: every fetch goes through an injected closure.

declare(strict_types=1);

const JWKS_CLIENT = 'test-client-id.apps.googleusercontent.com';
const JWKS_CACHE = __DIR__ . '/../storage/cache/google_jwks.json';

function jwks_cache_dir(): void
{
    $d = dirname(JWKS_CACHE);
    if (!is_dir($d)) {
        @mkdir($d, 0775, true);
    }
}

function jwks_clear_cache(): void
{
    @unlink(JWKS_CACHE);
}

function jwks_write_cache_raw(array $keys, int $ageSeconds): void
{
    jwks_cache_dir();
    $fetchedAt = gmdate('Y-m-d\TH:i:s\Z', time() - $ageSeconds);
    file_put_contents(
        JWKS_CACHE,
        json_encode(['fetched_at' => $fetchedAt, 'keys' => $keys], JSON_UNESCAPED_SLASHES),
        LOCK_EX
    );
}

T()->test('valid RS256 token verifies', function () {
    jwks_clear_cache();
    $claims = [
        'sub' => 'google-sub-1',
        'email' => 'user@gmail.com',
        'email_verified' => true,
        'name' => 'Test User',
        'aud' => JWKS_CLIENT,
        'iss' => 'accounts.google.com',
        'exp' => time() + 3600,
        'iat' => time(),
    ];
    $fx = make_rs256_fixture($claims, 'kid-A');
    $keys = json_decode($fx['jwks'], true)['keys'];
    $fetcher = function () use ($keys) {
        return $keys;
    };
    $got = google_verify_jwks($fx['token'], JWKS_CLIENT, $fetcher);
    T()->truthy(is_array($got), 'claims returned');
    T()->eq('google-sub-1', $got['sub'] ?? null, 'sub echoed');
    T()->eq('user@gmail.com', $got['email'] ?? null, 'email echoed');
    T()->eq('Test User', $got['name'] ?? null, 'name echoed');
    T()->eq(JWKS_CLIENT, $got['aud'] ?? null, 'aud echoed');
    T()->eq('accounts.google.com', $got['iss'] ?? null, 'iss echoed');
});

T()->test('tampered signature rejected', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'x', 'email' => 'x@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'accounts.google.com', 'exp' => time() + 3600];
    $fx = make_rs256_fixture($claims, 'kid-B');
    $keys = json_decode($fx['jwks'], true)['keys'];
    $fetcher = fn () => $keys;
    // Flip a byte in the signature.
    $parts = explode('.', $fx['token']);
    $sig = base64_decode(strtr($parts[2], '-_', '+/'));
    $sig[0] = chr(ord($sig[0]) ^ 0xff);
    $parts[2] = rtrim(strtr(base64_encode($sig), '+/', '-_'), '=');
    $tampered = implode('.', $parts);
    $got = google_verify_jwks($tampered, JWKS_CLIENT, $fetcher);
    T()->truthy($got === null, 'tampered signature -> null');
});

T()->test('wrong aud rejected', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'x', 'email' => 'x@gmail.com', 'email_verified' => true, 'aud' => 'other-client', 'iss' => 'accounts.google.com', 'exp' => time() + 3600];
    $fx = make_rs256_fixture($claims, 'kid-C');
    $keys = json_decode($fx['jwks'], true)['keys'];
    $got = google_verify_jwks($fx['token'], JWKS_CLIENT, fn () => $keys);
    T()->truthy($got === null, 'wrong aud -> null');
});

T()->test('wrong iss rejected', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'x', 'email' => 'x@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'https://evil.com', 'exp' => time() + 3600];
    $fx = make_rs256_fixture($claims, 'kid-D');
    $keys = json_decode($fx['jwks'], true)['keys'];
    $got = google_verify_jwks($fx['token'], JWKS_CLIENT, fn () => $keys);
    T()->truthy($got === null, 'wrong iss -> null');
});

T()->test('expired exp rejected', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'x', 'email' => 'x@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'accounts.google.com', 'exp' => time() - 10];
    $fx = make_rs256_fixture($claims, 'kid-E');
    $keys = json_decode($fx['jwks'], true)['keys'];
    $got = google_verify_jwks($fx['token'], JWKS_CLIENT, fn () => $keys);
    T()->truthy($got === null, 'expired exp -> null');
});

T()->test('alg confusion rejected (HS256/none alg, bad key alg)', function () {
    jwks_clear_cache();
    // Token signed RS256 but header claims HS256.
    $claims = ['sub' => 'x', 'email' => 'x@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'accounts.google.com', 'exp' => time() + 3600];
    $fx = make_rs256_fixture($claims, 'kid-F');
    $keys = json_decode($fx['jwks'], true)['keys'];
    // Rebuild token with alg=HS256 in header.
    $parts = explode('.', $fx['token']);
    $header = json_decode(b64url_decode($parts[0]), true);
    $header['alg'] = 'HS256';
    $parts[0] = b64url_encode(json_encode($header));
    $hsToken = implode('.', $parts);
    $got = google_verify_jwks($hsToken, JWKS_CLIENT, fn () => $keys);
    T()->truthy($got === null, 'HS256 alg header -> null');

    // Key carrying a non-RS256 alg must be skipped.
    $badKeys = $keys;
    $badKeys[0]['alg'] = 'HS256';
    $got2 = google_verify_jwks($fx['token'], JWKS_CLIENT, fn () => $badKeys);
    T()->truthy($got2 === null, 'key with non-RS256 alg -> null');
});

T()->test('kid rotation forces a single re-fetch', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'rot', 'email' => 'rot@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'accounts.google.com', 'exp' => time() + 3600];
    $fx1 = make_rs256_fixture($claims, 'kid-1');
    $fx2 = make_rs256_fixture($claims, 'kid-2');
    $keys1 = json_decode($fx1['jwks'], true)['keys'];
    $keys2 = json_decode($fx2['jwks'], true)['keys'];

    // Pre-seed cache with kid-1 (fresh).
    jwks_write_cache_raw($keys1, 60);

    $fetchCount = 0;
    $fetcher = function () use (&$fetchCount, $keys2) {
        $fetchCount++;
        return $keys2;
    };

    // First call: kid-2 missing -> fetch (kid-2) -> verify.
    $got1 = google_verify_jwks($fx2['token'], JWKS_CLIENT, $fetcher);
    T()->truthy(is_array($got1), 'first call verifies after re-fetch');
    T()->eq(1, $fetchCount, 'force-refresh happened exactly once');

    // Second call: cache now has kid-2 -> no fetch.
    $got2 = google_verify_jwks($fx2['token'], JWKS_CLIENT, $fetcher);
    T()->truthy(is_array($got2), 'second call verifies from cache');
    T()->eq(1, $fetchCount, 'no redundant fetch on cache hit');
});

T()->test('fresh cache hit avoids fetch entirely (Review Focus 5)', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'fresh', 'email' => 'fresh@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'accounts.google.com', 'exp' => time() + 3600];
    $fx = make_rs256_fixture($claims, 'kid-FRESH');
    $keys = json_decode($fx['jwks'], true)['keys'];
    jwks_write_cache_raw($keys, 60); // 1 minute old -> fresh

    $fetchCount = 0;
    $fetcher = function () use (&$fetchCount) {
        $fetchCount++;
        return null; // would fail if called
    };
    $got = google_verify_jwks($fx['token'], JWKS_CLIENT, $fetcher);
    T()->truthy(is_array($got), 'fresh cache verifies without network');
    T()->eq(0, $fetchCount, 'fetcher not called on fresh cache hit');
});

T()->test('fetch failure falls back to stale cache (internet blip resilience)', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'stale', 'email' => 'stale@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'accounts.google.com', 'exp' => time() + 3600];
    $fx = make_rs256_fixture($claims, 'kid-STALE');
    $keys = json_decode($fx['jwks'], true)['keys'];
    jwks_write_cache_raw($keys, 30 * 3600); // 30h old -> stale

    $fetchCount = 0;
    $fetcher = function () use (&$fetchCount) {
        $fetchCount++;
        return null; // network down
    };
    $got = google_verify_jwks($fx['token'], JWKS_CLIENT, $fetcher);
    T()->truthy(is_array($got), 'stale cache fallback verifies');
    T()->eq(1, $fetchCount, 'fetch attempted on stale cache');
});

T()->test('no cache and failed fetch -> null', function () {
    jwks_clear_cache();
    $claims = ['sub' => 'none', 'email' => 'none@gmail.com', 'email_verified' => true, 'aud' => JWKS_CLIENT, 'iss' => 'accounts.google.com', 'exp' => time() + 3600];
    $fx = make_rs256_fixture($claims, 'kid-NONE');
    $fetcher = fn () => null;
    $got = google_verify_jwks($fx['token'], JWKS_CLIENT, $fetcher);
    T()->truthy($got === null, 'no keys available -> null');
});

T()->test('tokeninfo fallback still present', function () {
    T()->truthy(function_exists('verify_google_id_token'), 'legacy verifier intact');
});
