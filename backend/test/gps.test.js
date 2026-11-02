import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { presentJeepney } from '../src/presenter.js';
import { localSimulatorUrl, GpsSimulator } from '../scripts/gps-simulator-core.js';
import { issueCredential } from '../src/security.js';

test('simulation requires explicit development loopback configuration', () => {
  const env = { DATABASE_URL: 'postgresql://test:test@localhost/test', ENABLE_GPS_SIMULATOR: 'true' };
  assert.equal(loadConfig(env).ENABLE_GPS_SIMULATOR, 'true');
  for (const override of [{ NODE_ENV: 'production' }, { NODE_ENV: 'test' }, { HOST: '0.0.0.0' }]) {
    assert.throws(() => loadConfig({ ...env, ...override }));
  }
  for (const url of ['https://example.com', 'http://localhost:3000', 'http://127.0.0.1@evil.test', 'http://127.0.0.1/path']) {
    assert.throws(() => localSimulatorUrl(url));
  }
});
test('simulation provenance and stale status are independent; historical demos stay unknown', () => {
  const now = Date.now();
  const row = { id: 'SIM', name: 'SIMULATED', source: 'simulated', latitude: 13, longitude: 121,
    status: 'FULL', recorded_at: new Date(now), last_seen_at: new Date(now) };
  const fresh = presentJeepney(row, now, 10);
  assert.equal(fresh.status, 'FULL'); assert.equal(fresh.isSimulated, true); assert.equal(fresh.isDemo, true);
  const stale = presentJeepney(row, now + 10000, 10);
  assert.equal(stale.status, null); assert.equal(stale.connectionStatus, 'OFFLINE'); assert.equal(stale.eta, null);
  assert.equal(presentJeepney({ ...row, source: 'demo' }, now, 10).status, null);
});
test('simulator sends nothing before manual status, while paused or before verification', async () => {
  let calls = 0;
  const simulator = new GpsSimulator({ url: 'http://127.0.0.1:3000', credential: { jeepneyId: 'SIM-GPS-001', token: issueCredential().token },
    fetchImpl: async () => { calls++; throw new Error('No network expected'); } });
  assert.equal(await simulator.tick(), false);
  simulator.paused = false; assert.equal(await simulator.tick(), false);
  simulator.setStatus('FULL'); await assert.rejects(simulator.tick());
  simulator.paused = true; assert.equal(await simulator.tick(), false);
  assert.equal(calls, 0); assert.throws(() => simulator.setStatus('AUTO'));
});
