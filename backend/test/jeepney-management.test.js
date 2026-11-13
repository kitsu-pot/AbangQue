import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createJeepney, editJeepney } from '../src/admin-jeepneys.js';

const config = loadConfig({ DATABASE_URL: 'postgresql://unused@127.0.0.1/unused' });
const input = { id: 'TEST-01', name: 'Test vehicle', plateNumber: null, description: '', administrativeNotes: '', active: true, routeId: null };
const cookie = 'abangque_admin=aqa_' + 'x'.repeat(43);
function app(admin = true, repo = {}) { return createApp({ config,
  adminRepository: { session: async () => admin ? { id: 'test-admin', role: 'ADMIN', expires_at: new Date(Date.now() + 60000) } : null },
  adminJeepneyRepository: repo }); }
const write = (server, method, path) => request(server)[method]('/api/admin' + path).set('Origin', config.ADMIN_WEB_ORIGINS).set('X-AbangQue-Admin', '1');

test('registration schemas reject mass assignment and immutable identifier edits', () => {
  assert.equal(createJeepney.parse({ ...input, plateNumber: ' ab 12 ' }).plateNumber, 'AB 12');
  for (const change of [{ id: 'bad id' }, { active: 'true' }, { plateNumber: '<bad>' }, { plateNumber: 'A' }, { name: '' },
    { routeId: 'DEMO-PATH-BOAC-MOGPOG' }, { source: 'simulated' }, { status: 'AVAILABLE' }, { latitude: 13 }, { version: 10 },
    { administrativeNotes: 'private\nnew line' }, { description: 'x'.repeat(501) }])
    assert.equal(createJeepney.safeParse({ ...input, ...change }).success, false);
  const { id, active, ...editable } = input;
  assert.equal(editJeepney.safeParse({ ...editable, expectedVersion: 1 }).success, true);
  assert.equal(editJeepney.safeParse({ ...editable, expectedVersion: 1, id }).success, false);
  assert.equal(editJeepney.safeParse({ ...editable, expectedVersion: 1, active }).success, false);
});
test('guest and passenger credentials cannot read or write jeepney management', async () => {
  const server = app(false);
  for (const path of ['/jeepneys', '/jeepneys/TEST-01', '/route-options']) await request(server).get('/api/admin' + path).expect(401);
  for (const [method, path] of [['post', '/jeepneys'], ['put', '/jeepneys/TEST-01'], ['post', '/jeepneys/TEST-01/activation']]) {
    await write(server, method, path).send(input).expect(401);
    await write(server, method, path).set('Authorization', 'Bearer aqp_' + 'x'.repeat(43)).send(input).expect(401);
  }
});
test('writes require trusted Origin/custom header and return safe field errors', async () => {
  const server = app();
  await request(server).put('/api/admin/jeepneys/TEST-01').set('Cookie', cookie).send(input).expect(403);
  const invalid = await write(server, 'post', '/jeepneys').set('Cookie', cookie).send({ ...input, name: '' }).expect(400);
  assert.ok(invalid.body.fields.some(f => f.field === 'name'));
  await request(server).get('/api/admin/jeepneys?page=0').set('Cookie', cookie).expect(400);
  await request(server).get('/api/admin/jeepneys?pageSize=101').set('Cookie', cookie).expect(400);
  await request(server).get('/api/admin/jeepneys?role=ADMIN').set('Cookie', cookie).expect(400);
  await request(server).get('/api/admin/jeepneys/bad%20id').set('Cookie', cookie).expect(400);
});
test('database failures are sanitized and do not claim saves succeeded', async () => {
  const server = app(true, { create: async () => { throw new Error('private database connection details'); } });
  const result = await write(server, 'post', '/jeepneys').set('Cookie', cookie).send(input).expect(503);
  assert.deepEqual(result.body, { error: 'SERVICE_UNAVAILABLE' });
});
