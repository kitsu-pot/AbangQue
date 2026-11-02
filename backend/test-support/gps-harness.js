// Test-only real PostgreSQL/HTTP harness. No test controls are mounted by src/server.js.
import { randomBytes } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { createServer } from 'node:http';
import pg from 'pg';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { PostgresRepository } from '../src/repository.js';
import { issueCredential } from '../src/security.js';
import { simulatorId } from '../src/simulation.js';
import { GpsSimulator } from '../scripts/gps-simulator-core.js';

export async function createGpsHarness({ controls = false } = {}) {
  const config = loadConfig({ ...process.env, NODE_ENV: 'development', HOST: '127.0.0.1',
    ENABLE_GPS_SIMULATOR: 'true', STALE_AFTER_SECONDS: '10' });
  const schema = 'gps_test_' + randomBytes(12).toString('hex');
  const admin = new pg.Pool({ connectionString: config.DATABASE_URL, connectionTimeoutMillis: 5000 });
  let pool, server, simulator;
  async function close() {
    if (server?.listening) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
    if (pool) await pool.end();
    if (/^gps_test_[0-9a-f]{24}$/.test(schema)) await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await admin.end();
  }
  try {
    await admin.query(`CREATE SCHEMA "${schema}"`);
    pool = new pg.Pool({ connectionString: config.DATABASE_URL, options: `-c search_path=${schema}`, connectionTimeoutMillis: 5000 });
    for (const name of (await readdir(new URL('../migrations/', import.meta.url))).filter(n => n.endsWith('.sql')).sort()) {
      await pool.query(await readFile(new URL('../migrations/' + name, import.meta.url), 'utf8'));
    }
    const key = issueCredential();
    await pool.query("INSERT INTO jeepneys(id,name,source) VALUES ($1,'SIMULATED integration jeepney','simulated'),('UNASSIGNED','Unassigned test fixture','device')", [simulatorId]);
    await pool.query("INSERT INTO device_credentials(id,jeepney_id,source,secret_hash) VALUES ($1,$2,'simulated',$3)", [key.id, simulatorId, key.secretHash]);
    const repository = new PostgresRepository(pool);
    const app = createApp({ repository, config });
    const age = () => pool.query("UPDATE location_status_updates SET recorded_at=recorded_at-interval '20 seconds',received_at=received_at-interval '20 seconds' WHERE jeepney_id=$1", [simulatorId]);
    server = createServer(async (req, res) => {
      if (!controls || !req.url.startsWith('/__test/')) return app(req, res);
      // Bound to ephemeral localhost, exists only while the integration runner lives.
      try {
        if (req.method !== 'POST') { res.writeHead(405); return res.end(); }
        const command = req.url.slice('/__test/'.length);
        if (command === 'stale') { simulator.paused = true; await age(); }
        else if (['available', 'full'].includes(command)) {
          simulator.setStatus(command.toUpperCase()); simulator.paused = false; await simulator.tick();
        } else { res.writeHead(404); return res.end(); }
        res.writeHead(204); res.end();
      } catch { res.writeHead(500); res.end(); }
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const url = 'http://127.0.0.1:' + server.address().port;
    simulator = new GpsSimulator({ url, credential: { jeepneyId: simulatorId, token: key.token } });
    await simulator.verify();
    return { config, repository, pool, app, url, simulator, key, age, close };
  } catch (error) { await close(); throw error; }
}
