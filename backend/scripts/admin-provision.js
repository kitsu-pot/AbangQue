import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import { AdminRepository } from '../src/admin-repository.js';
import { provisionFirstAdmin } from '../src/admin-provision.js';

let pool;
try {
  if (process.stdin.isTTY || process.argv.length !== 2) throw new Error('Use secure input wrapper');
  let input = '';
  for await (const chunk of process.stdin) {
    input += chunk;
    if (Buffer.byteLength(input) > 4096) throw new Error('Input too large');
  }
  const config = loadConfig();
  pool = createPool(config);
  await provisionFirstAdmin({ repository: new AdminRepository(pool), config, input: JSON.parse(input) });
  console.log('First administrator created. Sign in using your supplied credentials.');
} catch {
  console.error('Administrator not created. Check local development settings, migration 005, email/password policy, and whether an administrator already exists.');
  process.exitCode = 1;
} finally { await pool?.end(); }
