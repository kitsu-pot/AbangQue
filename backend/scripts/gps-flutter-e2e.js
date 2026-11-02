import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createGpsHarness } from '../test-support/gps-harness.js';

const harness = await createGpsHarness({ controls: true });
try {
  // Only a random local test URL crosses into Flutter; device secrets stay in Node.
  const args = ['test', 'test/gps_e2e_test.dart', '--reporter', 'expanded', '--dart-define=GPS_E2E_URL=' + harness.url];
  const windows = process.platform === 'win32';
  const child = spawn(windows ? 'cmd.exe' : 'flutter', windows ? ['/d', '/c', 'flutter', ...args] : args,
    { cwd: fileURLToPath(new URL('../../', import.meta.url)), stdio: 'inherit' });
  process.exitCode = await new Promise((resolve, reject) => { child.on('error', reject); child.on('exit', code => resolve(code ?? 1)); });
} finally { await harness.close(); }
