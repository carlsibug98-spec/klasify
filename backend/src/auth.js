// src/auth.js
// /auth endpoints: register, login, refresh, account deletion, profile edit,
// password change, and the forgot/reset password flow. Mirrors the API
// contract (docs/sync_api_contract.md) exactly — same routes, codes, status
// numbers, and response shapes the PHP implementation served.

const express = require('express');
const bcrypt = require('bcryptjs');
const crypto = require('node:crypto');
const { pool } = require('./db');
const { signToken, expiresAtIso, verifyToken, requireAuth } = require('./jwt');

const router = express.Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const BCRYPT_COST = 12;
const RESET_CODE_TTL_MINUTES = 15;
const maxEmailRequests = new Map(); // email -> recent timestamps (in-memory throttle)

function userJson(row) {
  return {
    id: Number(row.id),
    email: row.email,
    display_name: row.display_name,
  };
}

/// POST /auth/register
/// 201 { user, token, expires_at } | 409 EMAIL_EXISTS | 422 VALIDATION_ERROR
router.post('/register', async (req, res, next) => {
  try {
    const body = req.body || {};
    const email = String(body.email || '').trim();
    const password = String(body.password || '');
    const displayName = String(body.display_name || '').trim();

    if (!EMAIL_RE.test(email)) {
      return res.status(422).json({
        error: 'Invalid email address',
        code: 'VALIDATION_ERROR',
      });
    }
    if (password.length < 8) {
      return res.status(422).json({
        error: 'Password must be at least 8 characters',
        code: 'VALIDATION_ERROR',
      });
    }

    const [existing] = await pool.query('SELECT id FROM users WHERE email = ?', [email]);
    if (existing.length > 0) {
      return res.status(409).json({
        error: 'An account with this email already exists',
        code: 'EMAIL_EXISTS',
      });
    }

    const [insert] = await pool.query(
      'INSERT INTO users (email, password_hash, display_name) VALUES (?, ?, ?)',
      [email, await bcrypt.hash(password, BCRYPT_COST), displayName]
    );
    const userId = Number(insert.insertId);

    return res.status(201).json({
      user: { id: userId, email, display_name: displayName },
      token: signToken(userId, email),
      expires_at: expiresAtIso(),
    });
  } catch (err) {
    next(err);
  }
});

/// POST /auth/login
/// 200 { user, token, expires_at } | 401 INVALID_CREDENTIALS
router.post('/login', async (req, res, next) => {
  try {
    const body = req.body || {};
    const email = String(body.email || '').trim();
    const password = String(body.password || '');

    if (email === '' || password === '') {
      return res.status(422).json({
        error: 'Email and password are required',
        code: 'VALIDATION_ERROR',
      });
    }

    const [rows] = await pool.query(
      'SELECT id, email, password_hash, display_name FROM users WHERE email = ? AND deleted = 0 LIMIT 1',
      [email]
    );
    const user = rows[0];
    if (!user || !(await bcrypt.compare(password, user.password_hash || ''))) {
      return res.status(401).json({
        error: 'Invalid email or password',
        code: 'INVALID_CREDENTIALS',
      });
    }

    return res
      .status(200)
      .json({ user: userJson(user), token: signToken(Number(user.id), user.email), expires_at: expiresAtIso() });
  } catch (err) {
    next(err);
  }
});

/// POST /auth/refresh — accepts an expired token within a grace window and
/// reissues a fresh one, exactly like the PHP route did.
router.post('/refresh', async (req, res, next) => {
  try {
    const header = req.headers.authorization || '';
    const match = /^Bearer\s+(.+)$/i.exec(header);
    if (!match) {
      return res.status(401).json({ error: 'Missing token', code: 'UNAUTHORIZED' });
    }

    const payload = verifyToken(match[1], { ignoreExpiration: true });
    if (!payload || payload.user_id === undefined) {
      return res.status(401).json({ error: 'Invalid token', code: 'TOKEN_EXPIRED' });
    }

    const [rows] = await pool.query(
      'SELECT id, email, display_name FROM users WHERE id = ? AND deleted = 0 LIMIT 1',
      [Number(payload.user_id)]
    );
    const user = rows[0];
    if (!user) {
      return res.status(401).json({ error: 'User not found', code: 'TOKEN_EXPIRED' });
    }

    return res
      .status(200)
      .json({ token: signToken(Number(user.id), user.email), expires_at: expiresAtIso() });
  } catch (err) {
    next(err);
  }
});

/// DELETE /auth/account — soft-deletes the user and cascades through all
/// their data, leaving tombstones behind. Responds 204.
router.delete('/account', requireAuth, async (req, res, next) => {
  try {
    const userId = req.userId;
    await pool.query('UPDATE users SET deleted = 1 WHERE id = ?', [userId]);
    await pool.query('UPDATE classes SET deleted = 1 WHERE user_id = ?', [userId]);
    await pool.query('UPDATE events SET deleted = 1 WHERE user_id = ?', [userId]);
    await pool.query('UPDATE class_statuses SET deleted = 1 WHERE user_id = ?', [userId]);
    await pool.query('DELETE FROM password_resets WHERE user_id = ?', [userId]);
    return res.status(204).end();
  } catch (err) {
    next(err);
  }
});

/// PATCH /auth/me — partial profile edit: display_name and/or email.
/// 200 { user } | 409 EMAIL_EXISTS | 422 VALIDATION_ERROR
router.patch('/me', requireAuth, async (req, res, next) => {
  try {
    const body = req.body || {};
    const sets = [];
    const params = [];

    let displayName;
    let email;
    if (body.display_name !== undefined) {
      displayName = String(body.display_name).trim();
      if (displayName === '' || displayName.length > 100) {
        return res.status(422).json({
          error: 'Display name must be 1-100 characters',
          code: 'VALIDATION_ERROR',
        });
      }
      sets.push('display_name = ?');
      params.push(displayName);
    }
    if (body.email !== undefined) {
      email = String(body.email).trim();
      if (!EMAIL_RE.test(email)) {
        return res.status(422).json({
          error: 'Invalid email address',
          code: 'VALIDATION_ERROR',
        });
      }
      sets.push('email = ?');
      params.push(email);
    }

    if (sets.length === 0) {
      return res.status(422).json({
        error: 'Nothing to update',
        code: 'VALIDATION_ERROR',
      });
    }

    // Email uniqueness across OTHER users. Deleted rows keep their address
    // reserved, so the check is against every row, deleted or not.
    if (email !== undefined) {
      const [dup] = await pool.query(
        'SELECT id FROM users WHERE email = ? AND id <> ? LIMIT 1',
        [email, req.userId]
      );
      if (dup.length > 0) {
        return res.status(409).json({
          error: 'An account with this email already exists',
          code: 'EMAIL_EXISTS',
        });
      }
    }

    await pool.query(`UPDATE users SET ${sets.join(', ')} WHERE id = ?`, [
      ...params,
      req.userId,
    ]);

    const [rows] = await pool.query(
      'SELECT id, email, display_name FROM users WHERE id = ? LIMIT 1',
      [req.userId]
    );
    return res.status(200).json({ user: userJson(rows[0]) });
  } catch (err) {
    next(err);
  }
});

/// POST /auth/change-password — signed in, remembers the current password.
/// 204 | 401 INVALID_CREDENTIALS (wrong current password) | 422 VALIDATION_ERROR
router.post('/change-password', requireAuth, async (req, res, next) => {
  try {
    const body = req.body || {};
    const currentPassword = String(body.current_password || '');
    const newPassword = String(body.new_password || '');

    if (newPassword.length < 8) {
      return res.status(422).json({
        error: 'Password must be at least 8 characters',
        code: 'VALIDATION_ERROR',
      });
    }

    const [rows] = await pool.query(
      'SELECT password_hash FROM users WHERE id = ? AND deleted = 0 LIMIT 1',
      [req.userId]
    );
    if (!rows[0] || !(await bcrypt.compare(currentPassword, rows[0].password_hash || ''))) {
      return res.status(401).json({
        error: 'Current password is incorrect',
        code: 'INVALID_CREDENTIALS',
      });
    }

    await pool.query('UPDATE users SET password_hash = ? WHERE id = ?', [
      await bcrypt.hash(newPassword, BCRYPT_COST),
      req.userId,
    ]);
    // Any outstanding reset codes are meaningless now.
    await pool.query('DELETE FROM password_resets WHERE user_id = ?', [req.userId]);
    return res.status(204).end();
  } catch (err) {
    next(err);
  }
});

/// POST /auth/forgot-password — asks for a 6-digit reset code.
/// Always 200 { ok: true }; never reveals whether the email exists.
/// Codes live 15 minutes, one active at a time. Without SMTP configured the
/// code is logged to the server console (docker logs klasify-api in dev).
router.post('/forgot-password', async (req, res, next) => {
  try {
    const body = req.body || {};
    const email = String(body.email || '').trim();

    if (!EMAIL_RE.test(email)) {
      return res.status(422).json({
        error: 'Invalid email address',
        code: 'VALIDATION_ERROR',
      });
    }

    // Simple in-memory throttle: max 5 requests per email per hour.
    const now = Date.now();
    const recent = (maxEmailRequests.get(email.toLowerCase()) || []).filter(
      (t) => now - t < 3600 * 1000
    );
    if (recent.length >= 5) {
      return res.status(429).json({
        error: 'Too many requests. Try again later.',
        code: 'RATE_LIMITED',
      });
    }
    recent.push(now);
    maxEmailRequests.set(email.toLowerCase(), recent);

    const [users] = await pool.query(
      'SELECT id FROM users WHERE email = ? AND deleted = 0 LIMIT 1',
      [email]
    );
    if (users.length > 0) {
      const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
      await pool.query('DELETE FROM password_resets WHERE user_id = ?', [
        Number(users[0].id),
      ]);
      await pool.query(
        'INSERT INTO password_resets (user_id, code_hash, expires_at) VALUES (?, ?, ?)',
        [
          Number(users[0].id),
          await bcrypt.hash(code, BCRYPT_COST),
          new Date(Date.now() + RESET_CODE_TTL_MINUTES * 60 * 1000),
        ]
      );
      // Email delivery is wired to SMTP in production; until that exists the
      // code lands in the server log so the flow can be tested end to end.
      console.log(`Password reset code for ${email}: ${code}`);
    }

    return res.status(200).json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/// POST /auth/reset-password — { email, code, new_password }.
/// 204 (password updated; sign in normally with it) | 422 invalid code
router.post('/reset-password', async (req, res, next) => {
  try {
    const body = req.body || {};
    const email = String(body.email || '').trim();
    const code = String(body.code || '').trim();
    const newPassword = String(body.new_password || '');

    if (!EMAIL_RE.test(email) || !/^\d{6}$/.test(code) || newPassword.length < 8) {
      return res.status(422).json({
        error: 'Check the email, 6-digit code and a password of at least 8 characters',
        code: 'VALIDATION_ERROR',
      });
    }

    const [users] = await pool.query(
      'SELECT id FROM users WHERE email = ? AND deleted = 0 LIMIT 1',
      [email]
    );
    const userId = users.length > 0 ? Number(users[0].id) : null;

    let ok = false;
    if (userId !== null) {
      const [resets] = await pool.query(
        'SELECT id, code_hash, expires_at FROM password_resets WHERE user_id = ? AND used_at IS NULL ORDER BY created_at DESC LIMIT 1',
        [userId]
      );
      if (resets[0]) {
        const expiresIso = new Date(resets[0].expires_at).getTime();
        ok = await bcrypt.compare(code, resets[0].code_hash || '');
        // bcrypt.compare is timing-safe; expiry is checked separately because
        // an expired code must not be accepted even if the hash matches.
        ok = ok && expiresIso > Date.now();
        if (ok) {
          await pool.query('UPDATE users SET password_hash = ? WHERE id = ?', [
            await bcrypt.hash(newPassword, BCRYPT_COST),
            userId,
          ]);
          await pool.query('DELETE FROM password_resets WHERE user_id = ?', [userId]);
        }
      }
    }

    if (!ok) {
      return res.status(422).json({
        error: 'The reset code is invalid or expired',
        code: 'VALIDATION_ERROR',
      });
    }
    return res.status(204).end();
  } catch (err) {
    next(err);
  }
});

module.exports = router;
