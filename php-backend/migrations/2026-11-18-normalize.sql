-- Klasify normalization migration — 2026-11-18
--
-- This is a ONE-SHOT migration from the pre-normalization schema to the
-- strict 1NF/2NF/3NF/BCNF shape documented in docs/mysql_schema.sql.
-- It is not re-runnable: it rebuilds tables, so a second run fails on the
-- first already-dropped column.
--
-- BEFORE RUNNING
--   1. Stop the API (or put it in maintenance). DDL commits implicitly in
--      MySQL/MariaDB; a request landing mid-migration can write to a table
--      that is about to be replaced.
--   2. Back up the database:
--
--        mysqldump -h 127.0.0.1 -u root \
--          --databases klasify_sync --routines --triggers \
--          > klasify_sync_pre_normalize_2026-11-18.sql
--
--   3. Select the target database, then run this file:
--
--        USE klasify_sync;
--        SOURCE php-backend/migrations/2026-11-18-normalize.sql;
--
-- WHAT CHANGES
--   * Departments become a relation. users/events/office_statuses store
--     department_id; the old text column is backfilled and dropped. The wire
--     payload still carries the department NAME.
--   * Device identity becomes a relation (sync_devices). sync_cursors loses
--     user_id; the *_local_map tables are the only place a phone's local id
--     is stored, keyed by device.
--   * class_statuses loses user_id (ownership is classes.user_id), local_id
--     and local_class_id. Old local ids are NOT backfilled: the old schema
--     never recorded which device wrote a row, so any mapping would be a
--     guess. Phones re-map themselves on their first push after upgrading.
--   * events.broadcast becomes a VIRTUAL generated column derived from
--     user_id, and office_statuses.scope_key derives the COALESCE needed for
--     a total unique key. Neither stores a second copy of a fact.
--   * password_resets becomes one row per user (user_id PK) with
--     ttl_seconds; expires_at/used_at are gone. Only the newest unused code
--     per user is kept.
--   * rate_limit_hits splits the packed bucket into scope + subject. Old
--     counters are dropped: they are short-lived throttling state, and their
--     bucket strings do not map cleanly to the new (scope, subject) pairs.
--   * Duplicate school-wide office rows (allowed by the old NULL-tolerant
--     unique key) are collapsed to the most recently updated row before the
--     total unique key is added.

-- ---------------------------------------------------------------------------
-- 1. Departments: the relation every department scope now points at.
-- ---------------------------------------------------------------------------
CREATE TABLE departments (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  created_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  UNIQUE KEY uq_departments_name (name)
) ENGINE=InnoDB;

-- One row per spelling. The collation is case-insensitive, so "IT" and "it"
-- collapse into a single department instead of two.
INSERT IGNORE INTO departments (name)
SELECT DISTINCT TRIM(department)
  FROM users
 WHERE department IS NOT NULL AND TRIM(department) <> '';

INSERT IGNORE INTO departments (name)
SELECT DISTINCT TRIM(department)
  FROM events
 WHERE department IS NOT NULL AND TRIM(department) <> '';

INSERT IGNORE INTO departments (name)
SELECT DISTINCT TRIM(department)
  FROM office_statuses
 WHERE department IS NOT NULL AND TRIM(department) <> '';

-- ---------------------------------------------------------------------------
-- 2. users.department -> users.department_id
-- ---------------------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN department_id BIGINT UNSIGNED NULL AFTER role,
  DROP KEY idx_users_department,
  ADD KEY idx_users_department (department_id);

UPDATE users u
  JOIN departments d ON d.name = TRIM(u.department)
   SET u.department_id = d.id;

ALTER TABLE users
  ADD CONSTRAINT fk_users_department
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;

ALTER TABLE users DROP COLUMN department;

-- The fresh schema enforces the role set; a migrated database must too.
ALTER TABLE users
  ADD CONSTRAINT chk_users_role CHECK (role IN ('user', 'admin', 'super_admin'));

-- ---------------------------------------------------------------------------
-- 3. events.department -> events.department_id, and a derived broadcast flag
-- ---------------------------------------------------------------------------
ALTER TABLE events
  ADD COLUMN department_id BIGINT UNSIGNED NULL AFTER category,
  ADD KEY idx_events_department (department_id);

UPDATE events e
  JOIN departments d ON d.name = TRIM(e.department)
   SET e.department_id = d.id;

ALTER TABLE events
  ADD CONSTRAINT fk_events_department
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;

-- The stored broadcast flag is replaced by a derived column. Any legacy row
-- that disagreed with user_id IS NULL now reports the truth.
ALTER TABLE events
  DROP COLUMN department,
  DROP COLUMN broadcast;

ALTER TABLE events
  ADD COLUMN broadcast TINYINT(1)
      AS (CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) VIRTUAL;

-- ---------------------------------------------------------------------------
-- 4. office_statuses: collapse duplicates, department_id, total unique key
-- ---------------------------------------------------------------------------

-- The old unique key (office_name, department) let any number of school-wide
-- rows through, because SQL treats every NULL as distinct. Keep only the
-- most recently updated row for each (name, scope).
DELETE older
  FROM office_statuses older
  JOIN office_statuses newer
    ON newer.office_name = older.office_name
   AND newer.department <=> older.department
   AND (newer.updated_at > older.updated_at
        OR (newer.updated_at = older.updated_at AND newer.id > older.id));

ALTER TABLE office_statuses
  ADD COLUMN department_id BIGINT UNSIGNED NULL AFTER office_name,
  ADD KEY idx_office_department (department_id);

UPDATE office_statuses o
  JOIN departments d ON d.name = TRIM(o.department)
   SET o.department_id = d.id;

ALTER TABLE office_statuses
  ADD CONSTRAINT fk_office_department
  FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;

ALTER TABLE office_statuses DROP KEY uq_office;

ALTER TABLE office_statuses
  DROP COLUMN department,
  ADD COLUMN scope_key BIGINT UNSIGNED
      AS (COALESCE(department_id, 0)) VIRTUAL,
  ADD UNIQUE KEY uq_office (office_name, scope_key);

-- ---------------------------------------------------------------------------
-- 5. class_statuses: derive ownership from classes, drop device-local ids
-- ---------------------------------------------------------------------------
-- Rebuilt rather than altered: dropping three columns and the user_id foreign
-- key is clearer, and it makes the surviving foreign key's name deterministic
-- (auto-generated constraint names differ between installs).
CREATE TABLE class_statuses_new (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  class_id    BIGINT UNSIGNED NOT NULL,
  status      ENUM('finished','not_attending','cancelled') NOT NULL,
  start_date  DATE            NOT NULL,
  end_date    DATE            NULL,
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted     TINYINT(1)      NOT NULL DEFAULT 0,

  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  KEY idx_cs_class_updated (class_id, updated_at),
  CHECK (end_date IS NULL OR end_date >= start_date)
) ENGINE=InnoDB;

INSERT INTO class_statuses_new
  (id, class_id, status, start_date, end_date, created_at, updated_at, deleted)
SELECT id, class_id, status, start_date, end_date, created_at, updated_at, deleted
  FROM class_statuses;

DROP TABLE class_statuses;
RENAME TABLE class_statuses_new TO class_statuses;

-- ---------------------------------------------------------------------------
-- 6. Device identity: phone-local ids move to typed map relations
-- ---------------------------------------------------------------------------
CREATE TABLE sync_devices (
  device_id    VARCHAR(64)     NOT NULL PRIMARY KEY,
  user_id      BIGINT UNSIGNED NOT NULL,
  created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_seen_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_devices_user (user_id)
) ENGINE=InnoDB;

-- A device that appears under several accounts can only belong to one. Keep
-- the account with the most recent cursor activity. The ranking is explicit
-- because MariaDB may discard an ORDER BY inside INSERT ... SELECT.
INSERT IGNORE INTO sync_devices (device_id, user_id, created_at, last_seen_at)
SELECT device_id, user_id, created_at, updated_at
  FROM (
        SELECT c.*,
               ROW_NUMBER() OVER (
                 PARTITION BY c.device_id
                 ORDER BY c.updated_at DESC, c.user_id DESC
               ) AS rn
          FROM sync_cursors c
       ) ranked
 WHERE rn = 1;

CREATE TABLE sync_cursors_new (
  device_id    VARCHAR(64) NOT NULL PRIMARY KEY,
  last_push_at DATETIME(3) NULL,
  last_pull_at DATETIME(3) NULL,
  created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

  FOREIGN KEY (device_id) REFERENCES sync_devices(device_id) ON DELETE CASCADE
) ENGINE=InnoDB;

INSERT INTO sync_cursors_new
  (device_id, last_push_at, last_pull_at, created_at, updated_at)
SELECT device_id, MAX(last_push_at), MAX(last_pull_at), MIN(created_at), MAX(updated_at)
  FROM sync_cursors
 GROUP BY device_id;

DROP TABLE sync_cursors;
RENAME TABLE sync_cursors_new TO sync_cursors;

-- Old local_id columns cannot be turned into maps: nothing recorded which
-- device wrote each row. They are dropped; a phone re-registers its local
-- ids in the map on its next push, and existing rows are matched by
-- server_id (which phones already store).
ALTER TABLE classes DROP COLUMN local_id;
ALTER TABLE events DROP COLUMN local_id;

CREATE TABLE class_local_map (
  device_id VARCHAR(64)     NOT NULL,
  local_id  BIGINT          NOT NULL,
  class_id  BIGINT UNSIGNED NOT NULL,

  PRIMARY KEY (device_id, local_id),
  UNIQUE KEY uq_class_map_row (device_id, class_id),
  FOREIGN KEY (device_id) REFERENCES sync_devices(device_id) ON DELETE CASCADE,
  FOREIGN KEY (class_id)  REFERENCES classes(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE event_local_map (
  device_id VARCHAR(64)     NOT NULL,
  local_id  BIGINT          NOT NULL,
  event_id  BIGINT UNSIGNED NOT NULL,

  PRIMARY KEY (device_id, local_id),
  UNIQUE KEY uq_event_map_row (device_id, event_id),
  FOREIGN KEY (device_id) REFERENCES sync_devices(device_id) ON DELETE CASCADE,
  FOREIGN KEY (event_id)  REFERENCES events(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE status_local_map (
  device_id       VARCHAR(64)     NOT NULL,
  local_id        BIGINT          NOT NULL,
  class_status_id BIGINT UNSIGNED NOT NULL,

  PRIMARY KEY (device_id, local_id),
  UNIQUE KEY uq_status_map_row (device_id, class_status_id),
  FOREIGN KEY (device_id) REFERENCES sync_devices(device_id) ON DELETE CASCADE,
  FOREIGN KEY (class_status_id) REFERENCES class_statuses(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 7. password_resets: one live code per user, expiry derived at read time
-- ---------------------------------------------------------------------------
CREATE TABLE password_resets_new (
  user_id     BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  code_hash   VARCHAR(255) NOT NULL,
  created_at  DATETIME(3)  NOT NULL,
  ttl_seconds INT UNSIGNED NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CHECK (ttl_seconds > 0)
) ENGINE=InnoDB;

-- Only the newest unused code per user survives; used codes are dropped.
-- The remaining lifetime becomes the stored policy (normally 900 seconds).
INSERT INTO password_resets_new (user_id, code_hash, created_at, ttl_seconds)
SELECT r.user_id,
       r.code_hash,
       r.created_at,
       GREATEST(TIMESTAMPDIFF(SECOND, r.created_at, r.expires_at), 1)
  FROM password_resets r
  JOIN (
        SELECT user_id, MAX(id) AS id
          FROM password_resets
         WHERE used_at IS NULL
         GROUP BY user_id
       ) newest ON newest.id = r.id;

DROP TABLE password_resets;
RENAME TABLE password_resets_new TO password_resets;

-- ---------------------------------------------------------------------------
-- 8. rate_limit_hits: split the packed bucket
-- ---------------------------------------------------------------------------
-- Short-lived counters: resetting them once is cheaper and safer than
-- guessing how a legacy bucket string maps to a new (scope, subject) pair.
DROP TABLE IF EXISTS rate_limit_hits;
CREATE TABLE rate_limit_hits (
  id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  scope   VARCHAR(32)  NOT NULL,
  subject VARCHAR(255) NOT NULL,
  hit_at  DATETIME(3)  NOT NULL,
  KEY idx_rl_scope_subject_time (scope, subject, hit_at)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 9. Recreate the debug views (SELECT * expanded the old column lists)
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS active_classes;
DROP VIEW IF EXISTS active_events;
DROP VIEW IF EXISTS active_class_statuses;

CREATE VIEW active_classes AS
  SELECT id, user_id, subject, room, professor, day, start_minutes,
         end_minutes, created_at, updated_at, deleted
    FROM classes WHERE deleted = 0;

CREATE VIEW active_events AS
  SELECT id, user_id, title, venue, event_date, start_minutes, category,
         department_id, broadcast, reminder_enabled, lead_minutes,
         created_at, updated_at, deleted
    FROM events WHERE deleted = 0;

CREATE VIEW active_class_statuses AS
  SELECT id, class_id, status, start_date, end_date, created_at, updated_at,
         deleted
    FROM class_statuses WHERE deleted = 0;
