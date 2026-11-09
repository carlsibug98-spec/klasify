<?php
// Klasify sync API, PHP entry point.
// Every request reaches this file through .htaccess. It sends the CORS
// headers, routes the request to the matching handler, and turns errors
// into the contract's { error, code } JSON.

require __DIR__ . '/src/common.php';
require __DIR__ . '/src/auth.php';
require __DIR__ . '/src/sync.php';
require __DIR__ . '/src/admin.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method === 'OPTIONS') {
    http_response_code(204);
    exit;
}

/// The request path relative to where this API lives, e.g. "/auth/login".
function request_path(): string
{
    $uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
    $base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '')), '/');
    if ($base !== '' && str_starts_with($uri, $base)) {
        $uri = substr($uri, strlen($base));
    }
    $uri = '/' . ltrim($uri, '/');
    return strlen($uri) > 1 ? rtrim($uri, '/') : $uri;
}

/// [method, path pattern, handler]. Pattern groups become handler arguments.
$routes = [
    ['GET',    '#^/health$#', fn () => send_json(200, ['status' => 'ok', 'version' => '1.0.0'])],

    ['POST',   '#^/auth/register$#',         'auth_register'],
    ['POST',   '#^/auth/login$#',            'auth_login'],
    ['POST',   '#^/auth/google$#',           'auth_google'],
    ['POST',   '#^/auth/refresh$#',          'auth_refresh'],
    ['PATCH',  '#^/auth/me$#',               'auth_update_me'],
    ['POST',   '#^/auth/change-password$#',  'auth_change_password'],
    ['POST',   '#^/auth/forgot-password$#',  'auth_forgot_password'],
    ['POST',   '#^/auth/reset-password$#',   'auth_reset_password'],
    ['DELETE', '#^/auth/account$#',          'auth_delete_account'],

    ['POST',   '#^/sync/push$#',             'sync_push'],
    ['GET',    '#^/sync/pull$#',             'sync_pull'],

    ['GET',    '#^/admin/users$#',                              'admin_list_users'],
    ['PATCH',  '#^/admin/users/([^/]+)/role$#',                 'admin_set_role'],
    ['PATCH',  '#^/admin/users/([^/]+)/department$#',           'admin_set_department'],
    ['GET',    '#^/admin/office-statuses$#',                    'admin_list_offices'],
    ['PATCH',  '#^/admin/office-statuses/([^/]+)$#',            'admin_update_office'],
];

try {
    // Parse the body up front so malformed JSON is rejected before auth, as Express did.
    read_json_body();

    $path = request_path();
    foreach ($routes as [$verb, $pattern, $handler]) {
        if ($verb !== $method || !preg_match($pattern, $path, $matches)) {
            continue;
        }
        array_shift($matches);
        $handler(...$matches);
        exit;
    }

    send_json(404, ['error' => 'Not found', 'code' => 'NOT_FOUND']);
} catch (ApiError $e) {
    send_json($e->status, ['error' => $e->getMessage(), 'code' => $e->errorCode]);
} catch (Throwable $e) {
    app_log('ERROR ' . $e::class . ': ' . $e->getMessage() . ' in ' . $e->getFile() . ':' . $e->getLine());
    send_json(500, ['error' => 'Internal server error', 'code' => 'SERVER_ERROR']);
}
