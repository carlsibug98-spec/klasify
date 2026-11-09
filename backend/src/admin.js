// src/admin.js
// Admin-only endpoints: user role management and office availability.
// All routes require a signed-in admin (role = 'admin' or 'super_admin').
// Department-scoped: a dept admin only sees/manages their own department.

const express = require('express');
const { pool } = require('./db');
const { requireAuth } = require('./jwt');

const router = express.Router();

const VALID_ROLES = new Set(['user', 'admin', 'super_admin']);
const VALID_STATUSES = new Set(['open', 'closed', 'break']);
const OFFICES = ['guidance', 'clinic', 'registrar'];

/// Middleware: resolves the caller's role + department from the DB.
async function resolveCaller(req, res, next) {
  try {
    const [rows] = await pool.query(
      'SELECT id, role, department FROM users WHERE id = ? AND deleted = 0 LIMIT 1',
      [req.userId]
    );
    const u = rows[0];
    if (!u) return res.status(401).json({ error: 'User not found', code: 'UNAUTHORIZED' });
    if (u.role !== 'admin' && u.role !== 'super_admin') {
      return res.status(403).json({ error: 'Admin access required', code: 'FORBIDDEN' });
    }
    req.callerRole = u.role;
    req.callerDept = u.department;
    next();
  } catch (err) {
    next(err);
  }
}

/// GET /admin/users — list users the caller may manage.
router.get('/users', requireAuth, resolveCaller, async (req, res, next) => {
  try {
    let sql = 'SELECT id, email, display_name, role, department, created_at FROM users WHERE deleted = 0';
    const params = [];
    if (req.callerRole !== 'super_admin') {
      if (req.callerDept) {
        sql += ' AND (department = ? OR id = ?)';
        params.push(req.callerDept, req.userId);
      } else {
        // A department admin with no department assigned manages nobody
        // but themselves.
        sql += ' AND id = ?';
        params.push(req.userId);
      }
    }
    sql += ' ORDER BY created_at DESC LIMIT 200';
    const [rows] = await pool.query(sql, params);
    res.json({ users: rows });
  } catch (err) {
    next(err);
  }
});

/// PATCH /admin/users/:id/role — promote/demote a user.
router.patch('/users/:id/role', requireAuth, resolveCaller, async (req, res, next) => {
  try {
    const targetId = Number(req.params.id);
    const newRole = String(req.body?.role || '').trim();
    if (!VALID_ROLES.has(newRole)) {
      return res.status(422).json({ error: 'Invalid role', code: 'VALIDATION_ERROR' });
    }
    // Only super_admins can create other admins or change roles across depts.
    if (req.callerRole !== 'super_admin') {
      return res.status(403).json({ error: 'Super admin required', code: 'FORBIDDEN' });
    }
    // Cannot demote yourself.
    if (targetId === req.userId && newRole !== 'super_admin') {
      return res.status(422).json({ error: 'Cannot demote yourself', code: 'VALIDATION_ERROR' });
    }
    await pool.query('UPDATE users SET role = ? WHERE id = ? AND deleted = 0', [newRole, targetId]);
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/// PATCH /admin/users/:id/department — assign a user to a department.
router.patch('/users/:id/department', requireAuth, resolveCaller, async (req, res, next) => {
  try {
    const targetId = Number(req.params.id);
    const dept = req.body?.department === null ? null : String(req.body?.department || '').trim() || null;
    if (req.callerRole !== 'super_admin') {
      return res.status(403).json({ error: 'Super admin required', code: 'FORBIDDEN' });
    }
    await pool.query('UPDATE users SET department = ? WHERE id = ? AND deleted = 0', [dept, targetId]);
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/// GET /admin/office-statuses — list office statuses visible to the caller.
router.get('/office-statuses', requireAuth, resolveCaller, async (req, res, next) => {
  try {
    // Offices are school-wide (department = NULL). Every admin sees the
    // same three offices; updates are shared across the school.
    const [rows] = await pool.query(
      'SELECT id, office_name, status, custom_message, user_id, updated_at FROM office_statuses WHERE deleted = 0 AND department IS NULL ORDER BY office_name'
    );
    const present = new Set(rows.map((r) => r.office_name));
    for (const office of OFFICES) {
      if (!present.has(office)) {
        await pool.query(
          'INSERT INTO office_statuses (user_id, office_name, department, status) VALUES (?,?,NULL,?)',
          [req.userId, office, 'open']
        );
      }
    }
    const [fresh] = await pool.query(
      'SELECT id, office_name, status, custom_message, user_id, updated_at FROM office_statuses WHERE deleted = 0 AND department IS NULL ORDER BY office_name'
    );
    res.json({ offices: fresh });
  } catch (err) {
    next(err);
  }
});

/// PATCH /admin/office-statuses/:office — update an office's status.
router.patch('/office-statuses/:office', requireAuth, resolveCaller, async (req, res, next) => {
  try {
    const office = String(req.params.office).trim();
    if (!OFFICES.includes(office)) {
      return res.status(422).json({ error: 'Unknown office', code: 'VALIDATION_ERROR' });
    }
    const status = String(req.body?.status || '').trim();
    if (!VALID_STATUSES.has(status)) {
      return res.status(422).json({ error: 'Invalid status', code: 'VALIDATION_ERROR' });
    }
    const customMessage = req.body?.custom_message != null ? String(req.body.custom_message).trim() : null;

    const [existing] = await pool.query(
      'SELECT id FROM office_statuses WHERE office_name = ? AND department IS NULL AND deleted = 0 LIMIT 1',
      [office]
    );
    if (existing.length > 0) {
      await pool.query(
        'UPDATE office_statuses SET status = ?, custom_message = ?, user_id = ? WHERE id = ?',
        [status, customMessage, req.userId, existing[0].id]
      );
    } else {
      await pool.query(
        'INSERT INTO office_statuses (user_id, office_name, department, status, custom_message) VALUES (?,?,NULL,?,?)',
        [req.userId, office, status, customMessage]
      );
    }
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

module.exports = router;