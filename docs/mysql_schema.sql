-- Klasify sync backend schema (MySQL 8.0+)
-- Run this in SQLyog or any MySQL client against a fresh database.
-- Database name: klasify_sync
--
-- Design notes:
--   * All tables use InnoDB (transactional) + utf8mb4 (full Unicode).
--   * IDs are BIGINT UNSIGNED AUTO_INCREMENT (matches the app's local
--     INTEGER ids only loosely; the sync layer maps local_id <-> server_id).
--   * Every syncable row carries user_id, updated_at, and deleted (soft
--     delete) so deltas can be pushed/pulled without losing tombstones.
--   * Timestamps are stored as UTC DATETIME(3) (millisecond precision).
--   * Auth uses bcrypt password hashes (cost 12) — never store plaintext.

CREATE DATABASE IF NOT EXISTS klasify_sync
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE klasify_sync;

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  email         VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NULL,              -- bcrypt, cost 12; NULL for Google-only accounts
  google_sub    VARCHAR(255) NULL,             -- Google subject id; UNIQUE when present
  display_name  VARCHAR(100) NOT NULL DEFAULT '',
  created_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted       TINYINT(1)   NOT NULL DEFAULT 0,

  UNIQUE KEY uq_users_email (email),
  UNIQUE KEY uq_users_google_sub (google_sub),
  KEY idx_users_updated (updated_at)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Classes (weekly schedule)
-- ---------------------------------------------------------------------------
CREATE TABLE classes (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id       BIGINT UNSIGNED NOT NULL,
  local_id      BIGINT          NULL,           -- client-side SQLite row id
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
  user_id         BIGINT UNSIGNED NOT NULL,
  local_id        BIGINT          NULL,
  title           VARCHAR(200)    NOT NULL,
  venue           VARCHAR(200)    NOT NULL DEFAULT '',
  event_date      DATE            NOT NULL,      -- yyyy-MM-dd
  start_minutes   SMALLINT        NOT NULL,      -- 0..1439
  category        ENUM('personal','school') NOT NULL DEFAULT 'personal',
  reminder_enabled TINYINT(1)     NOT NULL DEFAULT 1,
  lead_minutes    TINYINT         NOT NULL DEFAULT 30,
  created_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted         TINYINT(1)      NOT NULL DEFAULT 0,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_events_user_updated (user_id, updated_at),
  KEY idx_events_user_date (user_id, event_date),
  CHECK (start_minutes BETWEEN 0 AND 1439),
  CHECK (reminder_enabled IN (0, 1)),
  CHECK (lead_minutes IN (5, 10, 15, 30))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Class status marks (done / not attending / cancelled per date range)
-- ---------------------------------------------------------------------------
CREATE TABLE class_statuses (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id     BIGINT UNSIGNED NOT NULL,
  local_id    BIGINT          NULL,
  class_id    BIGINT UNSIGNED NOT NULL,          -- server-side class id
  local_class_id BIGINT       NULL,              -- client-side class id (for pre-sync)
  status      ENUM('finished','not_attending','cancelled') NOT NULL,
  start_date  DATE            NOT NULL,
  end_date    DATE            NULL,
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted     TINYINT(1)      NOT NULL DEFAULT 0,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
  KEY idx_cs_user_updated (user_id, updated_at),
  CHECK (end_date IS NULL OR end_date >= start_date)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Password reset codes (6-digit, 15-minute codes for the forgot flow)
-- ---------------------------------------------------------------------------
CREATE TABLE password_resets (
  id         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id    BIGINT UNSIGNED NOT NULL,
  code_hash  VARCHAR(255) NOT NULL,             -- bcrypt of the 6-digit code
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  expires_at DATETIME(3) NOT NULL,              -- created_at + 15 minutes
  used_at    DATETIME(3) NULL,

  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_pr_user (user_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Sync metadata (per-user, per-device cursor)
-- ---------------------------------------------------------------------------
CREATE TABLE sync_cursors (
  user_id       BIGINT UNSIGNED NOT NULL,
  device_id     VARCHAR(64)     NOT NULL,
  last_push_at  DATETIME(3)     NULL,
  last_pull_at  DATETIME(3)     NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),

  PRIMARY KEY (user_id, device_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Helpful views for debugging
-- ---------------------------------------------------------------------------
CREATE VIEW active_classes AS
  SELECT * FROM classes WHERE deleted = 0;

CREATE VIEW active_events AS
  SELECT * FROM events WHERE deleted = 0;

CREATE VIEW active_class_statuses AS
  SELECT * FROM class_statuses WHERE deleted = 0;
