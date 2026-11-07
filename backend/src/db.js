// src/db.js
// MySQL connection pool. Configuration comes from the environment
// (docker-compose passes KLASIFY_DB_*); the defaults match the compose file
// so `node server.js` against a local MySQL with the same credentials works.

const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.KLASIFY_DB_HOST || 'mysql',
  port: parseInt(process.env.KLASIFY_DB_PORT || '3306', 10),
  user: process.env.KLASIFY_DB_USER || 'root',
  password: process.env.KLASIFY_DB_PASS || 'klasify_dev',
  database: process.env.KLASIFY_DB_NAME || 'klasify_sync',
  waitForConnections: true,
  connectionLimit: 10,
  // DATETIME(3)/(DATE) columns hold UTC values (see docs/mysql_schema.sql).
  timezone: 'Z',
  // Return DATETIME/DATE columns as raw strings ('YYYY-MM-DD HH:MM:SS.mmm')
  // instead of JS Date objects — the driver's local-timezone Date
  // conversion would silently shift every timestamp.
  dateStrings: true,
});

/// Normalizes a value (JS Date or ISO string) to the 'YYYY-MM-DD
/// HH:MM:SS.mmm' format the DATETIME(3) columns use, always in UTC.
/// Returns null for null or unparseable input.
function toMysqlTimestamp(value) {
  if (value === null || value === undefined || value === '') return null;
  const d = value instanceof Date ? value : new Date(value);
  if (isNaN(d.getTime())) return null;
  // '2026-11-06T09:30:00.000Z' -> '2026-11-06 09:30:00.000'
  return d.toISOString().slice(0, 19).replace('T', ' ') + '.' +
    String(d.getUTCMilliseconds()).padStart(3, '0');
}

/// The inverse of toMysqlTimestamp for values read back out of the database:
/// '2026-11-06 09:30:00.123' -> '2026-11-06T09:30:00.123Z'. Marked as UTC via
/// the trailing Z so clients parse it as an absolute instant, not local time.
function fromMysqlTimestampToIso(value) {
  if (typeof value !== 'string') return null;
  // Outline the string shape the pool is configured to return.
  const m = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?)$/.exec(value);
  if (!m) return null;
  let frac = (m[2].split('.')[1] || '');
  frac = '.' + frac.padEnd(3, '0').slice(0, 3);
  return m[1] + 'T' + (m[2].split('.')[0]) + frac + 'Z';
}

async function ping() {
  const conn = await pool.getConnection();
  try {
    await conn.ping();
  } finally {
    conn.release();
  }
}

module.exports = { pool, toMysqlTimestamp, fromMysqlTimestampToIso, ping };
