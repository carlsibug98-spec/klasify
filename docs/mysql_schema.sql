-- Klasify sync backend schema (MySQL 8.0+ / MariaDB 10.4+)
-- Run this in SQLyog or any MySQL client against a fresh database.
-- Database name: klasify_sync
--
-- Design notes:
--   * All tables use InnoDB (transactional) + utf8mb4 (full Unicode).
--   * IDs are BIGINT UNSIGNED AUTO_INCREMENT. A client row's local SQLite id
--     is never stored on the entity: it belongs to a device, so it lives in
--     the typed *_local_map relations instead.
--   * Departments are a relation. Every wire payload still carries the name;
--     the backend resolves it to department_id on write and joins it back on
--     read. utf8mb4_unicode_ci makes "IT" and "it" the same department.
--   * Every syncable row carries updated_at and deleted (soft delete) so
--     deltas can be pushed/pulled without losing tombstones.
--   * events.broadcast and office_statuses.scope_key are VIRTUAL generated
--     columns. They are derived facts, hold no storage, and cannot be written,
--     so the stored relations stay in BCNF. Making either STORED would create
--     a functional dependency from a non-key column and break that.
--   * Timestamps are stored as UTC DATETIME(3) (millisecond precision).
--   * Auth uses bcrypt password hashes (cost 12) — never store plaintext.

CREATE DATABASE IF NOT EXISTS klasify_sync
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE klasify_sync;

-- ---------------------------------------------------------------------------
-- Departments (one row per scope; the name is the wire value)
-- ---------------------------------------------------------------------------
CREATE TABLE departments (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  created_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  UNIQUE KEY uq_departments_name (name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email         VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NULL,              -- bcrypt, cost 12; NULL for Google-only accounts
  google_sub    VARCHAR(255) NULL,             -- Google subject id; UNIQUE when present
  display_name  VARCHAR(100) NOT NULL DEFAULT '',
  role          VARCHAR(20)  NOT NULL DEFAULT 'user',   -- 'user' | 'admin' | 'super_admin'
  department_id BIGINT UNSIGNED NULL,          -- department scope for dept admins; NULL = school-wide
  token_version INT UNSIGNED NOT NULL DEFAULT 0, -- bump to revoke all JWTs (password change/reset/delete)
  created_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted       TINYINT(1)   NOT NULL DEFAULT 0,

  UNIQUE KEY uq_users_email (email),
  UNIQUE KEY uq_users_google_sub (google_sub),
  KEY idx_users_updated (updated_at),
  KEY idx_users_role (role),
  KEY idx_users_department (department_id),
  CONSTRAINT fk_users_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT,
  CONSTRAINT chk_users_role CHECK (role IN ('user', 'admin', 'super_admin'))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Classes (weekly schedule)
-- ---------------------------------------------------------------------------
CREATE TABLE classes (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id       BIGINT UNSIGNED NOT NULL,
  subject       VARCHAR(200)    NOT NULL,
  room          VARCHAR(100)    NOT NULL,
  professor     VARCHAR(200)    NOT NULL,
  day           TINYINT         NOT NULL,       -- 1=Mon .. 7=Sun
  start_minutes SMALLINT        NOT NULL,       -- 0..1439
  end_minutes   SMALLINT        NOT NULL,       -- 1..1440
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted       TINYINT(1)      NOT NULL DEFAULT 0,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_classes_user_updated (user_id, updated_at),
  KEY idx_classes_user_deleted (user_id, deleted),
  CHECK (day BETWEEN 1 AND 7),
  CHECK (start_minutes BETWEEN 0 AND 1439),
  CHECK (end_minutes BETWEEN 1 AND 1440),
  CHECK (end_minutes > start_minutes)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Events (one-off school / personal events)
-- ---------------------------------------------------------------------------
CREATE TABLE events (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id         BIGINT UNSIGNED NULL,          -- NULL = broadcast row (admin post); owner id for personal events
  title           VARCHAR(200)    NOT NULL,
  venue           VARCHAR(200)    NOT NULL DEFAULT '',
  event_date      DATE            NOT NULL,      -- yyyy-MM-dd
  start_minutes   SMALLINT        NOT NULL,      -- 0..1439
  category        ENUM('personal','school') NOT NULL DEFAULT 'personal',
  department_id   BIGINT UNSIGNED NULL,          -- NULL = school-wide; non-null = department-scoped
  reminder_enabled TINYINT(1)     NOT NULL DEFAULT 1,
  lead_minutes    TINYINT         NOT NULL DEFAULT 30,
  created_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted         TINYINT(1)      NOT NULL DEFAULT 0,
  -- Declared last so a database migrated from the old schema (which adds it
  -- with ALTER TABLE) and a fresh one have the same physical column order.
  broadcast       TINYINT(1)      AS (CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) VIRTUAL,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_events_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT,
  KEY idx_events_user_updated (user_id, updated_at),
  KEY idx_events_user_date (user_id, event_date),
  KEY idx_events_department (department_id),
  CHECK (start_minutes BETWEEN 0 AND 1439),
  CHECK (reminder_enabled IN (0, 1)),
  CHECK (lead_minutes IN (5, 10, 15, 30))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Office availability (guidance / clinic / registrar)
-- ---------------------------------------------------------------------------
CREATE TABLE office_statuses (
  id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id         BIGINT UNSIGNED NULL,          -- last admin who changed it; NULL after account deletion
  office_name     VARCHAR(64)     NOT NULL,
  department_id   BIGINT UNSIGNED NULL,          -- NULL = school-wide
  status          ENUM('open','closed','break') NOT NULL DEFAULT 'open',
  custom_message  VARCHAR(200)    NULL,
  updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted         TINYINT(1)      NOT NULL DEFAULT 0,
  -- COALESCE turns the school-wide NULL into 0, which is outside the
  -- AUTO_INCREMENT range, so (office_name, scope_key) is a real key. A plain
  -- UNIQUE (office_name, department_id) would not be: SQL treats every NULL
  -- as distinct and would allow duplicate school-wide rows. Declared last so
  -- a migrated database and a fresh one have the same column order.
  scope_key       BIGINT UNSIGNED AS (COALESCE(department_id, 0)) VIRTUAL,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_office_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT,
  UNIQUE KEY uq_office (office_name, scope_key),
  KEY idx_office_updated (updated_at),
  KEY idx_office_department (department_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Class status marks (done / not attending / cancelled per date range)
-- Ownership is classes.user_id through class_id; there is no second copy.
-- ---------------------------------------------------------------------------
CREATE TABLE class_statuses (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  class_id    BIGINT UNSIGNED NOT NULL,          -- server-side class id
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

-- ---------------------------------------------------------------------------
-- Password reset codes (6-digit, 15-minute codes for the forgot flow).
-- A user has at most one live code, so user_id is the key. Expiry is derived
-- from created_at + ttl_seconds at read time; it is not stored twice.
-- ---------------------------------------------------------------------------
CREATE TABLE password_resets (
  user_id     BIGINT UNSIGNED NOT NULL PRIMARY KEY,
  code_hash   VARCHAR(255) NOT NULL,             -- bcrypt of the 6-digit code
  created_at  DATETIME(3)  NOT NULL,
  ttl_seconds INT UNSIGNED NOT NULL,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CHECK (ttl_seconds > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Sync identity. A device id is minted per account on the phone, so it can
-- belong to exactly one user; device_id -> user_id is a key fact.
-- ---------------------------------------------------------------------------
CREATE TABLE sync_devices (
  device_id    VARCHAR(64)     NOT NULL PRIMARY KEY,
  user_id      BIGINT UNSIGNED NOT NULL,
  created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_seen_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_devices_user (user_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Local-id identity. One typed map per syncable entity; (device, local id)
-- names a row on that phone, and (device, entity) names the same row from the
-- server side. No user_id: the entity's own owner column decides access.
-- ---------------------------------------------------------------------------
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
-- Sync cursors: one row per device. The owner is sync_devices.user_id, so a
-- second user_id here would be a transitive copy of that fact.
-- ---------------------------------------------------------------------------
CREATE TABLE sync_cursors (
  device_id    VARCHAR(64) NOT NULL PRIMARY KEY,
  last_push_at DATETIME(3) NULL,
  last_pull_at DATETIME(3) NULL,
  created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

  FOREIGN KEY (device_id) REFERENCES sync_devices(device_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Rate limiting (added 2026-11-09 with the PHP port). The port also
-- self-creates this table at first use; the DDL is here for documentation.
-- scope names the policy (register_ip, login_email, google, ...); subject is
-- the ip / lowercased email / '' for a global scope. They are two facts, not
-- one packed string.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rate_limit_hits (
  id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  scope   VARCHAR(32)  NOT NULL,
  subject VARCHAR(255) NOT NULL,
  hit_at  DATETIME(3)  NOT NULL,
  KEY idx_rl_scope_subject_time (scope, subject, hit_at)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Admin accountability. One append-only row per successful admin mutation:
-- who acted, what they did and which record it touched. Diagnostics in
-- app.log are not an accountability record.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  actor_id   BIGINT UNSIGNED NOT NULL,
  action     VARCHAR(64)  NOT NULL,
  target     VARCHAR(255) NOT NULL,
  created_at DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  KEY idx_admin_audit_created (created_at)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Helpful views for debugging
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Provisioning the first admin
-- ---------------------------------------------------------------------------
-- There is no public "claim admin" endpoint. Promote an existing account by
-- email (sign up normally first), then sign out/in or wait for the next
-- /auth/refresh so the app picks up the role.
--
--   UPDATE users SET role = 'super_admin' WHERE email = 'you@school.edu';
--
-- Department admins can broadcast events to their own department only:
--
--   INSERT INTO departments (name) VALUES ('IT');
--   UPDATE users SET role = 'admin',
--     department_id = (SELECT id FROM departments WHERE name = 'IT')
--   WHERE email = 'dept@school.edu';
--
-- Super admins promote/demote and assign departments from
-- Settings & privacy -> Admin -> User roles (no SQL needed after the first
-- admin exists). Self-demotion is blocked by the API.
