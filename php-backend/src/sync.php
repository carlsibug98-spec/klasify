<?php
// src/sync.php
// /sync/push and /sync/pull. Every client row is upserted by its owner and
// local id; the response maps local ids to server ids. Pull returns rows
// changed since a timestamp, including soft-deleted rows so clients can
// remove them locally. The server always wins conflicts.

const CLASS_STATUS_VALUES = ['finished', 'not_attending', 'cancelled'];
const EVENT_CATEGORY_VALUES = ['personal', 'school'];
const EVENT_LEAD_OPTIONS = [5.0, 10.0, 15.0, 30.0]; // floats: js_number() returns floats

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
    $nowIso = now_iso();
    $nowDt = now_mysql();

    // The caller's role and department decide which broadcasts are allowed.
    // require_auth() already rejected deleted/missing users; failing closed
    // here too means a future auth change cannot silently grant `user` scope.
    $caller = fetch_one('SELECT role, department FROM users WHERE id = ? AND deleted = 0 LIMIT 1', [$userId]);
    if ($caller === null) {
        throw new ApiError(401, 'User not found', 'UNAUTHORIZED');
    }
    $callerIsAdmin = in_array($caller['role'], ['admin', 'super_admin'], true);

    $result = [
        'server_time' => $nowIso,
        'classes' => [],
        'events' => [],
        'class_statuses' => [],
    ];

    // --- Classes --------------------------------------------------------
    foreach (list_field($body, 'classes') as $row) {
        if (!is_array($row)) {
            continue;
        }
        $localId = $row['local_id'] ?? null;
        if (($reason = invalid_class_row($row)) !== null) {
            app_log("sync/push: skipped class row for user {$userId}: {$reason}");
            continue;
        }

        $existing = null;
        $pushServerId = push_server_id($row);
        if ($pushServerId !== null) {
            $existing = fetch_one('SELECT id FROM classes WHERE user_id = ? AND id = ? LIMIT 1', [$userId, $pushServerId]);
        }
        if ($existing === null) {
            $existing = fetch_one('SELECT id FROM classes WHERE user_id = ? AND local_id = ? LIMIT 1', [$userId, $localId]);
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
                'INSERT INTO classes (user_id, local_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
                [$userId, $localId, $subject, $room, $professor, $day, $startMin, $endMin, $deleted, $updatedAt]
            );
            $serverId = (int)db()->lastInsertId();
        }
        $result['classes'][] = ['local_id' => $localId, 'server_id' => $serverId, 'updated_at' => $clientIso];
    }

    // --- Events ---------------------------------------------------------
    foreach (list_field($body, 'events') as $row) {
        if (!is_array($row)) {
            continue;
        }
        $localId = $row['local_id'] ?? null;
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

        // Broadcasts: a department admin always posts to their own department;
        // a super admin may pick one or post school-wide.
        $wantsBroadcast = js_truthy($row['broadcast'] ?? null);
        $callerHasDepartment = $caller['department'] !== null && $caller['department'] !== '';
        $isBroadcast = $wantsBroadcast && $callerIsAdmin
            && ($caller['role'] === 'super_admin' || $callerHasDepartment);
        $broadcast = $isBroadcast ? 1 : 0;

        $department = null;
        if ($isBroadcast) {
            $department = $caller['role'] === 'super_admin'
                ? (js_truthy($row['department'] ?? null) ? nonempty_or_null(trim(js_string($row['department']))) : null)
                : nonempty_or_null(js_string($caller['department']));
        }
        $storeUserId = $isBroadcast ? null : $userId;

        $existing = null;
        $pushServerId = push_server_id($row);
        if ($pushServerId !== null) {
            $existing = fetch_one('SELECT id, user_id, department FROM events WHERE id = ? LIMIT 1', [$pushServerId]);
        }

        // Someone else's personal event is never editable from this account.
        if ($existing !== null && $existing['user_id'] !== null && (int)$existing['user_id'] !== $userId) {
            app_log("sync/push: skipped foreign event id {$pushServerId} for user {$userId}");
            $result['events'][] = ['local_id' => $localId, 'server_id' => (int)$existing['id'], 'updated_at' => $clientIso];
            continue;
        }

        // A broadcast row may only be changed by an admin whose scope covers it.
        if ($existing !== null && $existing['user_id'] === null) {
            $inScope = $caller['role'] === 'super_admin'
                || ($callerIsAdmin && $existing['department'] === $caller['department']);
            if (!$inScope || !$isBroadcast) {
                $result['events'][] = ['local_id' => $localId, 'server_id' => (int)$existing['id'], 'updated_at' => $clientIso];
                continue;
            }
        }

        if ($existing === null) {
            $existing = $storeUserId === null
                ? fetch_one(
                    'SELECT id FROM events WHERE user_id IS NULL AND local_id = ? AND department <=> ? LIMIT 1',
                    [$localId, $department]
                )
                : fetch_one(
                    'SELECT id FROM events WHERE user_id = ? AND local_id = ? LIMIT 1',
                    [$storeUserId, $localId]
                );
        }

        if ($existing !== null) {
            $serverId = (int)$existing['id'];
            // A personal event shared to the school or a department becomes a broadcast row.
            query(
                'UPDATE events SET user_id=?, title=?, venue=?, event_date=?, start_minutes=?, category=?, department=?, broadcast=?, reminder_enabled=?, lead_minutes=?, deleted=?, updated_at=? WHERE id=?',
                [$storeUserId, $title, $venue, $eventDate, $startMin, $category, $department, $broadcast, $reminder, $leadMin, $deleted, $updatedAt, $serverId]
            );
        } else {
            query(
                'INSERT INTO events (user_id, local_id, title, venue, event_date, start_minutes, category, department, broadcast, reminder_enabled, lead_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
                [$storeUserId, $localId, $title, $venue, $eventDate, $startMin, $category, $department, $broadcast, $reminder, $leadMin, $deleted, $updatedAt]
            );
            $serverId = (int)db()->lastInsertId();
        }
        $result['events'][] = ['local_id' => $localId, 'server_id' => $serverId, 'updated_at' => $clientIso];
    }

    // --- Class statuses -------------------------------------------------
    foreach (list_field($body, 'class_statuses') as $row) {
        if (!is_array($row)) {
            continue;
        }
        $localId = $row['local_id'] ?? null;
        if (($reason = invalid_status_row($row)) !== null) {
            app_log("sync/push: skipped status row for user {$userId}: {$reason}");
            continue;
        }

        $localClassId = $row['local_class_id'] ?? null;
        $status = js_string($row['status'] ?? 'finished');
        $startDate = js_string($row['start_date'] ?? substr($nowIso, 0, 10));
        $endDate = $row['end_date'] ?? null;
        $deleted = js_truthy($row['deleted'] ?? null) ? 1 : 0;
        $clientIso = $row['updated_at'] ?? $nowIso;
        $updatedAt = to_mysql_ts($row['updated_at'] ?? null) ?? $nowDt;

        // The status must point at a class the server already has. Skip it
        // otherwise; the client re-pushes it on a later sync.
        $classId = null;
        if ($localClassId !== null) {
            $classRow = fetch_one('SELECT id FROM classes WHERE user_id = ? AND local_id = ? LIMIT 1', [$userId, $localClassId]);
            if ($classRow !== null) {
                $classId = (int)$classRow['id'];
            }
        }
        if ($classId === null) {
            continue;
        }

        $existing = null;
        $pushServerId = push_server_id($row);
        if ($pushServerId !== null) {
            $existing = fetch_one('SELECT id FROM class_statuses WHERE user_id = ? AND id = ? LIMIT 1', [$userId, $pushServerId]);
        }
        if ($existing === null) {
            $existing = fetch_one('SELECT id FROM class_statuses WHERE user_id = ? AND local_id = ? LIMIT 1', [$userId, $localId]);
        }

        if ($existing !== null) {
            $serverId = (int)$existing['id'];
            query(
                'UPDATE class_statuses SET class_id=?, status=?, start_date=?, end_date=?, deleted=?, updated_at=? WHERE id=?',
                [$classId, $status, $startDate, $endDate, $deleted, $updatedAt, $serverId]
            );
        } else {
            query(
                'INSERT INTO class_statuses (user_id, local_id, class_id, local_class_id, status, start_date, end_date, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
                [$userId, $localId, $classId, $localClassId, $status, $startDate, $endDate, $deleted, $updatedAt]
            );
            $serverId = (int)db()->lastInsertId();
        }
        $result['class_statuses'][] = ['local_id' => $localId, 'server_id' => $serverId, 'updated_at' => $clientIso];
    }

    query(
        'INSERT INTO sync_cursors (user_id, device_id, last_push_at) VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE last_push_at = VALUES(last_push_at), updated_at = CURRENT_TIMESTAMP(3)',
        [$userId, js_string($body['device_id'] ?? 'unknown'), $nowDt]
    );

    send_json(200, $result);
}

// ---------------------------------------------------------------------
// GET /sync/pull?since=<iso>
// ---------------------------------------------------------------------

function sync_pull(): void
{
    $userId = require_auth();

    $since = js_text($_GET['since'] ?? null);
    if ($since === '') {
        $since = '1970-01-01T00:00:00.000Z';
    }
    $sinceDt = to_mysql_ts($since) ?? '1970-01-01 00:00:00.000';
    $nowDt = now_mysql();

    $callerRow = fetch_one('SELECT department FROM users WHERE id = ? AND deleted = 0 LIMIT 1', [$userId]);
    $callerDept = $callerRow !== null ? nonempty_or_null(js_string($callerRow['department'])) : null;

    // `since` is inclusive: re-seeing a row is harmless because client upserts are idempotent.
    $classes = fetch_all(
        'SELECT id, local_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at FROM classes WHERE user_id = ? AND updated_at >= ?',
        [$userId, $sinceDt]
    );
    $events = fetch_all(
        'SELECT id, local_id, title, venue, event_date, start_minutes, category, department, broadcast, reminder_enabled, lead_minutes, deleted, updated_at FROM events WHERE (user_id = ? OR (user_id IS NULL AND (department IS NULL OR department = ?))) AND updated_at >= ?',
        [$userId, $callerDept, $sinceDt]
    );
    $statuses = fetch_all(
        'SELECT id, local_id, class_id, local_class_id, status, start_date, end_date, deleted, updated_at FROM class_statuses WHERE user_id = ? AND updated_at >= ?',
        [$userId, $sinceDt]
    );
    $offices = fetch_all(
        'SELECT id, office_name, department, status, custom_message, updated_at, deleted FROM office_statuses WHERE (department IS NULL OR department = ?) AND updated_at >= ?',
        [$callerDept, $sinceDt]
    );

    query(
        'INSERT INTO sync_cursors (user_id, device_id, last_pull_at) VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE last_pull_at = VALUES(last_pull_at), updated_at = CURRENT_TIMESTAMP(3)',
        [$userId, js_string($_GET['device_id'] ?? 'unknown'), $nowDt]
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
            'local_class_id' => nullable_int($r['local_class_id']),
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
