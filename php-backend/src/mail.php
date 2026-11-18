<?php
declare(strict_types=1);

// Password-reset email delivery.
//
// Three transports, chosen with KLASIFY_MAIL_TRANSPORT:
//   smtp (default) - real SMTP over PHP streams; STARTTLS or implicit TLS
//   mail           - PHP's mail() for hosts that provide a local sendmail
//   log            - development only; writes the code to app.log
//
// The SMTP client is dependency-free on purpose: this backend ships without
// Composer, and a reset email must not depend on an extension being present.

function mail_transport(): string
{
    $transport = getenv('KLASIFY_MAIL_TRANSPORT');
    if ($transport === false || trim($transport) === '') {
        $transport = cfg('mail_transport');
    }
    return strtolower(trim((string)$transport)) ?: 'smtp';
}

/// Environment wins over config.php so a deployment can be fixed without
/// editing files, and so tests can point the mailer at a capture server.
function mail_setting(string $env, string $key, string $default = ''): string
{
    $value = getenv($env);
    if ($value === false || $value === '') {
        $value = cfg($key);
    }
    return $value === '' ? $default : (string)$value;
}

function mail_settings(): array
{
    return [
        'host' => mail_setting('KLASIFY_SMTP_HOST', 'smtp_host'),
        'port' => (int)mail_setting('KLASIFY_SMTP_PORT', 'smtp_port', '587'),
        'secure' => strtolower(mail_setting('KLASIFY_SMTP_SECURE', 'smtp_secure', 'tls')),
        'user' => mail_setting('KLASIFY_SMTP_USER', 'smtp_user'),
        'pass' => mail_setting('KLASIFY_SMTP_PASS', 'smtp_pass'),
        'from' => mail_setting('KLASIFY_MAIL_FROM', 'mail_from', 'no-reply@klasify.local'),
        'from_name' => mail_setting('KLASIFY_MAIL_FROM_NAME', 'mail_from_name', 'Klasify'),
        'verify_peer' => mail_setting('KLASIFY_SMTP_VERIFY_PEER', 'smtp_verify_peer', '1') !== '0',
        'timeout' => (int)mail_setting('KLASIFY_SMTP_TIMEOUT', 'smtp_timeout', '10'),
    ];
}

/// True when the configured transport can actually deliver a message.
/// A log transport without the development flag would silently lose the code,
/// so it is treated as unavailable.
function mail_available(): bool
{
    $transport = mail_transport();
    if ($transport === 'log') {
        return cfg('debug_reset_codes') === '1';
    }
    if ($transport === 'smtp') {
        return mail_settings()['host'] !== '';
    }
    return $transport === 'mail';
}

/// Sends the 6-digit reset code. Throws when delivery fails; the caller decides
/// whether to surface that (it must not leak whether the address exists).
function send_reset_code_email(string $to, string $code): void
{
    $settings = mail_settings();
    $subject = 'Your Klasify password reset code';
    $body = "Your Klasify password reset code is {$code}.\n\n"
        . "It expires in 15 minutes and can be used once.\n"
        . "If you did not request it, you can ignore this email.\n";

    switch (mail_transport()) {
        case 'log':
            // The forgot handler writes the code when the debug flag is on.
            return;
        case 'mail':
            php_mail_deliver($settings, $to, $subject, $body);
            return;
        case 'smtp':
            smtp_send($settings, $to, $subject, $body);
            return;
        default:
            throw new RuntimeException('Unknown mail transport: ' . mail_transport());
    }
}

function php_mail_deliver(array $settings, string $to, string $subject, string $body): void
{
    $headers = [
        'From: ' . mail_from_header($settings),
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: 8bit',
    ];
    if (!@mail($to, $subject, $body, implode("\r\n", $headers))) {
        throw new RuntimeException('mail() rejected the message');
    }
}

function smtp_send(array $settings, string $to, string $subject, string $body): void
{
    $host = trim((string)$settings['host']);
    if ($host === '') {
        throw new RuntimeException('SMTP host is not configured');
    }
    $port = (int)$settings['port'];
    $secure = (string)$settings['secure'];
    $timeout = max(3, (int)$settings['timeout']);

    $context = stream_context_create([
        'ssl' => [
            'verify_peer' => (bool)$settings['verify_peer'],
            'verify_peer_name' => (bool)$settings['verify_peer'],
            'allow_self_signed' => !(bool)$settings['verify_peer'],
        ],
    ]);
    $remote = ($secure === 'ssl' ? 'ssl://' : 'tcp://') . $host . ':' . $port;
    $errno = 0;
    $errstr = '';
    $socket = @stream_socket_client(
        $remote,
        $errno,
        $errstr,
        $timeout,
        STREAM_CLIENT_CONNECT,
        $context
    );
    if ($socket === false) {
        throw new RuntimeException("SMTP connection to {$host}:{$port} failed: {$errstr} ({$errno})");
    }
    stream_set_timeout($socket, $timeout);

    try {
        smtp_expect($socket, [220]);
        $hostname = smtp_helo_name();
        smtp_command($socket, 'EHLO ' . $hostname, [250]);

        if ($secure === 'tls') {
            smtp_command($socket, 'STARTTLS', [220]);
            $method = STREAM_CRYPTO_METHOD_TLS_CLIENT;
            if (!@stream_socket_enable_crypto($socket, true, $method)) {
                throw new RuntimeException('SMTP STARTTLS negotiation failed');
            }
            smtp_command($socket, 'EHLO ' . $hostname, [250]);
        }

        if ((string)$settings['user'] !== '') {
            smtp_command($socket, 'AUTH LOGIN', [334]);
            smtp_command($socket, base64_encode((string)$settings['user']), [334]);
            smtp_command($socket, base64_encode((string)$settings['pass']), [235]);
        }

        $from = mail_sanitize_address((string)$settings['from']);
        $recipient = mail_sanitize_address($to);
        smtp_command($socket, 'MAIL FROM:<' . $from . '>', [250]);
        smtp_command($socket, 'RCPT TO:<' . $recipient . '>', [250, 251]);
        smtp_command($socket, 'DATA', [354]);
        $message = smtp_build_message($settings, $recipient, $subject, $body);
        smtp_write($socket, $message . "\r\n.\r\n");
        smtp_expect($socket, [250]);
        smtp_command($socket, 'QUIT', [221], false);
    } finally {
        fclose($socket);
    }
}

function smtp_helo_name(): string
{
    $name = gethostname();
    if (!is_string($name) || $name === '') {
        return 'localhost';
    }
    $clean = preg_replace('/[^A-Za-z0-9.\-]/', '-', $name);
    return $clean === '' ? 'localhost' : $clean;
}

function mail_sanitize_address(string $value): string
{
    $value = trim(str_replace(["\r", "\n", '<', '>'], '', $value));
    if ($value === '') {
        throw new RuntimeException('Empty mail address');
    }
    return $value;
}

function mail_from_header(array $settings): string
{
    $address = mail_sanitize_address((string)$settings['from']);
    $name = trim(str_replace(["\r", "\n"], '', (string)$settings['from_name']));
    if ($name === '') {
        return '<' . $address . '>';
    }
    return '"' . addcslashes($name, '"\\') . '" <' . $address . '>';
}

/// Builds the RFC 5322 message. Exposed for tests: header injection is
/// stripped, and leading dots are stuffed so SMTP cannot terminate DATA early.
function smtp_build_message(array $settings, string $to, string $subject, string $body): string
{
    $from = mail_sanitize_address((string)$settings['from']);
    $to = mail_sanitize_address($to);
    $subject = trim(str_replace(["\r", "\n"], ' ', $subject));
    $domain = substr(strrchr($from, '@') ?: '@localhost', 1) ?: 'localhost';

    $headers = [
        'Date: ' . date(DATE_RFC2822),
        'From: ' . mail_from_header($settings),
        'To: <' . $to . '>',
        'Subject: ' . $subject,
        'Message-ID: <' . bin2hex(random_bytes(12)) . '@' . $domain . '>',
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: 8bit',
    ];

    $normalized = str_replace(["\r\n", "\r"], "\n", $body);
    $normalized = rtrim($normalized, "\n");
    $normalized = preg_replace('/^\./m', '..', $normalized) ?? $normalized;
    $normalized = str_replace("\n", "\r\n", $normalized);

    return implode("\r\n", $headers) . "\r\n\r\n" . $normalized;
}

function smtp_write($socket, string $data): void
{
    $written = 0;
    $length = strlen($data);
    while ($written < $length) {
        $chunk = @fwrite($socket, substr($data, $written));
        if ($chunk === false || $chunk === 0) {
            throw new RuntimeException('SMTP write failed');
        }
        $written += $chunk;
    }
}

function smtp_command($socket, string $command, array $codes, bool $expectReply = true): void
{
    smtp_write($socket, $command . "\r\n");
    if ($expectReply) {
        smtp_expect($socket, $codes);
    }
}

/// Reads one (possibly multi-line) SMTP reply and checks its status code.
function smtp_expect($socket, array $codes): string
{
    $lines = [];
    while (true) {
        $line = fgets($socket, 1024);
        if ($line === false) {
            $meta = stream_get_meta_data($socket);
            $why = $meta['timed_out'] ? 'timed out' : 'connection closed';
            throw new RuntimeException('SMTP reply failed: ' . $why);
        }
        $clean = rtrim($line, "\r\n");
        $lines[] = $clean;
        // "250-line" continues; "250 line" ends the reply.
        if (strlen($clean) < 4 || $clean[3] === ' ') {
            break;
        }
    }
    $code = (int)substr($lines[0], 0, 3);
    if (!in_array($code, $codes, true)) {
        throw new RuntimeException('SMTP error: ' . implode(' / ', $lines));
    }
    return implode("\n", $lines);
}
