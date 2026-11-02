import { spawnSync } from 'node:child_process';
const run = spawnSync(process.execPath, ['--test', 'test/passenger-postgres.test.js', 'test/gps-postgres.test.js'], {
  env: { ...process.env, AUTH_INTEGRATION: 'true' }, stdio: 'inherit',
});
process.exitCode = run.status ?? 1;
