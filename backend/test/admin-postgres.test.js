import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import pg from 'pg';
import request from 'supertest';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { AdminRepository } from '../src/admin-repository.js';
import { PassengerRepository } from '../src/passenger-repository.js';
import { provisionFirstAdmin } from '../src/admin-provision.js';
import { hashToken } from '../src/passenger-auth.js';

test('real PostgreSQL administrator foundation', { skip: process.env.AUTH_INTEGRATION !== 'true' }, async t => {
  const config = loadConfig({ ...process.env, NODE_ENV: 'test', ENABLE_GPS_SIMULATOR: 'false', ADMIN_AUTH_RATE_LIMIT: '100' });
  const schema = 'admin_test_' + randomBytes(12).toString('hex');
  const control = new pg.Pool({ connectionString: config.DATABASE_URL, connectionTimeoutMillis: 5000 });
  let pool;
  try {
    await control.query(`CREATE SCHEMA "${schema}"`);
    pool = new pg.Pool({ connectionString: config.DATABASE_URL, options: `-c search_path=${schema}`, connectionTimeoutMillis: 5000 });
    const migrations = new URL('../migrations/', import.meta.url);
    for (const file of (await readdir(migrations)).filter(f => f.endsWith('.sql')).sort()) await pool.query(await readFile(new URL(file, migrations), 'utf8'));
    const repo = new AdminRepository(pool);
    const app = createApp({ adminRepository: repo, passengerRepository: new PassengerRepository(pool), config });
    const password = randomBytes(24).toString('base64url'), email = 'admin@example.test';
    const write = path => request(app).post('/api/admin' + path).set('Origin', config.ADMIN_WEB_ORIGINS.split(',')[0]).set('X-AbangQue-Admin', '1');
    const login = (address = email, pass = password) => write('/login').send({ email: address, password: pass });
    let cookie;
    await t.test('first provisioning is normalized, hash-only and serialized; second admin refused', async () => {
      // This isolated test uses local development policy; the real database name is unchanged.
      const provisionConfig = { ...config, NODE_ENV: 'development', HOST: '127.0.0.1' };
      await provisionFirstAdmin({ repository: repo, config: provisionConfig, input: { email: ' Admin@Example.Test ', password } });
      const stored = await repo.findByEmail(email);
      assert.equal(stored.role, 'ADMIN'); assert.ok(stored.password_hash.startsWith('$argon2id$'));
      assert.ok(!stored.password_hash.includes(password));
      await assert.rejects(provisionFirstAdmin({ repository: repo, config: provisionConfig, input: { email: 'other@example.test', password } }));
      const concurrent = await Promise.allSettled([repo.provisionFirst(email, stored.password_hash), repo.provisionFirst('third@example.test', stored.password_hash)]);
      assert.ok(concurrent.every(r => r.status === 'rejected'));
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM admin_accounts')).rows[0].n, 1);
    });
    await t.test('valid login sets HttpOnly cookie; no token or password in body', async () => {
      const result = await login().expect(200); cookie = result.headers['set-cookie'][0].split(';')[0];
      assert.match(result.headers['set-cookie'][0], /HttpOnly/); assert.match(result.headers['set-cookie'][0], /SameSite=Strict/);
      assert.equal(result.body.data.user.role, 'ADMIN'); assert.equal(result.body.data.token, undefined);
      const token = cookie.split('=')[1];
      const stored = (await pool.query('SELECT token_hash FROM admin_sessions')).rows[0];
      assert.equal(stored.token_hash, hashToken(token));
      await request(app).get('/api/admin/session').set('Cookie', cookie).expect(200);
    });
    await t.test('invalid password, unknown admin and passenger credentials have identical errors', async () => {
      const passenger = await request(app).post('/api/auth/register').send({ fullName: 'Test passenger', email: 'passenger@example.test', password }).expect(201);
      const invalid = await login(email, 'incorrect').expect(401);
      const unknown = await login('unknown@example.test').expect(401);
      const passengerLogin = await login('passenger@example.test').expect(401);
      assert.deepEqual(invalid.body, unknown.body); assert.deepEqual(invalid.body, passengerLogin.body);
      await request(app).get('/api/admin/dashboard').set('Authorization', 'Bearer ' + passenger.body.data.token).expect(401);
      await request(app).get('/api/auth/me').set('Authorization', 'Bearer ' + cookie.split('=')[1]).expect(401);
    });
    await t.test('empty database yields zero supported statistics and unavailable device registry', async () => {
      const result = await request(app).get('/api/admin/dashboard').set('Cookie', cookie).expect(200);
      assert.deepEqual(result.body.data.summary, { jeepneys: 0, demoJeepneys: 0, fresh: 0, staleOrMissing: 0, full: 0, available: 0, validUntil: null, routes: 0, devices: null });
      assert.deepEqual(result.body.data.recent, []);
    });
    await t.test('actual SQL counts vehicles, excludes test data, handles stale and missing reports', async () => {
      await pool.query("INSERT INTO registered_routes(origin,destination) VALUES('Boac','Gasan')");
      for (const [id, source, age, status] of [['FRESH-TEST', 'device', 0, 'AVAILABLE'], ['STALE-TEST', 'device', 500, 'FULL'], ['MISSING-TEST', 'device', null, null], ['SIM-TEST', 'simulated', 0, 'FULL'], ['DEMO-TEST', 'demo', 0, 'AVAILABLE']]) {
        await pool.query('INSERT INTO jeepneys(id,name,source) VALUES($1,$2,$3)', [id, 'Test-only vehicle', source]);
        if (age === null) continue;
        const key = source === 'demo' ? null : randomUUID();
        if (key) await pool.query('INSERT INTO device_credentials(id,jeepney_id,source,secret_hash) VALUES($1,$2,$3,$4)', [key, id, source, '0'.repeat(64)]);
        await pool.query(`INSERT INTO location_status_updates(jeepney_id,source,credential_id,latitude,longitude,status,recorded_at)
          VALUES($1,$2,$3,13.4,121.8,$4,now()-$5 * interval '1 second')`, [id, source, key, status, age]);
      }
      const result = (await request(app).get('/api/admin/dashboard').set('Cookie', cookie).expect(200)).body.data;
      const counts = result.summary;
      assert.equal(counts.jeepneys, 3); assert.equal(counts.demoJeepneys, 2); assert.equal(counts.routes, 1);
      assert.equal(counts.fresh, 1); assert.equal(counts.staleOrMissing, 2); assert.equal(counts.available, 1); assert.equal(counts.full, 0);
      assert.ok(Date.parse(counts.validUntil) > Date.parse(result.updatedAt));
      for (const row of result.recent) {
        assert.equal(row.route, null);
        if (row.id !== 'FRESH-TEST') assert.equal(row.status, 'UNKNOWN');
      }
      assert.equal(result.recent.find(r => r.id === 'MISSING-TEST').freshness, 'MISSING');
      assert.equal(result.recent.find(r => r.id === 'STALE-TEST').freshness, 'STALE');
      assert.ok(!JSON.stringify(result).includes('secret_hash'));
      const later = await repo.dashboard(new Date(Date.now() + 180000), 120);
      assert.equal(later.summary.fresh, 0); assert.equal(later.summary.available, 0);
      // Measurement and server receipt are independent; an old receipt cannot count as fresh.
      await pool.query("UPDATE location_status_updates SET received_at=now()-interval '10 minutes' WHERE jeepney_id='FRESH-TEST'");
      assert.equal((await repo.dashboard(new Date(), 120)).summary.fresh, 0);
    });
    await t.test('logout revokes server session, clears cookie and rejects replay', async () => {
      const result = await write('/logout').set('Cookie', cookie).send({}).expect(204);
      assert.match(result.headers['set-cookie'][0], /Expires=Thu, 01 Jan 1970/);
      await request(app).get('/api/admin/dashboard').set('Cookie', cookie).expect(401);
    });
    await t.test('expired sessions and login rotation cannot be reused', async () => {
      const result = await login().expect(200); cookie = result.headers['set-cookie'][0].split(';')[0];
      const rotated = await write('/login').set('Cookie', cookie).send({ email, password }).expect(200);
      await request(app).get('/api/admin/session').set('Cookie', cookie).expect(401);
      cookie = rotated.headers['set-cookie'][0].split(';')[0];
      await pool.query("UPDATE admin_sessions SET created_at=now()-interval '2 hours',expires_at=now()-interval '1 hour'");
      await request(app).get('/api/admin/session').set('Cookie', cookie).expect(401);
    });
    await t.test('production cookies are Secure host-only, with trusted HTTPS forwarding', async () => {
      const production = createApp({ adminRepository: repo, config: { ...config, NODE_ENV: 'production', TRUST_PROXY: 'loopback', ADMIN_WEB_ORIGINS: 'https://admin.example.test' } });
      const result = await request(production).post('/api/admin/login').set('X-Forwarded-Proto', 'https').set('Origin', 'https://admin.example.test')
        .set('X-AbangQue-Admin', '1').send({ email, password }).expect(200);
      assert.match(result.headers['set-cookie'][0], /^__Host-abangque_admin=/);
      assert.match(result.headers['set-cookie'][0], /; Secure/); assert.ok(!result.headers['set-cookie'][0].includes('Domain='));
    });
  } finally {
    await pool?.end();
    if (/^admin_test_[0-9a-f]{24}$/.test(schema)) await control.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await control.end();
  }
});
