import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { provisionFirstAdmin } from '../src/admin-provision.js';

const config = loadConfig({ DATABASE_URL: 'postgresql://unused@127.0.0.1/unused' });
const origin = config.ADMIN_WEB_ORIGINS;
const make = (overrides = {}, repository = {}) => createApp({ repository: {}, adminRepository: repository, config: { ...config, ...overrides } });
test('admin APIs reject guest, passenger bearer, device bearer and passenger cookies', async () => {
  const app = make({}, { session: async () => null });
  for (const path of ['/session', '/dashboard']) {
    await request(app).get('/api/admin' + path).expect(401);
    await request(app).get('/api/admin' + path).set('Authorization', 'Bearer aqp_' + 'x'.repeat(43)).expect(401);
    await request(app).get('/api/admin' + path).set('Authorization', 'Bearer device-token').expect(401);
    await request(app).get('/api/admin' + path).set('Cookie', 'abangque_admin=aqp_' + 'x'.repeat(43)).expect(401);
  }
});
test('server authorization rejects wrong roles and expired sessions even with a well-formed admin token', async () => {
  for (const session of [{ role: 'PASSENGER', expires_at: new Date(Date.now() + 10000) }, { role: 'ADMIN', expires_at: new Date(0) }]) {
    await request(make({}, { session: async () => session })).get('/api/admin/dashboard')
      .set('Cookie', 'abangque_admin=aqa_' + 'x'.repeat(43)).expect(401);
  }
});
test('CSRF checks protect login and logout; only exact configured origins receive CORS', async () => {
  const app = make({}, { revoke: async () => {} });
  for (const path of ['/login', '/logout']) {
    await request(app).post('/api/admin' + path).send({}).expect(403);
    await request(app).post('/api/admin' + path).set('Origin', origin).send({}).expect(403);
    await request(app).post('/api/admin' + path).set('Origin', origin + '.evil.test').set('X-AbangQue-Admin', '1').send({}).expect(403);
  }
  const allowed = await request(app).options('/api/admin/login').set('Origin', origin).expect(204);
  assert.equal(allowed.headers['access-control-allow-origin'], origin);
  assert.equal(allowed.headers['access-control-allow-credentials'], 'true');
  const denied = await request(app).options('/api/admin/login').set('Origin', 'null').expect(403);
  assert.equal(denied.headers['access-control-allow-origin'], undefined);
  await request(app).post('/api/admin/logout').set('Origin', origin).set('X-AbangQue-Admin', '1').send({}).expect(204);
});
test('admin input is strict, no public registration, login attempts are limited', async () => {
  const app = make({ ADMIN_AUTH_RATE_LIMIT: 2 });
  const post = () => request(app).post('/api/admin/login').set('Origin', origin).set('X-AbangQue-Admin', '1');
  await post().send({ email: 'admin@example.test', password: 'test', role: 'ADMIN' }).expect(400);
  await post().send({ email: 'invalid', password: 'test' }).expect(400);
  await post().send({ email: 'admin@example.test', password: 'test' }).expect(429);
  await request(app).post('/api/admin/register').set('Origin', origin).set('X-AbangQue-Admin', '1').send({}).expect(401);
});
test('production refuses cleartext, invalid origins, unsafe SameSite and spoofed forwarding', async () => {
  await request(make({ NODE_ENV: 'production' })).get('/api/admin/session').set('X-Forwarded-Proto', 'https').expect(403);
  for (const overrides of [{ NODE_ENV: 'production' }, { ADMIN_WEB_ORIGINS: '*' }, { ADMIN_WEB_ORIGINS: 'https://example.test/path' }, { ADMIN_COOKIE_SAME_SITE: 'none' }])
    assert.throws(() => loadConfig({ DATABASE_URL: config.DATABASE_URL, ...overrides }));
});
test('first-admin provisioning rejects non-local databases, production, weak passwords and injected roles', async () => {
  const repository = { provisionFirst: async () => assert.fail('Must not write') };
  const input = { email: 'admin@example.test', password: 'long test-only password' };
  for (const overrides of [{ NODE_ENV: 'production' }, { DATABASE_URL: 'postgresql://unused@remote.test/db' }, { HOST: '0.0.0.0' }])
    await assert.rejects(provisionFirstAdmin({ repository, config: { ...config, ...overrides }, input }));
  for (const invalid of [{ ...input, password: 'short' }, { ...input, role: 'ADMIN' }, { ...input, password: 'passwordpassword' }])
    await assert.rejects(provisionFirstAdmin({ repository, config, input: invalid }));
});
