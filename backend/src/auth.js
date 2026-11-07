// src/auth.js
// /auth endpoints: register, login, refresh, account deletion. Mirrors the
// API contract (docs/sync_api_contract.md) exactly — same routes, codes,
// status numbers, and response shapes the PHP implementation served.

const express = require('express');
const bcrypt = require('bcryptjs');
const { pool } = require('./db');
const { signToken, expiresAtIso, verifyToken, requireAuth } = require('./jwt');

const router = express.Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const BCRYPT_COST = 12;

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
    return res.status(204).end();
  } catch (err) {
    next(err);
  }
});

module.exports = router;
