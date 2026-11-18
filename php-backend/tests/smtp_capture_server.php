<?php
// tests/smtp_capture_server.php
//
// A real (if very small) SMTP server for the password-reset mail test. It
// binds 127.0.0.1 on an ephemeral port, speaks enough of RFC 5321 for the
// client in src/mail.php, and writes the DATA payload to a file. The test
// launches it with proc_open, so delivery is a genuine socket conversation,
// not a stubbed function.
//
// Usage: php smtp_capture_server.php <port|0> <output-file>

declare(strict_types=1);

$port = (int)($argv[1] ?? 0);
$output = $argv[2] ?? '';

$server = @stream_socket_server(
    'tcp://127.0.0.1:' . $port,
    $errno,
    $errstr,
    STREAM_SERVER_BIND | STREAM_SERVER_LISTEN
);
if ($server === false) {
    fwrite(STDERR, "bind failed: {$errstr} ({$errno})\n");
    exit(1);
}

$name = (string)stream_socket_get_name($server, false);
$actualPort = (int)substr($name, strrpos($name, ':') + 1);
echo "READY {$actualPort}\n";
fflush(STDOUT);

$client = @stream_socket_accept($server, 25);
if ($client === false) {
    fwrite(STDERR, "no client connected\n");
    fclose($server);
    exit(2);
}
stream_set_timeout($client, 25);

function reply($client, string $line): void
{
    fwrite($client, $line . "\r\n");
}

reply($client, '220 capture.local ESMTP ready');

$data = '';
$inData = false;
$authStage = 0;

while (!feof($client)) {
    $line = fgets($client, 8192);
    if ($line === false) {
        break;
    }

    if ($inData) {
        if (rtrim($line, "\r\n") === '.') {
            $inData = false;
            reply($client, '250 2.0.0 queued');
            continue;
        }
        $data .= $line;
        continue;
    }

    $command = rtrim($line, "\r\n");

    // Lines after AUTH LOGIN are base64 credentials, not commands.
    if ($authStage === 1) {
        $authStage = 2;
        reply($client, '334 UGFzc3dvcmQ6');
        continue;
    }
    if ($authStage === 2) {
        $authStage = 3;
        reply($client, '235 2.7.0 authenticated');
        continue;
    }

    $upper = strtoupper($command);
    if (str_starts_with($upper, 'EHLO')) {
        fwrite($client, "250-capture.local\r\n250-SIZE 10485760\r\n250 HELP\r\n");
    } elseif (str_starts_with($upper, 'HELO')) {
        reply($client, '250 capture.local');
    } elseif (str_starts_with($upper, 'AUTH LOGIN')) {
        $authStage = 1;
        reply($client, '334 VXNlcm5hbWU6');
    } elseif (str_starts_with($upper, 'MAIL FROM:')) {
        reply($client, '250 2.1.0 sender ok');
    } elseif (str_starts_with($upper, 'RCPT TO:')) {
        reply($client, '250 2.1.5 recipient ok');
    } elseif ($upper === 'DATA') {
        $inData = true;
        reply($client, '354 end data with <CRLF>.<CRLF>');
    } elseif ($upper === 'QUIT') {
        reply($client, '221 2.0.0 bye');
        break;
    } elseif ($upper === 'RSET' || $upper === 'NOOP') {
        reply($client, '250 2.0.0 ok');
    } else {
        reply($client, '502 5.5.2 command not implemented');
    }
}

fclose($client);
fclose($server);

if ($output !== '') {
    file_put_contents($output, $data);
}
exit(0);
