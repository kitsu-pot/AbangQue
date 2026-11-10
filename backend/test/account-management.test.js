import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import * as argon2 from 'argon2';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { passwordOptions } from '../src/passenger-auth.js';

const config = loadConfig({ DATABASE_URL: 'postgresql://unused/unused', AUTH_RATE_LIMIT: '100' });
const token = 'Bearer aqp_' + 'a'.repeat(43);
const current = randomBytes(24).toString('base64url');
const next = randomBytes(24).toString('base64url');
const input = { currentPassword: current, newPassword: next, confirmPassword: next };
function app(repo = {}, overrides = {}) {
  return createApp({ repository: { list: async () => [] }, passengerRepository: {
    session: async () => ({ id: 'account-a', role: 'PASSENGER' }), ...repo,
  }, config: { ...config, ...overrides } });
}

test('sensitive account routes authenticate, strictly validate and never accept target IDs', async () => {
  let calls = 0;
  const server = app({ changePassword: async () => { calls++; }, deleteAccount: async () => { calls++; } });
  for (const [method, path] of [['post', '/api/auth/me/password'], ['delete', '/api/auth/me']]) {
    await request(server)[method](path).send(input).expect(401);
    await request(server)[method](path).set('Authorization', token).send({ ...input, id: 'someone-else' }).expect(400);
  }
  for (const invalid of [
    { ...input, newPassword: 'short', confirmPassword: 'short' },
    { ...input, confirmPassword: 'different' }, { ...input, currentPassword: '' },
    { ...input, newPassword: current, confirmPassword: current },
    { ...input, newPassword: 'a'.repeat(129) }, { ...input, role: 'ADMIN' },
  ]) await request(server).post('/api/auth/me/password').set('Authorization', token).send(invalid).expect(400);
  await request(server).delete('/api/auth/me').set('Authorization', token).send({ currentPassword: current, passengerId: 'someone-else' }).expect(400);
  await request(server).delete('/api/auth/me').set('Authorization', token).type('text').send(current).expect(415);
  assert.equal(calls, 0);
  await request(server).get('/api/jeepneys').expect(200);
});

test('real Argon2 verification rejects wrong current password without expiring the session', async () => {
  const hash = await argon2.hash(current, passwordOptions);
  let changed;
  const server = app({
    changePassword: async (_, verify) => { changed = await verify(hash); },
    deleteAccount: async (_, verify) => { await verify(hash); },
  });
  const wrong = await request(server).post('/api/auth/me/password').set('Authorization', token)
    .send({ ...input, currentPassword: 'wrong' }).expect(403);
  assert.equal(wrong.body.error, 'CURRENT_PASSWORD_INCORRECT');
  assert.equal(changed, undefined);
  await request(server).delete('/api/auth/me').set('Authorization', token).send({ currentPassword: 'wrong' }).expect(403);
  await request(server).post('/api/auth/me/password').set('Authorization', token).send(input).expect(204);
  assert.ok(await argon2.verify(changed, next));
  assert.notEqual(changed, next);
});

test('password/deletion attempts share rate limits and generic database failure responses', async () => {
  const server = app({}, { AUTH_RATE_LIMIT: 2 });
  await request(server).post('/api/auth/me/password').set('Authorization', token).send({}).expect(400);
  await request(server).delete('/api/auth/me').set('Authorization', token).send({}).expect(400);
  const limited = await request(server).post('/api/auth/me/password').set('Authorization', token).send(input).expect(429);
  assert.equal(limited.body.error, 'AUTH_RATE_LIMITED');
  const failed = app({ deleteAccount: async () => { throw new Error('private database details'); } });
  const response = await request(failed).delete('/api/auth/me').set('Authorization', token).send({ currentPassword: current }).expect(503);
  assert.deepEqual(response.body, { error: 'SERVICE_UNAVAILABLE' });
  const revoked = app({ changePassword: async () => { throw Object.assign(new Error(), { accountError: 'SESSION_INVALID' }); } });
  await request(revoked).post('/api/auth/me/password').set('Authorization', token).send(input).expect(401);
});

test('sensitive account throttling survives token/IP changes for the same authenticated passenger', async () => {
  const server = app({}, { AUTH_RATE_LIMIT: 2, TRUST_PROXY: 'loopback' });
  for (let i = 1; i <= 3; i++) {
    await request(server).post('/api/auth/me/password')
      .set('X-Forwarded-For', '192.0.2.' + i)
      .set('Authorization', 'Bearer aqp_' + String(i).repeat(43))
      .send({}).expect(i === 3 ? 429 : 400);
  }
});
