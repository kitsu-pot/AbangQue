import { mkdir, readFile, writeFile, unlink } from 'node:fs/promises';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import { issueCredential, parseToken } from '../src/security.js';
import { requireSimulation, simulatorId } from '../src/simulation.js';

const config = loadConfig();
requireSimulation(config);
const path = new URL('../.local/gps-simulator.json', import.meta.url);
const pool = createPool(config);
let createdFile = false;
const client = await pool.connect();
try {
  await client.query('BEGIN');
  if (process.argv.includes('--revoke')) {
    const saved = JSON.parse(await readFile(path, 'utf8'));
    const token = parseToken('Bearer ' + saved.token);
    if (saved.jeepneyId !== simulatorId || !token) throw new Error('Invalid simulator credential file');
    await client.query("UPDATE device_credentials SET revoked_at=now() WHERE id=$1 AND jeepney_id=$2 AND source='simulated'", [token.id, simulatorId]);
    await client.query('COMMIT');
    await unlink(path);
    console.log('SIMULATED device revoked; local secret removed. Test history retained.');
  } else {
    // Collision with a real vehicle fails; no existing record is relabeled.
    await client.query("INSERT INTO jeepneys(id,name,source) VALUES ($1,'SIMULATED GPS test jeepney','simulated') ON CONFLICT (id) DO NOTHING", [simulatorId]);
    const vehicle = (await client.query('SELECT source FROM jeepneys WHERE id=$1 FOR UPDATE', [simulatorId])).rows[0];
    if (vehicle.source !== 'simulated') throw new Error('Reserved simulator ID is already in use');
    const key = issueCredential();
    await client.query("INSERT INTO device_credentials(id,jeepney_id,source,secret_hash) VALUES ($1,$2,'simulated',$3)", [key.id, simulatorId, key.secretHash]);
    await mkdir(new URL('../.local/', import.meta.url), { recursive: true });
    await writeFile(path, JSON.stringify({ jeepneyId: simulatorId, token: key.token }), { flag: 'wx', mode: 0o600 });
    createdFile = true;
    await client.query('COMMIT');
    console.log('SIMULATED device provisioned. Secret saved in ignored backend/.local/gps-simulator.json; never share this file.');
  }
} catch {
  await client.query('ROLLBACK');
  if (createdFile) await unlink(path).catch(() => {});
  console.error('Simulator provisioning failed. Check migrations and local setup. Existing secret files are never overwritten; revoke first to rotate.');
  process.exitCode = 1;
} finally { client.release(); await pool.end(); }
