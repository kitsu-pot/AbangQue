import { readFile } from 'node:fs/promises';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
const pool = createPool(loadConfig());
let client;
try {
  client = await pool.connect();
  await client.query('BEGIN');
  await client.query('SELECT pg_advisory_xact_lock(71423301)');
  await client.query(await readFile(new URL('../seeds/demo.sql', import.meta.url), 'utf8'));
  await client.query('COMMIT');
  console.log('Historical DEMO fixtures seeded. No hardware was connected.');
} catch {
  if (client) await client.query('ROLLBACK').catch(() => {});
  console.error('Demo seed failed. Check connectivity and run migrations first.');
  process.exitCode = 1;
} finally { client?.release(); await pool.end(); }

