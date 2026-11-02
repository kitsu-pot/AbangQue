import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import pg from 'pg';
import request from 'supertest';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { PostgresRepository } from '../src/repository.js';
import { PassengerRepository } from '../src/passenger-repository.js';
import { hashToken } from '../src/passenger-auth.js';

test('real PostgreSQL passenger authentication', { skip: process.env.AUTH_INTEGRATION !== 'true' }, async t => {
  const config = loadConfig({ ...process.env, NODE_ENV: 'test', AUTH_RATE_LIMIT: '100' });
  const schema = 'auth_test_' + randomBytes(12).toString('hex');
  const admin = new pg.Pool({ connectionString: config.DATABASE_URL, connectionTimeoutMillis: 5000 });
  let pool;
  try {
    // Generated identifier only. Never touch existing application tables/accounts.
    await admin.query(`CREATE SCHEMA "${schema}"`);
    pool = new pg.Pool({ connectionString: config.DATABASE_URL, options: `-c search_path=${schema}`, connectionTimeoutMillis: 5000 });
    for (const name of ['001_initial.sql', '002_passenger_auth.sql', '003_simulated_device_source.sql']) {
      await pool.query(await readFile(new URL('../migrations/' + name, import.meta.url), 'utf8'));
    }
    const app = createApp({ repository: new PostgresRepository(pool), passengerRepository: new PassengerRepository(pool), config });
    const password = randomBytes(24).toString('base64url');
    const data = { fullName: 'Integration Passenger', email: 'passenger@example.test', password };
    let registered, loggedIn;
    await t.test('registers a PASSENGER and stores only Argon2id/password and session hashes', async () => {
      registered = (await request(app).post('/api/auth/register').send(data).expect(201)).body.data;
      assert.equal(registered.user.role, 'PASSENGER');
      const row = (await pool.query('SELECT * FROM passenger_accounts')).rows[0];
      assert.ok(row.password_hash.startsWith('$argon2id$v=19$m=65536,t=3,p=1$'));
      assert.notEqual(row.password_hash, password);
      const session = (await pool.query('SELECT * FROM passenger_sessions')).rows[0];
      assert.equal(session.token_hash, hashToken(registered.token));
      assert.ok(new Date(registered.expiresAt) > new Date());
      assert.ok(!JSON.stringify(registered).includes('password_hash'));
    });
    await t.test('rejects normalized duplicate email and concurrent registration duplicates', async () => {
      await request(app).post('/api/auth/register').send({ ...data, email: ' PASSENGER@EXAMPLE.TEST ' }).expect(409);
      const results = await Promise.all([1, 2].map(() => request(app).post('/api/auth/register').send({ ...data, email: 'race@example.test' })));
      assert.deepEqual(results.map(r => r.status).sort(), [201, 409]);
    });
    await t.test('successful login and restoration verify the server session', async () => {
      loggedIn = (await request(app).post('/api/auth/login').send({ email: data.email.toUpperCase(), password }).expect(200)).body.data;
      assert.notEqual(loggedIn.token, registered.token);
      const restored = (await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + loggedIn.token).expect(200)).body.data;
      assert.equal(restored.user.id, registered.user.id);
    });
    await t.test('wrong password and unknown email have identical login responses', async () => {
      const wrong = await request(app).post('/api/auth/login').send({ email: data.email, password: 'wrong password value' }).expect(401);
      const unknown = await request(app).post('/api/auth/login').send({ email: 'unknown@example.test', password }).expect(401);
      assert.deepEqual(wrong.body, unknown.body);
    });
    await t.test('strict validation rejects weak passwords, bad email and administrator registration', async () => {
      for (const input of [{ ...data, password: 'short' }, { ...data, fullName: ' ' }, { ...data, email: 'invalid' }, { ...data, role: 'ADMIN' }]) {
        await request(app).post('/api/auth/register').send(input).expect(400);
      }
      await request(app).post('/api/auth/register').type('text').send('bad').expect(415);
      await request(app).post('/api/auth/register').type('json').send('{').expect(400);
    });
    await t.test('profile editing is scoped to the session and cannot change role/email/id', async () => {
      const auth = 'Bearer ' + loggedIn.token;
      const result = await request(app).patch('/api/auth/me').set('Authorization', auth).send({ fullName: 'Updated Passenger' }).expect(200);
      assert.equal(result.body.data.user.fullName, 'Updated Passenger');
      for (const input of [{ role: 'ADMIN' }, { email: 'new@example.test' }, { id: registered.user.id }]) {
        await request(app).patch('/api/auth/me').set('Authorization', auth).send({ fullName: 'X', ...input }).expect(400);
      }
      await request(app).get('/api/auth/me').expect(401);
    });
    await t.test('logout revokes server session, is idempotent and leaves other sessions independent', async () => {
      await request(app).post('/api/auth/logout').set('Authorization', 'Bearer ' + loggedIn.token).expect(204);
      await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + loggedIn.token).expect(401);
      await request(app).post('/api/auth/logout').set('Authorization', 'Bearer ' + loggedIn.token).expect(204);
      await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + registered.token).expect(200);
    });
    await t.test('expired and revoked sessions cannot access protected endpoints', async () => {
      await pool.query("UPDATE passenger_sessions SET created_at=now()-interval '2 days', expires_at=now()-interval '1 day' WHERE token_hash=$1", [hashToken(registered.token)]);
      await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + registered.token).expect(401);
      await request(app).patch('/api/auth/me').set('Authorization', 'Bearer ' + registered.token).send({ fullName: 'No' }).expect(401);
    });
    await t.test('public transportation remains accessible to guests; passenger cannot submit device telemetry', async () => {
      await pool.query("INSERT INTO jeepneys(id,name,source) VALUES ('AUTH-TEST','Test fixture','device')");
      await request(app).get('/api/jeepneys').expect(200);
      await request(app).get('/api/jeepneys/AUTH-TEST').expect(200);
      await request(app).get('/health').expect(200);
      await request(app).post('/api/device-updates').set('Authorization', 'Bearer ' + registered.token).send({}).expect(401);
    });
  } finally {
    if (pool) await pool.end();
    // Only the random schema created above is removed, including its test data.
    if (/^auth_test_[0-9a-f]{24}$/.test(schema)) await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await admin.end();
  }
});
