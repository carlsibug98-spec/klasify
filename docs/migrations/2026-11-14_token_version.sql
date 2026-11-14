-- Klasify security migration: revocable sessions.
-- Apply once to an existing database (klasify_sync):
--   mysql -u root klasify_sync < docs/migrations/2026-11-14_token_version.sql
--
-- Fresh installs get the column from docs/mysql_schema.sql and do not need
-- this file.
--
-- After applying, every token issued before the upgrade has no `tv` claim
-- and is treated as version 0. Existing users default to 0, so current
-- sessions keep working; bumping token_version revokes them.

ALTER TABLE users
  ADD COLUMN token_version INT UNSIGNED NOT NULL DEFAULT 0
  AFTER department;
