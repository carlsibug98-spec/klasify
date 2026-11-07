// src/jwt.js
// HS256 JWT helpers plus the shared Bearer-token middleware. The token
// format matches docs/sync_api_contract.md: { user_id, email } signed with
// KLASIFY_JWT_SECRET, 7-day expiry.

const jwt = require('jsonwebtoken');

const SECRET =
  process.env.KLASIFY_JWT_SECRET ||
  'change-this-to-a-long-random-string-in-production';
const TTL_HOURS = 24 * 7; // 7 days

function signToken(userId, email) {
  return jwt.sign({ user_id: userId, email }, SECRET, {
    algorithm: 'HS256',
    expiresIn: `${TTL_HOURS}h`,
  });
}

/// ISO timestamp the current token expires at, for the auth responses.
function expiresAtIso() {
  return new Date(Date.now() + TTL_HOURS * 3600 * 1000).toISOString();
}

/// Returns the payload, or null when the signature is bad / malformed.
function verifyToken(token, { ignoreExpiration = false } = {}) {
  try {
    return jwt.verify(token, SECRET, {
      algorithms: ['HS256'],
      ignoreExpiration,
    });
  } catch {
    return null;
  }
}

/// Express middleware: resolves the Bearer token and attaches req.userId,
/// or writes the contract's 401 error shape and stops the chain.
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) {
    return res
      .status(401)
      .json({ error: 'Missing authorization token', code: 'UNAUTHORIZED' });
  }
  const payload = verifyToken(match[1]);
  if (!payload || payload.user_id === undefined) {
    return res
      .status(401)
      .json({ error: 'Invalid or expired token', code: 'TOKEN_EXPIRED' });
  }
  req.userId = Number(payload.user_id);
  next();
}

module.exports = { signToken, expiresAtIso, verifyToken, requireAuth, TTL_HOURS };
