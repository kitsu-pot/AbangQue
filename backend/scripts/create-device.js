import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import { issueCredential } from '../src/security.js';
import { jeepneyId } from '../src/validation.js';
const id = process.argv[2];
if (!jeepneyId.safeParse(id).success) throw new Error('Usage: npm run device:create -- REGISTERED_JEEPNEY_ID');
const pool = createPool(loadConfig());
try {
  const credential = issueCredential();
  await pool.query('INSERT INTO device_credentials(id, jeepney_id, secret_hash) VALUES ($1, $2, $3)',
    [credential.id, id, credential.secretHash]);
  console.log('Provision this bearer token on the assigned device only. Shown once; never put it in Flutter, Git, or logs:');
  console.log(credential.token);
} catch {
  console.error('Credential creation failed. Register a device-source jeepney and run migrations first.');
  process.exitCode = 1;
} finally { await pool.end(); }

