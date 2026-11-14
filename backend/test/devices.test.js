import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { registration } from '../src/admin-devices.js';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
const input = {
  id: 'TEST-DEVICE',
  label: null,
  model: null,
  description: null,
  administrativeNotes: null,
  enabled: true,
  jeepneyId: null,
};
test('device registration rejects invalid IDs, protected fields and excessive metadata', () => {
  assert.ok(registration.safeParse(input).success);
  for (const patch of [
    { id: 'bad id' },
    { id: 'LEGACY-VEHICLE' },
    { id: 'SIM-GPS-001' },
    { id: 'DEMO-DEVICE' },
    { label: 'x'.repeat(121) },
    { description: 'new\nline' },
    { enabled: 'yes' },
    { source: 'simulated' },
    { token: 'secret' },
    { latitude: 13 },
    { status: 'FULL' },
    { jeepneyId: 'bad id' },
  ])
    assert.equal(registration.safeParse({ ...input, ...patch }).success, false);
});
test('guest/passenger credentials cannot manage devices and CSRF applies to all sensitive actions', async () => {
  const config = loadConfig({
    DATABASE_URL: 'postgresql://unused@127.0.0.1/unused',
  });
  const app = createApp({
    config,
    adminRepository: { session: async () => null },
    adminDeviceRepository: {},
  });
  for (const path of [
    '/devices',
    '/devices/TEST-DEVICE',
    '/device-jeepney-options',
  ])
    await request(app)
      .get('/api/admin' + path)
      .set('Authorization', 'Bearer passenger')
      .expect(401);
  for (const path of [
    '/devices',
    '/devices/TEST-DEVICE/assignment',
    '/devices/TEST-DEVICE/state',
    '/devices/TEST-DEVICE/provision',
    '/devices/TEST-DEVICE/rotate',
    '/devices/TEST-DEVICE/revoke',
  ]) {
    await request(app)
      .post('/api/admin' + path)
      .set('Origin', config.ADMIN_WEB_ORIGINS)
      .set('X-AbangQue-Admin', '1')
      .set('Authorization', 'Bearer passenger')
      .send(input)
      .expect(401);
    await request(app)
      .post('/api/admin' + path)
      .send(input)
      .expect(403);
  }
});
test('device write failures are sanitized, never returning generated secrets', async () => {
  const config = loadConfig({
    DATABASE_URL: 'postgresql://unused@127.0.0.1/unused',
  });
  const app = createApp({
    config,
    adminRepository: {
      session: async () => ({
        id: 'admin',
        role: 'ADMIN',
        expires_at: new Date(Date.now() + 60000),
      }),
    },
    adminDeviceRepository: {
      change: async () => {
        throw new Error('secret-internal-detail');
      },
    },
  });
  const result = await request(app)
    .post('/api/admin/devices/TEST-DEVICE/rotate')
    .set('Cookie', 'abangque_admin=aqa_' + 'x'.repeat(43))
    .set('Origin', config.ADMIN_WEB_ORIGINS)
    .set('X-AbangQue-Admin', '1')
    .send({ expectedVersion: 1 })
    .expect(503);
  assert.deepEqual(result.body, { error: 'SERVICE_UNAVAILABLE' });
});
