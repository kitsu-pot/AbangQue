import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
const config = loadConfig({ DATABASE_URL: 'postgresql://unused/unused' });
function app(overrides = {}, repo = {}) {
  return createApp({ repository: { list: async () => [] }, passengerRepository: repo, config: { ...config, ...overrides } });
}
test('auth requires input validation, rejects public role injection and limits attempts', async () => {
  const server = app({ AUTH_RATE_LIMIT: 2 });
  await request(server).post('/api/auth/register').send({ fullName: 'X', email: 'bad', password: 'short', role: 'ADMIN' }).expect(400);
  await request(server).post('/api/auth/login').send({ email: 'bad', password: 'x' }).expect(400);
  await request(server).post('/api/auth/login').send({ email: 'bad', password: 'x' }).expect(429);
  await request(server).get('/api/jeepneys').expect(200);
});
test('production rejects plaintext authentication and untrusted forwarded protocol', async () => {
  await request(app({ NODE_ENV: 'production' })).post('/api/auth/login').set('X-Forwarded-Proto', 'https').send({}).expect(403);
});
test('protected profile rejects missing credentials, device tokens and wrong roles', async () => {
  const server = app({}, { session: async () => ({ role: 'ADMIN' }) });
  await request(server).get('/api/auth/me').expect(401);
  await request(server).patch('/api/auth/me').set('Authorization', 'Bearer device-secret').send({ fullName: 'X' }).expect(401);
  await request(server).get('/api/auth/me').set('Authorization', 'Bearer aqp_' + 'x'.repeat(43)).expect(403);
});
