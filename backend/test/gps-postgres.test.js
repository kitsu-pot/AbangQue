import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createGpsHarness } from '../test-support/gps-harness.js';
import { createApp } from '../src/app.js';

test('real simulator → authenticated HTTP → PostgreSQL → public read flow', { skip: process.env.AUTH_INTEGRATION !== 'true' }, async t => {
  const h = await createGpsHarness();
  try {
    const read = async () => (await (await fetch(h.url + '/api/jeepneys/SIM-GPS-001')).json()).data;
    await t.test('valid simulated credential, moving coordinates and manual status updates', async () => {
      h.simulator.setStatus('AVAILABLE'); h.simulator.paused = false;
      assert.equal(await h.simulator.tick(), true);
      const first = await read();
      h.simulator.setStatus('FULL'); await h.simulator.tick();
      const second = await read();
      assert.notDeepEqual(second.position, first.position);
      assert.equal(first.status, 'AVAILABLE'); assert.equal(second.status, 'FULL');
      assert.equal(second.connectionStatus, 'ONLINE'); assert.equal(second.eta, null);
      assert.equal(second.isSimulated, true); assert.equal(second.source, 'simulated');
      assert.equal(second.isDemo, true); assert.notEqual(first.timestamp, second.timestamp);
      const stored = await h.pool.query('SELECT DISTINCT source FROM location_status_updates');
      assert.deepEqual(stored.rows, [{ source: 'simulated' }]);
    });
    await t.test('pause sends no records, stale reports lose status, resume recovers', async () => {
      const count = () => h.pool.query('SELECT count(*) FROM location_status_updates');
      const before = (await count()).rows;
      h.simulator.paused = true; assert.equal(await h.simulator.tick(), false);
      assert.deepEqual((await count()).rows, before);
      await h.age();
      const stale = await read();
      assert.equal(stale.status, null); assert.equal(stale.isStale, true); assert.equal(stale.connectionStatus, 'OFFLINE');
      h.simulator.paused = false; h.simulator.setStatus('AVAILABLE'); await h.simulator.tick();
      const resumed = await read(); assert.equal(resumed.status, 'AVAILABLE'); assert.equal(resumed.isStale, false);
    });
    await t.test('explicit test assignment only; disabled and production APIs hide and reject simulation', async () => {
      const catalog = (await (await fetch(h.url + '/api/routes')).json()).data;
      assert.equal(catalog.routes[0].isDemo, true);
      assert.deepEqual(catalog.assignments.map(a => a.jeepneyId), ['SIM-GPS-001']);
      for (const overrides of [{ ENABLE_GPS_SIMULATOR: 'false' }, { NODE_ENV: 'production' }]) {
        const app = createApp({ repository: h.repository, config: { ...h.config, INCLUDE_DEMO: 'true', ...overrides } });
        assert.ok(!(await request(app).get('/api/jeepneys').expect(200)).body.data.some(v => v.isSimulated));
        await request(app).get('/api/jeepneys/SIM-GPS-001').expect(404);
        assert.deepEqual((await request(app).get('/api/routes')).body.data.routes, []);
        await request(app).post('/api/device-updates').set('Authorization', 'Bearer ' + h.key.token).send({}).expect(403);
      }
    });
    await t.test('wrong secret, wrong vehicle, duplicates and revocation preserve device protection', async () => {
      const body = { jeepneyId: 'SIM-GPS-001', latitude: 13, longitude: 121, status: 'FULL', timestamp: new Date().toISOString() };
      const post = token => request(h.app).post('/api/device-updates').set('Authorization', 'Bearer ' + token);
      await post(h.key.id + '.' + '0'.repeat(64)).send(body).expect(401);
      await post(h.key.token).send({ ...body, jeepneyId: 'UNASSIGNED' }).expect(403);
      await post(h.key.token).send(body).expect(201);
      await post(h.key.token).send(body).expect(409);
      await h.pool.query('UPDATE device_credentials SET revoked_at=now() WHERE id=$1', [h.key.id]);
      await post(h.key.token).send(body).expect(401);
    });
  } finally { await h.close(); }
});
