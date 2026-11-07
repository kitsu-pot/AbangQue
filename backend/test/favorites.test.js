import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
const config = loadConfig({ DATABASE_URL: 'postgresql://unused/unused' });
const id = '11111111-1111-4111-8111-111111111111';
const auth = 'Bearer aqp_' + 'x'.repeat(43);
function app({ role = 'PASSENGER', session = true, overrides = {}, repo = {} } = {}) {
  return createApp({ config: { ...config, ...overrides }, repository: { list: async () => [] },
    passengerRepository: { session: async () => session ? { id: 'server-identity', role } : null },
    favoriteRepository: { catalog: async () => ({ routes: [], assignments: [] }), list: async () => [], save: async () => true, remove: async () => {}, ...repo } });
}
test('favorites require passenger sessions; transport remains public', async () => {
  const server = app();
  for (const method of ['get', 'put', 'delete']) {
    const path = '/api/favorites' + (method === 'get' ? '' : '/' + id);
    await request(server)[method](path).expect(401);
    await request(server)[method](path).set('Authorization', 'Bearer device-secret').expect(401);
    await request(app({ session: false }))[method](path).set('Authorization', auth).expect(401);
    await request(app({ role: 'ADMIN' }))[method](path).set('Authorization', auth).expect(403);
  }
  await request(server).get('/api/routes').expect(200);
  await request(server).get('/api/jeepneys').expect(200);
});
test('favorites reject insecure production requests and forged forwarded protocol', async () => {
  await request(app({ overrides: { NODE_ENV: 'production' } })).get('/api/favorites')
    .set('Authorization', auth).set('X-Forwarded-Proto', 'https').expect(403);
});
test('identity comes exclusively from the session and input is strict', async () => {
  const calls = [];
  const server = app({ repo: {
    list: async passenger => { calls.push([passenger]); return []; },
    save: async (passenger, route) => { calls.push([passenger, route]); return true; },
    remove: async (passenger, route) => { calls.push([passenger, route]); },
  } });
  await request(server).get('/api/favorites?passengerId=other').set('Authorization', auth).expect(400);
  await request(server).put('/api/favorites/' + id).set('Authorization', auth).send({ passengerId: 'other' }).expect(400);
  await request(server).put('/api/favorites/DEMO-PATH-BOAC-MOGPOG').set('Authorization', auth).expect(400);
  await request(server).put('/api/favorites/not-an-id').set('Authorization', auth).expect(400);
  await request(server).put('/api/favorites/' + id).set('Authorization', auth).type('text').send('userId=other').expect(415);
  await request(server).get('/api/favorites').set('Authorization', auth).expect(200);
  await request(server).put('/api/favorites/' + id).set('Authorization', auth).expect(204);
  await request(server).delete('/api/favorites/' + id).set('Authorization', auth).expect(204);
  assert.deepEqual(calls, [['server-identity'], ['server-identity', id], ['server-identity', id]]);
});
test('unavailable routes and repository failures never report successful saves', async () => {
  await request(app({ repo: { save: async () => false } })).put('/api/favorites/' + id).set('Authorization', auth).expect(409);
  const result = await request(app({ repo: { save: async () => { throw Error('private database detail'); } } }))
    .put('/api/favorites/' + id).set('Authorization', auth).expect(503);
  assert.deepEqual(result.body, { error: 'SERVICE_UNAVAILABLE' });
});
