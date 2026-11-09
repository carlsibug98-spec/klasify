// src/sync.js
// /sync/push + /sync/pull. Ports routes/sync.php exactly: upsert every
// client row by (user_id, local_id), answer with local->server id mappings,
// keep a per-device cursor, and include soft-deleted rows in pull deltas.
// Server always wins conflicts: the client's updated_at is stored verbatim
// and becomes the row's local update time.

const express = require('express');
const { pool, toMysqlTimestamp, fromMysqlTimestampToIso } = require('./db');
const { requireAuth } = require('./jwt');

const router = express.Router();
router.use(requireAuth);

// ---------------------------------------------------------------------
// Per-row push validation. The SQLite app layer polices these fields
// (triggers + CHECKs); MySQL's schema CHECKs enforce only part of that.
// A violating row would make MySQL abort the request with a 500 and
// freeze the pushing account's cursor: every retry re-hits the same
// error. Invalid rows are skipped instead (no mapping, logged) so the
// rest of the push still lands and honest rows keep syncing.
// ---------------------------------------------------------------------
const trimmed = (v) => String(v ?? '').trim();
const isDateKey = (v) => /^\d{4}-\d{2}-\d{2}$/.test(String(v ?? ''));
const STATUS_VALUES = new Set(['finished', 'not_attending', 'cancelled']);
const CATEGORIES = new Set(['personal', 'school']);
const LEAD_OPTIONS = new Set([5, 10, 15, 30]);

function invalidClass(row) {
  const subject = trimmed(row.subject);
  if (subject.length < 2 || subject.length > 200) return 'bad subject length';
  const room = trimmed(row.room);
  if (room.length < 1 || room.length > 100) return 'bad room length';
  const professor = trimmed(row.professor);
  if (professor.length < 2 || professor.length > 200) return 'bad professor length';
  const day = Number(row.day);
  if (!Number.isInteger(day) || day < 1 || day > 7) return 'day out of range';
  const start = Number(row.start_minutes);
  if (!Number.isInteger(start) || start < 0 || start >= 1440) {
    return 'start_minutes out of range';
  }
  const end = Number(row.end_minutes);
  if (!Number.isInteger(end) || end < 1 || end > 1440 || end <= start) {
    return 'end_minutes out of range';
  }
  return null;
}

function invalidEvent(row) {
  const title = trimmed(row.title);
  if (title.length < 2 || title.length > 200) return 'bad title length';
  if (String(row.venue ?? '').length > 200) return 'bad venue length';
  const start = Number(row.start_minutes);
  if (!Number.isInteger(start) || start < 0 || start >= 1440) {
    return 'start_minutes out of range';
  }
  if (!CATEGORIES.has(String(row.category ?? ''))) return 'unknown category';
  if (!LEAD_OPTIONS.has(Number(row.lead_minutes))) return 'bad lead_minutes';
  if (!isDateKey(row.event_date)) return 'malformed event_date';
  return null;
}

function invalidStatus(row) {
  if (!STATUS_VALUES.has(String(row.status ?? ''))) return 'unknown status';
  if (!isDateKey(row.start_date)) return 'malformed start_date';
  if (row.end_date !== null && row.end_date !== undefined) {
    if (!isDateKey(row.end_date)) return 'malformed end_date';
    if (String(row.end_date) < String(row.start_date)) return 'end_date before start_date';
  }
  return null;
}

// ---------------------------------------------------------------------
// POST /sync/push
// ---------------------------------------------------------------------
router.post('/push', async (req, res, next) => {
  try {
    const body = req.body || {};
    const userId = req.userId;
    const nowIso = new Date().toISOString();
    const nowDt = toMysqlTimestamp(new Date());

    // Caller role/dept for department-scoped broadcast events.
    const [callerRows] = await pool.query(
      'SELECT role, department FROM users WHERE id = ? AND deleted = 0 LIMIT 1',
      [userId]
    );
    const caller = callerRows[0] || { role: 'user', department: null };
    const callerIsAdmin = caller.role === 'admin' || caller.role === 'super_admin';

    const result = {
      server_time: nowIso,
      classes: [],
      events: [],
      class_statuses: [],
    };

    // --- Classes ------------------------------------------------------
    for (const row of body.classes || []) {
      const localId = row.local_id ?? null;
      const invalid = invalidClass(row);
      if (invalid) {
        console.warn(`sync/push: skipped class row for user ${userId}: ${invalid}`);
        continue;
      }
      // Match an already-mapped row by its server id first (the client
      // echoes back the id from its last sync); fall back to local_id for
      // a row the client has not mapped yet.
      const pushServerId =
        row.server_id !== null && row.server_id !== undefined
          ? Number(row.server_id)
          : null;
      let existing = [];
      if (pushServerId !== null && Number.isFinite(pushServerId) && pushServerId > 0) {
        [existing] = await pool.query(
          'SELECT id FROM classes WHERE user_id = ? AND id = ? LIMIT 1',
          [userId, pushServerId]
        );
      }
      if (existing.length === 0) {
        [existing] = await pool.query(
          'SELECT id FROM classes WHERE user_id = ? AND local_id = ? LIMIT 1',
          [userId, localId]
        );
      }
      const subject = String(row.subject ?? '');
      const room = String(row.room ?? '');
      const professor = String(row.professor ?? '');
      const day = Number(row.day ?? 1);
      const startMin = Number(row.start_minutes ?? 0);
      const endMin = Number(row.end_minutes ?? 0);
      const deleted = row.deleted ? 1 : 0;
      // Echo the client's own timestamp back, like the PHP route did.
      const clientIso = row.updated_at ?? nowIso;
      const updatedAt = toMysqlTimestamp(row.updated_at) || nowDt;

      let serverId;
      if (existing.length > 0) {
        serverId = Number(existing[0].id);
        await pool.query(
          'UPDATE classes SET subject=?, room=?, professor=?, day=?, start_minutes=?, end_minutes=?, deleted=?, updated_at=? WHERE id=?',
          [subject, room, professor, day, startMin, endMin, deleted, updatedAt, serverId]
        );
      } else {
        const [insert] = await pool.query(
          'INSERT INTO classes (user_id, local_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
          [userId, localId, subject, room, professor, day, startMin, endMin, deleted, updatedAt]
        );
        serverId = Number(insert.insertId);
      }
      result.classes.push({ local_id: localId, server_id: serverId, updated_at: clientIso });
    }

    // --- Events ---------------------------------------------------------
    for (const row of body.events || []) {
      const localId = row.local_id ?? null;
      const invalid = invalidEvent(row);
      if (invalid) {
        console.warn(`sync/push: skipped event row for user ${userId}: ${invalid}`);
        continue;
      }
      const title = String(row.title ?? '');
      const venue = String(row.venue ?? '');
      const eventDate = String(row.event_date ?? nowIso.slice(0, 10));
      const startMin = Number(row.start_minutes ?? 0);
      const category = String(row.category ?? 'personal');
      const reminder = row.reminder_enabled ? 1 : 0;
      const leadMin = Number(row.lead_minutes ?? 30);
      const deleted = row.deleted ? 1 : 0;
      const clientIso = row.updated_at ?? nowIso;
      const updatedAt = toMysqlTimestamp(row.updated_at) || nowDt;

      // Broadcasting: only admins can post to a department or the school.
      // A dept admin always posts to their own department; a super admin
      // may pick one (row.department) or leave it school-wide.
      const wantsBroadcast = !!row.broadcast;
      const isBroadcast = wantsBroadcast && callerIsAdmin &&
        (caller.role === 'super_admin' || !!caller.department);
      const broadcast = isBroadcast ? 1 : 0;
      const department = isBroadcast
        ? (caller.role === 'super_admin'
            ? (row.department ? String(row.department).trim() || null : null)
            : (caller.department || null))
        : null;
      const storeUserId = isBroadcast ? null : userId;

      const pushServerId =
        row.server_id !== null && row.server_id !== undefined
          ? Number(row.server_id)
          : null;
      let existing = [];
      if (pushServerId !== null && Number.isFinite(pushServerId) && pushServerId > 0) {
        [existing] = await pool.query(
          'SELECT id, user_id, department FROM events WHERE id = ? LIMIT 1',
          [pushServerId]
        );
      }
      if (existing.length > 0 && existing[0].user_id !== null && Number(existing[0].user_id) !== Number(userId)) {
        // Someone else's personal event: never editable from this account.
        console.warn(`sync/push: skipped foreign event id ${pushServerId} for user ${userId}`);
        result.events.push({ local_id: localId, server_id: Number(existing[0].id), updated_at: clientIso });
        continue;
      }
      if (existing.length > 0 && existing[0].user_id === null) {
        // Broadcast row: only an admin whose scope covers it may change it.
        const inScope = caller.role === 'super_admin' ||
          (callerIsAdmin && existing[0].department === caller.department);
        if (!inScope || !isBroadcast) {
          result.events.push({ local_id: localId, server_id: Number(existing[0].id), updated_at: clientIso });
          continue;
        }
      }
      if (existing.length === 0) {
        if (storeUserId === null) {
          [existing] = await pool.query(
            'SELECT id FROM events WHERE user_id IS NULL AND local_id = ? AND department <=> ? LIMIT 1',
            [localId, department]
          );
        } else {
          [existing] = await pool.query(
            'SELECT id FROM events WHERE user_id = ? AND local_id = ? LIMIT 1',
            [storeUserId, localId]
          );
        }
      }
      let serverId;
      if (existing.length > 0) {
        serverId = Number(existing[0].id);
        // user_id follows the broadcast state: a personal event shared to the
        // school/department becomes a broadcast row (user_id NULL), so other
        // users' pulls can see it.
        await pool.query(
          'UPDATE events SET user_id=?, title=?, venue=?, event_date=?, start_minutes=?, category=?, department=?, broadcast=?, reminder_enabled=?, lead_minutes=?, deleted=?, updated_at=? WHERE id=?',
          [storeUserId, title, venue, eventDate, startMin, category, department, broadcast, reminder, leadMin, deleted, updatedAt, serverId]
        );
      } else {
        const [insert] = await pool.query(
          'INSERT INTO events (user_id, local_id, title, venue, event_date, start_minutes, category, department, broadcast, reminder_enabled, lead_minutes, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [storeUserId, localId, title, venue, eventDate, startMin, category, department, broadcast, reminder, leadMin, deleted, updatedAt]
        );
        serverId = Number(insert.insertId);
      }
      result.events.push({ local_id: localId, server_id: serverId, updated_at: clientIso });
    }

    // --- Class statuses ---------------------------------------------------
    for (const row of body.class_statuses || []) {
      const localId = row.local_id ?? null;
      const invalid = invalidStatus(row);
      if (invalid) {
        console.warn(`sync/push: skipped status row for user ${userId}: ${invalid}`);
        continue;
      }
      const localClassId = row.local_class_id ?? null;
      const status = String(row.status ?? 'finished');
      const startDate = String(row.start_date ?? nowIso.slice(0, 10));
      const endDate = row.end_date ?? null;
      const deleted = row.deleted ? 1 : 0;
      const clientIso = row.updated_at ?? nowIso;
      const updatedAt = toMysqlTimestamp(row.updated_at) || nowDt;
      // Resolve the server-side class id from the client's class local id.
      // The Flutter push sends classes first in the same request, so the
      // mapping normally exists by the time the statuses are processed.
      let classId = null;
      if (localClassId !== null && localClassId !== undefined) {
        const [cr] = await pool.query(
          'SELECT id FROM classes WHERE user_id = ? AND local_id = ? LIMIT 1',
          [userId, localClassId]
        );
        if (cr.length > 0) classId = Number(cr[0].id);
      }
      // class_id is NOT NULL + FK in the schema: a status whose class is
      // not on the server yet cannot be stored. Skip it; the client keeps
      // the row unmapped and re-pushes it on a later sync, by which time
      // the class row will exist.
      if (classId === null) continue;

      const pushServerId =
        row.server_id !== null && row.server_id !== undefined
          ? Number(row.server_id)
          : null;
      let existing = [];
      if (pushServerId !== null && Number.isFinite(pushServerId) && pushServerId > 0) {
        [existing] = await pool.query(
          'SELECT id FROM class_statuses WHERE user_id = ? AND id = ? LIMIT 1',
          [userId, pushServerId]
        );
      }
      if (existing.length === 0) {
        [existing] = await pool.query(
          'SELECT id FROM class_statuses WHERE user_id = ? AND local_id = ? LIMIT 1',
          [userId, localId]
        );
      }
      let serverId;
      if (existing.length > 0) {
        serverId = Number(existing[0].id);
        await pool.query(
          'UPDATE class_statuses SET class_id=?, status=?, start_date=?, end_date=?, deleted=?, updated_at=? WHERE id=?',
          [classId, status, startDate, endDate, deleted, updatedAt, serverId]
        );
      } else {
        const [insert] = await pool.query(
          'INSERT INTO class_statuses (user_id, local_id, class_id, local_class_id, status, start_date, end_date, deleted, updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
          [userId, localId, classId, localClassId, status, startDate, endDate, deleted, updatedAt]
        );
        serverId = Number(insert.insertId);
      }
      result.class_statuses.push({ local_id: localId, server_id: serverId, updated_at: clientIso });
    }

    await pool.query(
      `INSERT INTO sync_cursors (user_id, device_id, last_push_at) VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE last_push_at = VALUES(last_push_at), updated_at = CURRENT_TIMESTAMP(3)`,
      [userId, String(body.device_id ?? 'unknown'), nowDt]
    );

    res.json(result);
  } catch (err) {
    next(err);
  }
});

// ---------------------------------------------------------------------
// GET /sync/pull?since=<iso> — rows changed on the server since `since`,
// soft-deleted ones included so clients can tombstone locally.
// ---------------------------------------------------------------------
router.get('/pull', async (req, res, next) => {
  try {
    const userId = req.userId;
    const sinceIso = String(req.query.since || '1970-01-01T00:00:00.000Z');
    const sinceDt = toMysqlTimestamp(sinceIso) || '1970-01-01 00:00:00.000';
    const nowDt = toMysqlTimestamp(new Date());

    // Caller's department for broadcast-event filtering.
    const [callerRows] = await pool.query(
      'SELECT department FROM users WHERE id = ? AND deleted = 0 LIMIT 1',
      [userId]
    );
    const callerDept = callerRows[0] ? callerRows[0].department : null;

    const result = {
      server_time: new Date().toISOString(),
      classes: [],
      events: [],
      class_statuses: [],
      office_statuses: [],
    };

    // `since` is inclusive on purpose: rows stamped exactly at the cursor
    // cannot be missed by a later newer cycle, and because client upserts
    // are idempotent (LWW + id mapping), re-seeing a row costs nothing.
    const [classes] = await pool.query(
      'SELECT id, local_id, subject, room, professor, day, start_minutes, end_minutes, deleted, updated_at FROM classes WHERE user_id = ? AND updated_at >= ?',
      [userId, sinceDt]
    );
    result.classes = classes.map((r) => ({
      id: Number(r.id),
      local_id: r.local_id === null ? null : Number(r.local_id),
      subject: r.subject,
      room: r.room,
      professor: r.professor,
      day: Number(r.day),
      start_minutes: Number(r.start_minutes),
      end_minutes: Number(r.end_minutes),
      deleted: !!Number(r.deleted),
      updated_at: fromMysqlTimestampToIso(r.updated_at) ?? r.updated_at,
    }));

    const [events] = await pool.query(
      'SELECT id, local_id, title, venue, event_date, start_minutes, category, department, broadcast, reminder_enabled, lead_minutes, deleted, updated_at FROM events WHERE (user_id = ? OR (user_id IS NULL AND (department IS NULL OR department = ?))) AND updated_at >= ?',
      [userId, callerDept, sinceDt]
    );
    result.events = events.map((r) => ({
      id: Number(r.id),
      local_id: r.local_id === null ? null : Number(r.local_id),
      title: r.title,
      venue: r.venue,
      event_date: r.event_date,
      start_minutes: Number(r.start_minutes),
      category: r.category,
      department: r.department || null,
      broadcast: !!Number(r.broadcast),
      reminder_enabled: !!Number(r.reminder_enabled),
      lead_minutes: Number(r.lead_minutes),
      deleted: !!Number(r.deleted),
      updated_at: fromMysqlTimestampToIso(r.updated_at) ?? r.updated_at,
    }));

    const [statuses] = await pool.query(
      'SELECT id, local_id, class_id, local_class_id, status, start_date, end_date, deleted, updated_at FROM class_statuses WHERE user_id = ? AND updated_at >= ?',
      [userId, sinceDt]
    );
    result.class_statuses = statuses.map((r) => ({
      id: Number(r.id),
      local_id: r.local_id === null ? null : Number(r.local_id),
      class_id: r.class_id === null ? null : Number(r.class_id),
      local_class_id: r.local_class_id === null ? null : Number(r.local_class_id),
      status: r.status,
      start_date: r.start_date,
      end_date: r.end_date,
      deleted: !!Number(r.deleted),
      updated_at: fromMysqlTimestampToIso(r.updated_at) ?? r.updated_at,
    }));

    const [offices] = await pool.query(
      'SELECT id, office_name, department, status, custom_message, updated_at, deleted FROM office_statuses WHERE (department IS NULL OR department = ?) AND updated_at >= ?',
      [callerDept, sinceDt]
    );
    result.office_statuses = offices.map((r) => ({
      id: Number(r.id),
      office_name: r.office_name,
      department: r.department || null,
      status: r.status,
      custom_message: r.custom_message,
      updated_at: fromMysqlTimestampToIso(r.updated_at) ?? r.updated_at,
      deleted: !!Number(r.deleted),
    }));

    await pool.query(
      `INSERT INTO sync_cursors (user_id, device_id, last_pull_at) VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE last_pull_at = VALUES(last_pull_at), updated_at = CURRENT_TIMESTAMP(3)`,
      [userId, String(req.query.device_id ?? 'unknown'), nowDt]
    );

    res.json(result);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
