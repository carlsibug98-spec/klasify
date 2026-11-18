<?php
// src/sync.php
// /sync/push and /sync/pull. Every client row is upserted by its owner and
// local id; the response maps local ids to server ids. Pull returns rows
// changed since a timestamp, including soft-deleted rows so clients can
// remove them locally. The server always wins conflicts.
//
// Identity model: a device id belongs to exactly one account and is stored in
// sync_devices. The phone's local SQLite id names a row only on that device,
// so it lives in the typed *_local_map relations, never on the entity. A
// status has no owner of its own: classes.user_id is the owner, reached
// through class_id.

const CLASS_STATUS_VALUES = ['finished', 'not_attending', 'cancelled'];
const EVENT_CATEGORY_VALUES = ['personal', 'school'];
const EVENT_LEAD_OPTIONS = [5.0, 10.0, 15.0, 30.0]; // floats: js_number() returns floats
const DEVICE_ID_PATTERN = '/^[A-Za-z0-9._:-]{1,64}\z/';

/// Tables and entity columns the local-id writers accept. Kept as a literal
/// map so a table name can never come from request data.
const LOCAL_MAP_TABLES = [
    'classes' => ['table' => 'class_local_map', 'column' => 'class_id'],
    'events' => ['table' => 'event_local_map', 'column' => 'event_id'],
    'class_statuses' => ['table' => 'status_local_map', 'column' => 'class_status_id'],
];

function trimmed_string(mixed $v): string
{
    return trim(js_string($v));
}

function is_date_key(mixed $v): bool
{
    return (bool)preg_match('/^\d{4}-\d{2}-\d{2}\z/', js_string($v));
}

/// A list from the request body, or [] when the field is missing or not a list.
function list_field(array $body, string $field): array
{
    $value = $body[$field] ?? null;
    return is_array($value) ? $value : [];
}

/// Positive server id echoed back by the client, or null.
function push_server_id(array $row): ?int
{
    if (!isset($row['server_id'])) {
        return null;
    }
    $n = js_number($row['server_id']);
    return (is_finite($n) && $n > 0) ? (int)$n : null;
}

/// Positive local id, or null when the client did not send a usable one.
function local_id_value(mixed $value): ?int
{
    $n = js_number($value);
    return (is_finite($n) && $n > 0 && floor($n) === $n) ? (int)$n : null;
}

/// A required, validated device id. Missing or malformed is 422.
function require_device_id(mixed $raw): string
{
    $id = is_string($raw) ? trim($raw) : '';
    if ($id === '' || preg_match(DEVICE_ID_PATTERN, $id) !== 1) {
        throw new ApiError(422, 'A valid device_id is required', 'DEVICE_REQUIRED');
    }
    return $id;
}

/// Records that this account owns the device, or refuses to steal it from
/// another account. Safe to call on every push and pull.
function register_device(int $userId, string $deviceId): void
{
    $row = fetch_one('SELECT user_id FROM sync_devices WHERE device_id = ? FOR UPDATE', [$deviceId]);
    if ($row !== null) {
        if ((int)$row['user_id'] !== $userId) {
            throw new ApiError(409, 'This device is linked to another account', 'DEVICE_CONFLICT');
        }
        query('UPDATE sync_devices SET last_seen_at = ? WHERE device_id = ?', [now_mysql(), $deviceId]);
        return;
    }

    try {
        query('INSERT INTO sync_devices (device_id, user_id) VALUES (?, ?)', [$deviceId, $userId]);
    } catch (PDOException $e) {
        // Two first requests on the same device raced. The winner owns it; a
        // different account still gets the conflict, never a silent claim.
        if ((int)($e->errorInfo[1] ?? 0) !== 1062) {
            throw $e;
        }
        $row = fetch_one('SELECT user_id FROM sync_devices WHERE device_id = ? LIMIT 1', [$deviceId]);
        if ($row === null || (int)$row['user_id'] !== $userId) {
            throw new ApiError(409, 'This device is linked to another account', 'DEVICE_CONFLICT');
        }
    }
}

/// Writes the one local id a device uses for one server row. A stale mapping
/// in either direction is removed first: the entity row always wins.
function map_local_row(string $entity, string $deviceId, ?int $localId, int $entityId): void
{
    if ($localId === null) {
        return;
    }
    $map = LOCAL_MAP_TABLES[$entity] ?? null;
    if ($map === null) {
        return; // programmer error; never reachable from request data
    }
    $table = $map['table'];
    $column = $map['column'];

    query(
        "DELETE FROM {$table} WHERE device_id = ? AND ((local_id = ? AND {$column} <> ?) OR ({$column} = ? AND local_id <> ?))",
        [$deviceId, $localId, $entityId, $entityId, $localId]
    );
    query(
        "INSERT INTO {$table} (device_id, local_id, {$column}) VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE {$column} = VALUES({$column})",
        [$deviceId, $localId, $entityId]
    );
}

// ---------------------------------------------------------------------
// Per-row validation. Invalid rows are skipped (and logged) so one bad row
// cannot block the rest of the push or freeze the device's cursor.
// ---------------------------------------------------------------------

function invalid_class_row(array $row): ?string
{
    $subject = trimmed_string($row['subject'] ?? null);
    if (mb_strlen($subject) < 2 || mb_strlen($subject) > 200) {
        return 'bad subject length';
    }
    $room = trimmed_string($row['room'] ?? null);
    if (mb_strlen($room) < 1 || mb_strlen($room) > 100) {
        return 'bad room length';
    }
    $professor = trimmed_string($row['professor'] ?? null);
    if (mb_strlen($professor) < 2 || mb_strlen($professor) > 200) {
        return 'bad professor length';
    }
    $day = js_number($row['day'] ?? null);
    if (!is_js_integer($day) || $day < 1 || $day > 7) {
        return 'day out of range';
    }
    $start = js_number($row['start_minutes'] ?? null);
    if (!is_js_integer($start) || $start < 0 || $start >= 1440) {
        return 'start_minutes out of range';
    }
    $end = js_number($row['end_minutes'] ?? null);
    if (!is_js_integer($end) || $end < 1 || $end > 1440 || $end <= $start) {
        return 'end_minutes out of range';
    }
    return null;
}

function invalid_event_row(array $row): ?string
{
    $title = trimmed_string($row['title'] ?? null);
    if (mb_strlen($title) < 2 || mb_strlen($title) > 200) {
        return 'bad title length';
    }
    if (mb_strlen(js_string($row['venue'] ?? null)) > 200) {
        return 'bad venue length';
    }
    $start = js_number($row['start_minutes'] ?? null);
    if (!is_js_integer($start) || $start < 0 || $start >= 1440) {
        return 'start_minutes out of range';
    }
    if (!in_array(js_string($row['category'] ?? null), EVENT_CATEGORY_VALUES, true)) {
        return 'unknown category';
    }
    if (!in_array(js_number($row['lead_minutes'] ?? null), EVENT_LEAD_OPTIONS, true)) {
        return 'bad lead_minutes';
    }
    if (!is_date_key($row['event_date'] ?? null)) {
        return 'malformed event_date';
    }
    return null;
}

function invalid_status_row(array $row): ?string
{
    if (!in_array(js_string($row['status'] ?? null), CLASS_STATUS_VALUES, true)) {
        return 'unknown status';
    }
    if (!is_date_key($row['start_date'] ?? null)) {
        return 'malformed start_date';
    }
    if (isset($row['end_date'])) {
        if (!is_date_key($row['end_date'])) {
            return 'malformed end_date';
        }
        if (strcmp(js_string($row['end_date']), js_string($row['start_date'])) < 0) {
            return 'end_date before start_date';
        }
    }
    return null;
}

// ---------------------------------------------------------------------
// POST /sync/push
// ---------------------------------------------------------------------

function sync_push(): void
{
    $userId = require_auth();
    $body = read_json_body();
    $deviceId = require_device_id($body['device_id'] ?? null);
    $nowIso = now_iso();
    $nowDt = now_mysql();

    // The caller's role and department decide which broadcasts are allowed.
    // require_auth() already rejected deleted/missing users; failing closed
    // here too means a future auth change cannot silently grant `user` scope.
    $caller = fetch_one(
        'SELECT u.role, u.department_id, d.name AS department
           FROM users u LEFT JOIN departments d ON d.id = u.department_id
          WHERE u.id = ? AND u.deleted = 0 LIMIT 1',
        [$userId]
    );
    if ($caller === null) {
        throw new ApiError(401, 'User not found', 'UNAUTHORIZED');
    }
    $callerIsAdmin = in_array($caller['role'], ['admin', 'super_admin'], true);
    $callerDeptId = nullable_int($caller['department_id']);

    $result = [
        'server_time' => $nowIso,
        'classes' => [],
        'events' => [],
        'class_statuses' => [],
    ];

    db()->beginTransaction();
    try {
        register_device($userId, $deviceId);

        // --- Classes ----------------------------------------------------
        foreach (list_field($body, 'classes') as $row) {
            if (!is_array($row)) {
                continue;
            }
            $localId = local_id_value($row['local_id'] ?? null);
            if (($reason = invalid_class_row($row)) !== null) {
                app_log("sync/push: skipped class row for user {$userId}: {$reason}");
                continue;
            }

            $existing = null;
            $pushServerId = push_server_id($row);
            if ($pushServerId !== null) {
                $existing = fetch_one(
                    'SELECT id FROM classes WHERE user_id = ? AND id = ? LIMIT 1',
                    [$userId, $pushServerId]
                );
            }
            if ($existing === null && $localId !== null) {
                $existing = fetch_one(
                    'SELECT c.id FROM class_local_map m JOIN classes c ON c.id = m.class_id
                      WHERE m.device_id = ? AND m.local_id = ? AND c.user_id = ? LIMIT 1',
                    [$deviceId, $localId, $userId]
                );
            }

            $subject = js_string($row['subject'] ?? null);
            $room = js_string($row['room'] ?? null);
            $professor = js_string($row['professor'] ?? null);
            $day = (int)js_number($row['day'] ?? 1);
            $startMin = (int)js_number($row['start_minutes'] ?? 0);
            $endMin = (int)js_number($row['end_minutes'] ?? 0);
            $deleted = js_truthy($row['deleted'] ?? null) ? 1 : 0;
            $clientIso = $row['updated_at'] ?? $nowIso;
            $updatedAt = to_mysql_ts($row['updated_at'] ?? null) ?? $nowDt;

            if ($existing !== null) {
                $serverId = (int)$existing['id'];
                query(
                    'UPDATE classes SET subject=?, room=?, professor=?, day=?, start_minutes=?, end_minutes=?, deleted=?, updated_at=? WHERE id=?',
                    [$subject, $room, $professor, $day, $startMin, $endMin, $deleted, $updatedAt, $serverId]
                );
            } else {
                query(
                    'INSERT INTO classes (user_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
                    [$userId, $subject, $room, $professor, $day, $startMin, $endMin, $deleted, $updatedAt]
                );
                $serverId = (int)db()->lastInsertId();
            }
            map_local_row('classes', $deviceId, $localId, $serverId);
            $result['classes'][] = ['local_id' => $localId, 'server_id' => $serverId, 'updated_at' => $clientIso];
        }

        // --- Events -----------------------------------------------------
        foreach (list_field($body, 'events') as $row) {
            if (!is_array($row)) {
                continue;
            }
            $localId = local_id_value($row['local_id'] ?? null);
            if (($reason = invalid_event_row($row)) !== null) {
                app_log("sync/push: skipped event row for user {$userId}: {$reason}");
                continue;
            }

            $title = js_string($row['title'] ?? null);
            $venue = js_string($row['venue'] ?? null);
            $eventDate = js_string($row['event_date'] ?? substr($nowIso, 0, 10));
            $startMin = (int)js_number($row['start_minutes'] ?? 0);
            $category = js_string($row['category'] ?? 'personal');
            $reminder = js_truthy($row['reminder_enabled'] ?? null) ? 1 : 0;
            $leadMin = (int)js_number($row['lead_minutes'] ?? 30);
            $deleted = js_truthy($row['deleted'] ?? null) ? 1 : 0;
            $clientIso = $row['updated_at'] ?? $nowIso;
            $updatedAt = to_mysql_ts($row['updated_at'] ?? null) ?? $nowDt;

            // Broadcasts: a department admin always posts to their own
            // department; a super admin may pick one or post school-wide.
            $wantsBroadcast = js_truthy($row['broadcast'] ?? null);
            $isBroadcast = $wantsBroadcast && $callerIsAdmin
                && ($caller['role'] === 'super_admin' || $callerDeptId !== null);

            $departmentId = null;
            if ($isBroadcast) {
                $departmentId = $caller['role'] === 'super_admin'
                    ? department_id_for(trim(js_string($row['department'] ?? null)))
                    : $callerDeptId;
            }
            $storeUserId = $isBroadcast ? null : $userId;

            $existing = null;
            $pushServerId = push_server_id($row);
            if ($pushServerId !== null) {
                $existing = fetch_one(
                    'SELECT id, user_id, department_id FROM events WHERE id = ? LIMIT 1',
                    [$pushServerId]
                );
            }
            if ($existing === null && $localId !== null) {
                $existing = fetch_one(
                    'SELECT e.id, e.user_id, e.department_id FROM event_local_map m
                       JOIN events e ON e.id = m.event_id
                      WHERE m.device_id = ? AND m.local_id = ? LIMIT 1',
                    [$deviceId, $localId]
                );
            }

            // Someone else's personal event is never editable from this account.
            if ($existing !== null && $existing['user_id'] !== null && (int)$existing['user_id'] !== $userId) {
                app_log("sync/push: skipped foreign event id {$pushServerId} for user {$userId}");
                $result['events'][] = ['local_id' => $localId, 'server_id' => (int)$existing['id'], 'updated_at' => $clientIso];
                continue;
            }

            // A broadcast row may only be changed by an admin whose scope covers it.
            if ($existing !== null && $existing['user_id'] === null) {
                $existingDept = nullable_int($existing['department_id']);
                $inScope = $caller['role'] === 'super_admin'
                    || ($callerIsAdmin && $existingDept === $callerDeptId);
                if (!$inScope || !$isBroadcast) {
                    $result['events'][] = ['local_id' => $localId, 'server_id' => (int)$existing['id'], 'updated_at' => $clientIso];
                    continue;
                }
            }

            if ($existing !== null) {
                $serverId = (int)$existing['id'];
                // A personal event shared to the school or a department becomes a broadcast row.
                query(
                    'UPDATE events SET user_id=?, title=?, venue=?, event_date=?, start_minutes=?, category=?, department_id=?, reminder_enabled=?, lead_minutes=?, deleted=?, updated_at=? WHERE id=?',
                    [$storeUserId, $title, $venue, $eventDate, $startMin, $category, $departmentId, $reminder, $leadMin, $deleted, $updatedAt, $serverId]
                );
            } else {
                query(
                    'INSERT INTO events (user_id, title, venue, event_date, start_minutes, category, department_id, reminder_enabled, lead_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                    [$storeUserId, $title, $venue, $eventDate, $startMin, $category, $departmentId, $reminder, $leadMin, $deleted, $updatedAt]
                );
                $serverId = (int)db()->lastInsertId();
            }
            map_local_row('events', $deviceId, $localId, $serverId);
            $result['events'][] = ['local_id' => $localId, 'server_id' => $serverId, 'updated_at' => $clientIso];
        }

        // --- Class statuses ---------------------------------------------
        foreach (list_field($body, 'class_statuses') as $row) {
            if (!is_array($row)) {
                continue;
            }
            $localId = local_id_value($row['local_id'] ?? null);
            if (($reason = invalid_status_row($row)) !== null) {
                app_log("sync/push: skipped status row for user {$userId}: {$reason}");
                continue;
            }

            // A class that reached this device by pull has a server id. Only a
            // class created offline in this push needs the map fallback.
            $classId = null;
            $serverClassId = push_server_id(['server_id' => $row['server_class_id'] ?? null]);
            if ($serverClassId !== null) {
                $classRow = fetch_one(
                    'SELECT id FROM classes WHERE user_id = ? AND id = ? LIMIT 1',
                    [$userId, $serverClassId]
                );
                if ($classRow !== null) {
                    $classId = (int)$classRow['id'];
                }
            }
            if ($classId === null) {
                $localClassId = local_id_value($row['local_class_id'] ?? null);
                if ($localClassId !== null) {
                    $classRow = fetch_one(
                        'SELECT c.id FROM class_local_map m JOIN classes c ON c.id = m.class_id
                          WHERE m.device_id = ? AND m.local_id = ? AND c.user_id = ? LIMIT 1',
                        [$deviceId, $localClassId, $userId]
                    );
                    if ($classRow !== null) {
                        $classId = (int)$classRow['id'];
                    }
                }
            }
            if ($classId === null) {
                continue;
            }

            $status = js_string($row['status'] ?? 'finished');
            $startDate = js_string($row['start_date'] ?? substr($nowIso, 0, 10));
            $endDate = $row['end_date'] ?? null;
            $deleted = js_truthy($row['deleted'] ?? null) ? 1 : 0;
            $clientIso = $row['updated_at'] ?? $nowIso;
            $updatedAt = to_mysql_ts($row['updated_at'] ?? null) ?? $nowDt;

            $existing = null;
            $pushServerId = push_server_id($row);
            if ($pushServerId !== null) {
                $existing = fetch_one(
                    'SELECT s.id FROM class_statuses s JOIN classes c ON c.id = s.class_id
                      WHERE c.user_id = ? AND s.id = ? LIMIT 1',
                    [$userId, $pushServerId]
                );
            }
            if ($existing === null && $localId !== null) {
                $existing = fetch_one(
                    'SELECT s.id FROM status_local_map m
                       JOIN class_statuses s ON s.id = m.class_status_id
                       JOIN classes c ON c.id = s.class_id
                      WHERE m.device_id = ? AND m.local_id = ? AND c.user_id = ? LIMIT 1',
                    [$deviceId, $localId, $userId]
                );
            }

            if ($existing !== null) {
                $serverId = (int)$existing['id'];
                query(
                    'UPDATE class_statuses SET class_id=?, status=?, start_date=?, end_date=?, deleted=?, updated_at=? WHERE id=?',
                    [$classId, $status, $startDate, $endDate, $deleted, $updatedAt, $serverId]
                );
            } else {
                query(
                    'INSERT INTO class_statuses (class_id, status, start_date, end_date, deleted, updated_at) VALUES (?,?,?,?,?,?)',
                    [$classId, $status, $startDate, $endDate, $deleted, $updatedAt]
                );
                $serverId = (int)db()->lastInsertId();
            }
            map_local_row('class_statuses', $deviceId, $localId, $serverId);
            $result['class_statuses'][] = ['local_id' => $localId, 'server_id' => $serverId, 'updated_at' => $clientIso];
        }

        query(
            'INSERT INTO sync_cursors (device_id, last_push_at) VALUES (?, ?)
             ON DUPLICATE KEY UPDATE last_push_at = VALUES(last_push_at), updated_at = CURRENT_TIMESTAMP(3)',
            [$deviceId, $nowDt]
        );

        db()->commit();
    } catch (Throwable $e) {
        db()->rollBack();
        throw $e;
    }

    send_json(200, $result);
}

// ---------------------------------------------------------------------
// GET /sync/pull?since=<iso>&device_id=<id>
// ---------------------------------------------------------------------

function sync_pull(): void
{
    $userId = require_auth();
    $deviceId = require_device_id($_GET['device_id'] ?? null);

    $since = js_text($_GET['since'] ?? null);
    if ($since === '') {
        $since = '1970-01-01T00:00:00.000Z';
    }
    $sinceDt = to_mysql_ts($since) ?? '1970-01-01 00:00:00.000';
    $nowDt = now_mysql();

    $callerRow = fetch_one(
        'SELECT u.department_id, d.name AS department
           FROM users u LEFT JOIN departments d ON d.id = u.department_id
          WHERE u.id = ? AND u.deleted = 0 LIMIT 1',
        [$userId]
    );
    $callerDeptId = $callerRow !== null ? nullable_int($callerRow['department_id']) : null;

    register_device($userId, $deviceId);
    query(
        'INSERT INTO sync_cursors (device_id, last_pull_at) VALUES (?, ?)
         ON DUPLICATE KEY UPDATE last_pull_at = VALUES(last_pull_at), updated_at = CURRENT_TIMESTAMP(3)',
        [$deviceId, $nowDt]
    );

    // `since` is inclusive: re-seeing a row is harmless because client upserts are idempotent.
    $classes = fetch_all(
        'SELECT c.id, m.local_id, c.subject, c.room, c.professor, c.day, c.start_minutes, c.end_minutes, c.deleted, c.updated_at
           FROM classes c
           LEFT JOIN class_local_map m ON m.class_id = c.id AND m.device_id = ?
          WHERE c.user_id = ? AND c.updated_at >= ?',
        [$deviceId, $userId, $sinceDt]
    );
    $events = fetch_all(
        'SELECT e.id, m.local_id, e.title, e.venue, e.event_date, e.start_minutes, e.category,
                d.name AS department, e.broadcast, e.reminder_enabled, e.lead_minutes, e.deleted, e.updated_at
           FROM events e
           LEFT JOIN event_local_map m ON m.event_id = e.id AND m.device_id = ?
           LEFT JOIN departments d ON d.id = e.department_id
          WHERE (e.user_id = ? OR (e.user_id IS NULL AND (e.department_id IS NULL OR e.department_id <=> ?)))
            AND e.updated_at >= ?',
        [$deviceId, $userId, $callerDeptId, $sinceDt]
    );
    $statuses = fetch_all(
        'SELECT s.id, m.local_id, s.class_id, s.status, s.start_date, s.end_date, s.deleted, s.updated_at
           FROM class_statuses s
           JOIN classes c ON c.id = s.class_id
           LEFT JOIN status_local_map m ON m.class_status_id = s.id AND m.device_id = ?
          WHERE c.user_id = ? AND s.updated_at >= ?',
        [$deviceId, $userId, $sinceDt]
    );
    // Offices are a handful of cache rows: return the full in-scope set on
    // every pull so a rename, retirement, or one-time v11 adoption reaches a
    // phone whose cache predates this schema.
    $offices = fetch_all(
        'SELECT o.id, o.office_name, d.name AS department, o.status, o.custom_message, o.updated_at, o.deleted
           FROM office_statuses o
           LEFT JOIN departments d ON d.id = o.department_id
          WHERE (o.department_id IS NULL OR o.department_id <=> ?)',
        [$callerDeptId]
    );

    send_json(200, [
        'server_time' => now_iso(),
        'classes' => array_map(fn (array $r) => [
            'id' => (int)$r['id'],
            'local_id' => nullable_int($r['local_id']),
            'subject' => $r['subject'],
            'room' => $r['room'],
            'professor' => $r['professor'],
            'day' => (int)$r['day'],
            'start_minutes' => (int)$r['start_minutes'],
            'end_minutes' => (int)$r['end_minutes'],
            'deleted' => (bool)(int)$r['deleted'],
            'updated_at' => from_mysql_ts_to_iso($r['updated_at']) ?? $r['updated_at'],
        ], $classes),
        'events' => array_map(fn (array $r) => [
            'id' => (int)$r['id'],
            'local_id' => nullable_int($r['local_id']),
            'title' => $r['title'],
            'venue' => $r['venue'],
            'event_date' => $r['event_date'],
            'start_minutes' => (int)$r['start_minutes'],
            'category' => $r['category'],
            'department' => nonempty_or_null(js_string($r['department'])),
            'broadcast' => (bool)(int)$r['broadcast'],
            'reminder_enabled' => (bool)(int)$r['reminder_enabled'],
            'lead_minutes' => (int)$r['lead_minutes'],
            'deleted' => (bool)(int)$r['deleted'],
            'updated_at' => from_mysql_ts_to_iso($r['updated_at']) ?? $r['updated_at'],
        ], $events),
        'class_statuses' => array_map(fn (array $r) => [
            'id' => (int)$r['id'],
            'local_id' => nullable_int($r['local_id']),
            'class_id' => nullable_int($r['class_id']),
            'status' => $r['status'],
            'start_date' => $r['start_date'],
            'end_date' => $r['end_date'],
            'deleted' => (bool)(int)$r['deleted'],
            'updated_at' => from_mysql_ts_to_iso($r['updated_at']) ?? $r['updated_at'],
        ], $statuses),
        'office_statuses' => array_map(fn (array $r) => [
            'id' => (int)$r['id'],
            'office_name' => $r['office_name'],
            'department' => nonempty_or_null(js_string($r['department'])),
            'status' => $r['status'],
            'custom_message' => $r['custom_message'],
            'updated_at' => from_mysql_ts_to_iso($r['updated_at']) ?? $r['updated_at'],
            'deleted' => (bool)(int)$r['deleted'],
        ], $offices),
    ]);
}

function nullable_int(mixed $v): ?int
{
    return $v === null ? null : (int)$v;
}
