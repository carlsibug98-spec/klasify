<?php
// src/google_jwks.php
// Local verification of Google ID tokens using the published JWKS
// (RS256), instead of a per-login round trip to tokeninfo. The JWKS is
// cached on disk for up to 24 hours; a failed fetch falls back to a
// parseable cache so a school-PC internet blip does not lock everyone out.

/// Build a PEM-encoded RSA public key from a JWK's base64url n/e.
function jwks_pem(string $n, string $e): string
{
    $nBin = b64url_decode($n);
    $eBin = b64url_decode($e);

    // Pad the modulus so it is a positive two's-complement integer.
    if ($nBin !== '' && (ord($nBin[0]) & 0x80)) {
        $nBin = "\x00" . $nBin;
    }
    if ($eBin !== '' && (ord($eBin[0]) & 0x80)) {
        $eBin = "\x00" . $eBin;
    }

    $derInt = fn (string $bin): string => "\x02" . jwks_der_length(strlen($bin)) . $bin;
    $rsaSeq = "\x30" . jwks_der_length(strlen($derInt($nBin)) + strlen($derInt($eBin)))
        . $derInt($nBin) . $derInt($eBin);

    // AlgorithmIdentifier for rsaEncryption (OID 1.2.840.113549.1.1.1, NULL params).
    $oid = "\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01";
    $null = "\x05\x00";
    $algIdContent = $oid . $null;
    $algId = "\x30" . jwks_der_length(strlen($algIdContent)) . $algIdContent;

    // SubjectPublicKeyInfo: SEQUENCE { algorithm, subjectPublicKey BIT STRING }.
    $bitStringContent = "\x00" . $rsaSeq;
    $bitString = "\x03" . jwks_der_length(strlen($bitStringContent)) . $bitStringContent;
    $spkiContent = $algId . $bitString;
    $spki = "\x30" . jwks_der_length(strlen($spkiContent)) . $spkiContent;

    $b64 = base64_encode($spki);
    $lines = "-----BEGIN PUBLIC KEY-----\n";
    for ($i = 0; $i < strlen($b64); $i += 64) {
        $lines .= substr($b64, $i, 64) . "\n";
    }
    $lines .= "-----END PUBLIC KEY-----\n";
    return $lines;
}

function jwks_der_length(int $len): string
{
    if ($len < 0x80) {
        return chr($len);
    }
    $bytes = '';
    $tmp = $len;
    while ($tmp > 0) {
        $bytes = chr($tmp & 0xff) . $bytes;
        $tmp >>= 8;
    }
    return chr(0x80 | strlen($bytes)) . $bytes;
}

function jwks_cache_path(): string
{
    return dirname(__DIR__) . '/storage/cache/google_jwks.json';
}

function jwks_read_cache(string $path): ?array
{
    $raw = @file_get_contents($path);
    if ($raw === false) {
        return null;
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded) || !isset($decoded['keys']) || !is_array($decoded['keys'])) {
        return null;
    }
    if (!isset($decoded['fetched_at']) || !is_string($decoded['fetched_at'])) {
        return null;
    }
    return $decoded;
}

function jwks_cache_fresh(array $cache): bool
{
    $ts = strtotime($cache['fetched_at']);
    if ($ts === false) {
        return false;
    }
    return (time() - $ts) < 86400;
}

function jwks_write_cache(string $path, array $keys): void
{
    $dir = dirname($path);
    if (!is_dir($dir)) {
        @mkdir($dir, 0775, true);
    }
    $payload = json_encode(
        ['fetched_at' => gmdate('Y-m-d\TH:i:s\Z'), 'keys' => $keys],
        JSON_UNESCAPED_SLASHES
    );
    @file_put_contents($path, (string)$payload, LOCK_EX);
}

function jwks_find_key(array $keys, string $kid): ?array
{
    foreach ($keys as $k) {
        if (!is_array($k)) {
            continue;
        }
        if (($k['kid'] ?? null) !== $kid) {
            continue;
        }
        if (($k['kty'] ?? null) !== 'RSA') {
            continue;
        }
        if (isset($k['alg']) && $k['alg'] !== 'RS256') {
            continue;
        }
        if (isset($k['use']) && $k['use'] !== 'sig') {
            continue;
        }
        if (!isset($k['n'], $k['e']) || !is_string($k['n']) || !is_string($k['e'])) {
            continue;
        }
        return $k;
    }
    return null;
}

/// Verify a Google ID token locally against the JWKS. Returns the claims
/// array on success, null on any failure. $fetch is an optional override
/// used by tests (and by callers that want a custom transport); when null
/// the default cURL transport is used.
function google_verify_jwks(string $idToken, string $clientId, ?callable $fetch = null): ?array
{
    $parts = explode('.', $idToken);
    if (count($parts) !== 3) {
        return null;
    }
    $header = json_decode(b64url_decode($parts[0]), true);
    $claims = json_decode(b64url_decode($parts[1]), true);
    $sigBin = b64url_decode($parts[2]);
    if (!is_array($header) || !is_array($claims)) {
        return null;
    }
    if (($header['alg'] ?? null) !== 'RS256') {
        return null;
    }
    $kid = $header['kid'] ?? null;
    if (!is_string($kid) || $kid === '') {
        return null;
    }
    if (($claims['aud'] ?? null) !== $clientId) {
        return null;
    }
    if (!in_array($claims['iss'] ?? null, ['accounts.google.com', 'https://accounts.google.com'], true)) {
        return null;
    }
    if (!isset($claims['exp']) || !is_numeric($claims['exp']) || (int)$claims['exp'] <= time()) {
        return null;
    }

    $fetcher = $fetch;
    if ($fetcher === null) {
        $fetcher = function (): ?array {
            $ch = curl_init('https://www.googleapis.com/oauth2/v3/certs');
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
            $decoded = json_decode((string)$raw, true);
            if (!is_array($decoded) || !isset($decoded['keys']) || !is_array($decoded['keys'])) {
                return null;
            }
            return $decoded['keys'];
        };
    }

    $cachePath = jwks_cache_path();
    $cached = jwks_read_cache($cachePath);
    $cacheFresh = $cached !== null && jwks_cache_fresh($cached);

    $keys = $cacheFresh ? $cached['keys'] : null;
    $key = $keys !== null ? jwks_find_key($keys, $kid) : null;

    if ($key === null) {
        $fetched = $fetcher();
        if (is_array($fetched)) {
            $keys = $fetched;
            jwks_write_cache($cachePath, $keys);
            $key = jwks_find_key($keys, $kid);
        } else {
            // Fetch failed: fall back to a parseable cache (even a stale one)
            // so a school-PC internet blip does not lock everyone out.
            if ($cached !== null) {
                $keys = $cached['keys'];
                $key = jwks_find_key($keys, $kid);
            }
        }
    }

    if ($key === null) {
        return null;
    }

    $pem = jwks_pem((string)$key['n'], (string)$key['e']);
    $data = $parts[0] . '.' . $parts[1];
    if (openssl_verify($data, $sigBin, $pem, OPENSSL_ALGO_SHA256) !== 1) {
        return null;
    }

    return $claims;
}
