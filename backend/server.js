// server.js
// Klasify sync backend entry point: one Express app wiring CORS, JSON
// parsing, the health check, and the /auth + /sync routers to one port.
// Every route matches docs/sync_api_contract.md — the Flutter client did
// not need a single change when this backend replaced the PHP one.

const express = require('express');
const db = require('./src/db');

const authRoutes = require('./src/auth');
const syncRoutes = require('./src/sync');

const app = express();
const PORT = parseInt(process.env.KLASIFY_PORT || '80', 10);

// CORS: the Flutter http client ignores CORS, but browsers / tests don't.
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).end();
  next();
});

// Sync payloads are small; 4mb is a generous ceiling.
app.use(express.json({ limit: '4mb' }));

app.get('/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0' });
});

app.use('/auth', authRoutes);
app.use('/sync', syncRoutes);

// 404s use the same shape as every other error in the contract.
app.use((req, res) => {
  res.status(404).json({ error: 'Not found', code: 'NOT_FOUND' });
});

// Central handler: malformed JSON -> 422 like any other validation issue;
// anything unexpected -> 500 without leaking internals.
app.use((err, req, res, next) => {
  if (err && err.type === 'entity.parse.failed') {
    return res
      .status(422)
      .json({ error: 'Malformed JSON body', code: 'VALIDATION_ERROR' });
  }
  console.error(err);
  return res
    .status(500)
    .json({ error: 'Internal server error', code: 'SERVER_ERROR' });
});

app.listen(PORT, () => {
  console.log(`Klasify sync backend listening on :${PORT}`);
  db.ping().catch((e) => console.error('DB ping failed:', e.message));
});
