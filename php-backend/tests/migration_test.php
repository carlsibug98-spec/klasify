<?php
// tests/migration_test.php
// The normalization migration is one-shot and runs against real production
// data, so it is tested against the real pre-normalization schema with the
// row shapes that schema allowed: duplicate school-wide offices, department
// spellings that differ only by whitespace, a phone shared by two accounts,
// and several reset codes per user.
//
// Each test builds two scratch databases:
//
//   klasify_migration_pre    legacy schema + legacy rows + the migration
//   klasify_migration_fresh  docs/mysql_schema.sql, i.e. a new install
//
// The last test proves the migrated structure equals the fresh one. The
// scratch databases are left in place for inspection; the next run drops and
// recreates them.

declare(strict_types=1);

const MIGRATION_SQL = __DIR__ . '/../migrations/2026-11-18-normalize.sql';
const LEGACY_SCHEMA_SQL = __DIR__ . '/fixtures/mysql_schema_pre_normalize.sql';
const MIGRATION_DB_PRE = 'klasify_migration_pre';
const MIGRATION_DB_FRESH = 'klasify_migration_fresh';

/// A connection to the server, optionally bound to one database.
function migration_pdo(?string $database = null): PDO
{
    $dsn = sprintf('mysql:host=%s;port=%d;charset=utf8mb4', cfg('db_host'), (int)cfg('db_port'));
    if ($database !== null) {
        $dsn .= ';dbname=' . $database;
    }
    return new PDO($dsn, cfg('db_user'), cfg('db_pass'), [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
}

/// Executes a .sql file statement by statement, stripping `--` comments the
/// same way the harness does. With $skipDatabaseStatements the file's own
/// CREATE DATABASE / USE lines are ignored so the caller picks the database.
function migration_exec_file(PDO $pdo, string $path, bool $skipDatabaseStatements = false): void
{
    $sql = file_get_contents($path);
    throw_unless($sql !== false, 'cannot read ' . basename($path));
    $lines = [];
    foreach (explode("\n", $sql) as $line) {
        $commentAt = strpos($line, '--');
        $lines[] = $commentAt === false ? $line : substr($line, 0, $commentAt);
    }
    foreach (explode(';', implode("\n", $lines)) as $statement) {
        if (trim($statement) === '') {
            continue;
        }
        if ($skipDatabaseStatements && preg_match('/^(CREATE\s+DATABASE|USE)\b/i', ltrim($statement))) {
            continue;
        }
        $pdo->exec($statement);
    }
}

/// Recreates both scratch databases and returns the legacy one, loaded from
/// the pre-normalization fixture and ready to seed.
function migration_legacy_db(): PDO
{
    $server = migration_pdo();
    foreach ([MIGRATION_DB_PRE, MIGRATION_DB_FRESH] as $database) {
        $server->exec("DROP DATABASE IF EXISTS `{$database}`");
        $server->exec("CREATE DATABASE `{$database}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
    }
    $legacy = migration_pdo(MIGRATION_DB_PRE);
    migration_exec_file($legacy, LEGACY_SCHEMA_SQL);
    return $legacy;
}

/// Runs the production migration exactly once, as the deployment does.
function migration_apply(PDO $pdo): void
{
    migration_exec_file($pdo, MIGRATION_SQL);
}

/// Loads the documented schema into the fresh database.
function migration_fresh_db(): PDO
{
    $fresh = migration_pdo(MIGRATION_DB_FRESH);
    migration_exec_file($fresh, dirname(__DIR__, 2) . '/docs/mysql_schema.sql', true);
    return $fresh;
}

/// One row (or null) from a scratch database.
function migration_row(PDO $pdo, string $sql, array $params = []): ?array
{
    $statement = $pdo->prepare($sql);
    $statement->execute($params);
    $row = $statement->fetch();
    return $row === false ? null : $row;
}

/// One scalar value (or null) from a scratch database.
function migration_value(PDO $pdo, string $sql, array $params = []): mixed
{
    $row = migration_row($pdo, $sql, $params);
    return $row === null ? null : reset($row);
}

/// SHOW CREATE TABLE/VIEW for every relation, normalized so AUTO_INCREMENT
/// counters and view definers do not create false differences.
function migration_structure(PDO $pdo): array
{
    $structure = [];
    foreach ($pdo->query('SHOW FULL TABLES')->fetchAll(PDO::FETCH_NUM) as [$name, $kind]) {
        $row = $pdo->query(
            ($kind === 'VIEW' ? 'SHOW CREATE VIEW `' : 'SHOW CREATE TABLE `') . $name . '`'
        )->fetch(PDO::FETCH_NUM);
        $ddl = (string)($row[1] ?? '');
        $ddl = (string)preg_replace('/\s+AUTO_INCREMENT=\d+/', '', $ddl);
        $ddl = (string)preg_replace('/DEFINER=`[^`]*`@`[^`]*`\s*/', '', $ddl);
        $structure[$name] = trim((string)preg_replace('/\s+/', ' ', $ddl));
    }
    ksort($structure);
    return $structure;
}

T()->test('offices merge by normalized scope before the total unique key', function () {
    $pre = migration_legacy_db();
    $pre->exec(
        "INSERT INTO users (email, password_hash, display_name, role, department)
         VALUES ('mig-office@test.com', 'x', 'Mig', 'admin', ' it ')"
    );

    // Every row below was legal under the old key. The same office appears
    // twice with department spellings that differ only by whitespace, and a
    // school-wide office appears twice because MySQL allows repeated NULLs.
    $pre->exec(
        "INSERT INTO office_statuses (office_name, department, status, custom_message, updated_at) VALUES
         ('guidance', ' IT', 'open',   'leading space, older',  '2026-11-01 08:00:00.000'),
         ('guidance', 'IT ', 'break',  'trailing space, newer', '2026-11-02 08:00:00.000'),
         ('guidance', NULL,  'closed', 'school-wide',           '2026-11-03 08:00:00.000'),
         ('canteen',  NULL,  'open',   'older school row',      '2026-11-01 08:00:00.000'),
         ('canteen',  NULL,  'break',  'newest school row',     '2026-11-04 08:00:00.000')"
    );

    migration_apply($pre);

    T()->eq(1, (int)migration_value($pre, 'SELECT COUNT(*) FROM departments'), 'one department for IT/it/whitespace variants');
    $departmentId = (int)migration_value($pre, 'SELECT id FROM departments LIMIT 1');

    T()->eq(
        2,
        (int)migration_value($pre, "SELECT COUNT(*) FROM office_statuses WHERE office_name = 'guidance'"),
        'school-wide and department guidance both survive'
    );
    $scoped = migration_row(
        $pre,
        "SELECT department_id, custom_message FROM office_statuses
          WHERE office_name = 'guidance' AND department_id IS NOT NULL"
    );
    T()->truthy($scoped !== null, 'department-scoped guidance exists');
    T()->eq($departmentId, (int)$scoped['department_id'], 'scoped guidance points at the single department');
    T()->eq('trailing space, newer', $scoped['custom_message'], 'newest scoped row wins the merge');

    $schoolWide = migration_row(
        $pre,
        "SELECT custom_message FROM office_statuses
          WHERE office_name = 'guidance' AND department_id IS NULL"
    );
    T()->eq('school-wide', $schoolWide['custom_message'] ?? null, 'school-wide guidance untouched');

    T()->eq(
        1,
        (int)migration_value($pre, "SELECT COUNT(*) FROM office_statuses WHERE office_name = 'canteen'"),
        'duplicate school-wide rows collapse'
    );
    T()->eq(
        'newest school row',
        migration_value($pre, "SELECT custom_message FROM office_statuses WHERE office_name = 'canteen'"),
        'newest school-wide row wins'
    );
    T()->eq(3, (int)migration_value($pre, 'SELECT COUNT(*) FROM office_statuses'), 'no other office row lost');
    T()->eq(
        0,
        (int)migration_value(
            $pre,
            "SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'office_statuses' AND COLUMN_NAME = 'department'"
        ),
        'the text department column is gone'
    );
});

T()->test('migration maps every department source and derives broadcast', function () {
    $pre = migration_legacy_db();
    $pre->exec(
        "INSERT INTO users (email, password_hash, display_name, role, department) VALUES
         ('mig-dept-a@test.com', 'x', 'A', 'user',   'Physics'),
         ('mig-dept-b@test.com', 'x', 'B', 'user',   'physics '),
         ('mig-dept-c@test.com', 'x', 'C', 'user',   NULL),
         ('mig-dept-d@test.com', 'x', 'D', 'user',   '')"
    );
    $physicsUser = (int)migration_value($pre, "SELECT id FROM users WHERE email = 'mig-dept-a@test.com'");

    // The legacy events table allowed a stored broadcast flag that disagreed
    // with user_id, and a department string no user had (Chemistry).
    $pre->exec(
        "INSERT INTO events (user_id, title, venue, event_date, start_minutes, category, department, broadcast) VALUES
         ({$physicsUser}, 'Personal with dept', '', '2026-11-18', 480, 'personal', 'Chemistry', 0),
         ({$physicsUser}, 'False broadcast',    '', '2026-11-19', 540, 'school',   NULL,        1),
         (NULL,           'Real broadcast',     '', '2026-11-20', 600, 'school',   'physics',   1)"
    );
    $pre->exec(
        "INSERT INTO classes (user_id, subject, room, professor, day, start_minutes, end_minutes)
         VALUES ({$physicsUser}, 'Algebra', 'R1', 'Prof A', 1, 480, 540)"
    );
    $classId = (int)migration_value($pre, 'SELECT id FROM classes LIMIT 1');
    $pre->exec(
        "INSERT INTO class_statuses (user_id, class_id, status, start_date, local_id, local_class_id)
         VALUES ({$physicsUser}, {$classId}, 'finished', '2026-11-18', 7, 3),
                ({$physicsUser}, {$classId}, 'cancelled', '2026-11-19', 8, 3)"
    );

    migration_apply($pre);

    T()->eq(2, (int)migration_value($pre, 'SELECT COUNT(*) FROM departments'), 'users and events contribute departments once each');
    $physicsId = (int)migration_value($pre, "SELECT id FROM departments WHERE name = 'Physics'");
    $chemistryId = (int)migration_value($pre, "SELECT id FROM departments WHERE name = 'Chemistry'");
    T()->truthy($physicsId > 0 && $chemistryId > 0, 'both department names exist');

    $userDepartmentIds = array_map(
        fn (array $row) => $row['department_id'] === null ? null : (int)$row['department_id'],
        $pre->query('SELECT department_id FROM users ORDER BY id')->fetchAll(PDO::FETCH_ASSOC)
    );
    T()->eq(
        [$physicsId, $physicsId, null, null],
        $userDepartmentIds,
        'users share the department relation; blank and NULL stay unassigned'
    );

    T()->eq(
        $chemistryId,
        (int)migration_value($pre, "SELECT department_id FROM events WHERE title = 'Personal with dept'"),
        'event-only department is created and linked'
    );
    T()->eq(
        $physicsId,
        (int)migration_value($pre, "SELECT department_id FROM events WHERE title = 'Real broadcast'"),
        'department scope resolved for broadcast rows'
    );

    $broadcasts = $pre->query('SELECT title, broadcast FROM events ORDER BY id')->fetchAll(PDO::FETCH_KEY_PAIR);
    T()->eq(0, (int)$broadcasts['Personal with dept'], 'owned event is not a broadcast');
    T()->eq(0, (int)$broadcasts['False broadcast'], 'stored flag disagreement resolves to user_id');
    T()->eq(1, (int)$broadcasts['Real broadcast'], 'unowned event is a broadcast');

    $classStatusColumns = array_column(
        $pre->query('SHOW COLUMNS FROM class_statuses')->fetchAll(PDO::FETCH_ASSOC),
        'Field'
    );
    T()->truthy(
        !in_array('user_id', $classStatusColumns, true)
        && !in_array('local_id', $classStatusColumns, true)
        && !in_array('local_class_id', $classStatusColumns, true),
        'status ownership is derived; device ids moved to maps'
    );
    T()->eq(2, (int)migration_value($pre, 'SELECT COUNT(*) FROM class_statuses'), 'marks preserved');
    T()->eq(
        $classId,
        (int)migration_value($pre, 'SELECT DISTINCT class_id FROM class_statuses'),
        'marks still point at their class'
    );
    T()->eq(3, (int)migration_value($pre, 'SELECT COUNT(*) FROM active_events'), 'recreated view reads the derived column');
});

T()->test('one device has one owner, one cursor, and one reset code', function () {
    $pre = migration_legacy_db();
    $pre->exec(
        "INSERT INTO users (email, password_hash, display_name, role) VALUES
         ('mig-dev-a@test.com', 'x', 'A', 'user'),
         ('mig-dev-b@test.com', 'x', 'B', 'user')"
    );
    $userA = (int)migration_value($pre, "SELECT id FROM users WHERE email = 'mig-dev-a@test.com'");
    $userB = (int)migration_value($pre, "SELECT id FROM users WHERE email = 'mig-dev-b@test.com'");

    // The same phone signed into two accounts: the device can only belong to
    // the account that used it last.
    $pre->exec(
        "INSERT INTO sync_cursors (user_id, device_id, last_push_at, last_pull_at, created_at, updated_at) VALUES
         ({$userA}, 'shared-phone', '2026-11-01 10:00:00.000', '2026-11-01 10:00:00.000', '2026-11-01 09:00:00.000', '2026-11-01 10:00:00.000'),
         ({$userB}, 'shared-phone', '2026-11-05 10:00:00.000', '2026-11-05 10:00:00.000', '2026-11-02 09:00:00.000', '2026-11-05 10:00:00.000'),
         ({$userA}, 'tablet',       '2026-11-03 10:00:00.000', NULL,                         '2026-11-03 09:00:00.000', '2026-11-03 10:00:00.000')"
    );

    $pre->exec(
        "INSERT INTO password_resets (user_id, code_hash, created_at, expires_at, used_at) VALUES
         ({$userA}, 'used-code',   '2026-11-01 09:00:00.000', '2026-11-01 09:15:00.000', '2026-11-01 09:05:00.000'),
         ({$userA}, 'older-code',  '2026-11-01 09:10:00.000', '2026-11-01 09:25:00.000', NULL),
         ({$userA}, 'newest-code', '2026-11-01 09:20:00.000', '2026-11-01 09:35:00.000', NULL)"
    );

    $pre->exec("INSERT INTO rate_limit_hits (bucket, hit_at) VALUES ('forgot:a@test.com', '2026-11-01 09:00:00.000')");

    migration_apply($pre);

    T()->eq(2, (int)migration_value($pre, 'SELECT COUNT(*) FROM sync_devices'), 'one device row per device id');
    T()->eq(
        $userB,
        (int)migration_value($pre, "SELECT user_id FROM sync_devices WHERE device_id = 'shared-phone'"),
        'most recently active account owns the shared phone'
    );
    T()->eq(2, (int)migration_value($pre, 'SELECT COUNT(*) FROM sync_cursors'), 'one cursor per device');
    T()->eq(
        '2026-11-05 10:00:00.000',
        (string)migration_value($pre, "SELECT last_pull_at FROM sync_cursors WHERE device_id = 'shared-phone'"),
        'cursor keeps the newest pull time across accounts'
    );
    $cursorColumns = array_column($pre->query('SHOW COLUMNS FROM sync_cursors')->fetchAll(PDO::FETCH_ASSOC), 'Field');
    T()->truthy(!in_array('user_id', $cursorColumns, true), 'cursor has no user_id');

    T()->eq(1, (int)migration_value($pre, 'SELECT COUNT(*) FROM password_resets'), 'one live code per user');
    T()->eq('newest-code', migration_value($pre, 'SELECT code_hash FROM password_resets'), 'newest unused code survives');
    T()->eq(
        900,
        (int)migration_value($pre, 'SELECT ttl_seconds FROM password_resets'),
        'remaining lifetime becomes the stored policy'
    );

    foreach (['class_local_map', 'event_local_map', 'status_local_map'] as $map) {
        T()->eq(0, (int)migration_value($pre, "SELECT COUNT(*) FROM `{$map}`"), "{$map} starts empty");
    }

    T()->eq(0, (int)migration_value($pre, 'SELECT COUNT(*) FROM rate_limit_hits'), 'legacy counters are reset');
    $rateColumns = array_column($pre->query('SHOW COLUMNS FROM rate_limit_hits')->fetchAll(PDO::FETCH_ASSOC), 'Field');
    T()->truthy(
        in_array('scope', $rateColumns, true) && in_array('subject', $rateColumns, true)
        && !in_array('bucket', $rateColumns, true),
        'rate limit key is split'
    );

    $officeColumns = array_column($pre->query('SHOW COLUMNS FROM office_statuses')->fetchAll(PDO::FETCH_ASSOC), 'Field');
    T()->truthy(
        in_array('department_id', $officeColumns, true) && in_array('scope_key', $officeColumns, true),
        'office scope is a relation plus a derived total key'
    );
});

T()->test('migrated schema is structurally identical to a fresh install', function () {
    $pre = migration_legacy_db();
    migration_apply($pre);
    $fresh = migration_fresh_db();

    $migratedStructure = migration_structure($pre);
    $freshStructure = migration_structure($fresh);

    T()->eq(array_keys($freshStructure), array_keys($migratedStructure), 'same relation set');
    foreach ($freshStructure as $relation => $ddl) {
        T()->eq($ddl, $migratedStructure[$relation] ?? null, "same definition for {$relation}");
    }
});
