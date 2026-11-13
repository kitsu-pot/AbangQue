import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyTestMigrations } from '../test-support/migrations.js';
import { randomBytes, randomUUID } from 'node:crypto';
import pg from 'pg';
import request from 'supertest';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { PostgresRepository } from '../src/repository.js';
import { PassengerRepository } from '../src/passenger-repository.js';
import { FavoriteRepository } from '../src/favorite-repository.js';
import { hashToken } from '../src/passenger-auth.js';

test('real PostgreSQL favorite routes', { skip: process.env.AUTH_INTEGRATION !== 'true' }, async t => {
  const config = loadConfig({ ...process.env, NODE_ENV: 'test', AUTH_RATE_LIMIT: '100' });
  const schema = 'favorites_test_' + randomBytes(12).toString('hex');
  const admin = new pg.Pool({ connectionString: config.DATABASE_URL, connectionTimeoutMillis: 5000 });
  let pool;
  try {
    await admin.query(`CREATE SCHEMA "${schema}"`);
    pool = new pg.Pool({ connectionString: config.DATABASE_URL, options: `-c search_path=${schema}`, connectionTimeoutMillis: 5000 });
    await applyTestMigrations(pool);
    const makeApp = () => createApp({ repository: new PostgresRepository(pool), passengerRepository: new PassengerRepository(pool), favoriteRepository: new FavoriteRepository(pool), config });
    let app = makeApp();
    const password = randomBytes(24).toString('base64url');
    const account = email => ({ fullName: 'Favorite Test Passenger', email, password });
    const a = (await request(app).post('/api/auth/register').send(account('a@example.test')).expect(201)).body.data;
    const b = (await request(app).post('/api/auth/register').send(account('b@example.test')).expect(201)).body.data;
    const header = session => 'Bearer ' + session.token;
    const forward = randomUUID(), reverse = randomUUID();
    await t.test('migration seeds no operating routes', async () => {
      const result = (await request(app).get('/api/routes').expect(200)).body;
      assert.deepEqual(result.data.routes, []);
      assert.equal(result.meta.officialRoutesAvailable, false);
    });
    // Fixtures exist ONLY in the generated test schema; never registered as real operating routes.
    await pool.query("INSERT INTO registered_routes(id,origin,destination) VALUES($1,'Boac','Gasan'),($2,'Gasan','Boac')", [forward, reverse]);
    await t.test('public catalog returns stable directional IDs without assigning any jeepneys', async () => {
      const { data } = (await request(app).get('/api/routes').expect(200)).body;
      assert.equal(data.routes.length, 2);
      assert.deepEqual(data.assignments, []);
      assert.ok(data.routes.every(r => r.isDemo === false));
      await request(app).get('/api/jeepneys').expect(200);
      await request(app).get('/api/favorites').expect(401);
      await request(app).put('/api/favorites/' + forward).expect(401);
    });
    await t.test('saves direction separately and concurrent duplicate saves are idempotent', async () => {
      const responses = await Promise.all([1, 2, 3].map(() => request(app).put('/api/favorites/' + forward).set('Authorization', header(a))));
      assert.ok(responses.every(r => r.status === 204));
      await request(app).put('/api/favorites/' + reverse).set('Authorization', header(a)).expect(204);
      const rows = (await request(app).get('/api/favorites').set('Authorization', header(a)).expect(200)).body.data;
      assert.equal(rows.length, 2);
      assert.deepEqual(new Set(rows.map(r => r.routeId)), new Set([forward, reverse]));
      assert.ok(rows.every(r => r.available));
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM passenger_favorite_routes')).rows[0].n, 2);
    });
    await t.test('another passenger cannot read or remove the owner favorites', async () => {
      assert.deepEqual((await request(app).get('/api/favorites').set('Authorization', header(b)).expect(200)).body.data, []);
      await request(app).get('/api/favorites?passengerId=' + a.user.id).set('Authorization', header(b)).expect(400);
      await request(app).put('/api/favorites/' + forward).set('Authorization', header(b)).send({ passengerId: a.user.id }).expect(400);
      await request(app).delete('/api/favorites/' + forward).set('Authorization', header(b)).expect(204);
      assert.equal((await request(app).get('/api/favorites').set('Authorization', header(a))).body.data.length, 2);
    });
    await t.test('favorites survive server recreation, session recovery and login from a second device', async () => {
      app = makeApp();
      await request(app).get('/api/auth/me').set('Authorization', header(a)).expect(200);
      const another = (await request(app).post('/api/auth/login').send({ email: 'a@example.test', password }).expect(200)).body.data;
      assert.notEqual(another.token, a.token);
      assert.equal((await request(app).get('/api/favorites').set('Authorization', header(another)).expect(200)).body.data.length, 2);
      await request(app).post('/api/auth/logout').set('Authorization', header(another)).expect(204);
      await request(app).get('/api/favorites').set('Authorization', header(another)).expect(401);
      await request(app).delete('/api/favorites/' + forward).set('Authorization', header(another)).expect(401);
    });
    await t.test('inactive and deleted directions remain unavailable favorites and cannot be saved', async () => {
      await pool.query('UPDATE registered_routes SET active=false WHERE id=$1', [forward]);
      await pool.query('DELETE FROM registered_routes WHERE id=$1', [reverse]);
      const rows = (await request(app).get('/api/favorites').set('Authorization', header(a)).expect(200)).body.data;
      assert.equal(rows.length, 2);
      assert.ok(rows.every(r => r.available === false));
      assert.equal(rows.find(r => r.routeId === reverse).origin, 'Gasan');
      for (const id of [forward, reverse, randomUUID()])
        await request(app).put('/api/favorites/' + id).set('Authorization', header(a)).expect(409);
      assert.deepEqual((await request(app).get('/api/routes').expect(200)).body.data.routes, []);
    });
    await t.test('removal persists, is idempotent and leaves the other direction alone', async () => {
      for (let i = 0; i < 2; i++) await request(app).delete('/api/favorites/' + forward).set('Authorization', header(a)).expect(204);
      assert.deepEqual((await request(app).get('/api/favorites').set('Authorization', header(a))).body.data.map(r => r.routeId), [reverse]);
      await request(app).delete('/api/favorites/' + reverse).set('Authorization', header(a)).expect(204);
      assert.deepEqual((await request(app).get('/api/favorites').set('Authorization', header(a))).body.data, []);
    });
    await t.test('expired sessions cannot manage favorites; passenger deletion cascades', async () => {
      await pool.query("UPDATE passenger_sessions SET created_at=now()-interval '2 days', expires_at=now()-interval '1 day' WHERE token_hash=$1", [hashToken(a.token)]);
      await request(app).get('/api/favorites').set('Authorization', header(a)).expect(401);
      await request(app).put('/api/favorites/' + forward).set('Authorization', header(a)).expect(401);
      await pool.query('UPDATE registered_routes SET active=true WHERE id=$1', [forward]);
      await request(app).put('/api/favorites/' + forward).set('Authorization', header(b)).expect(204);
      await pool.query('DELETE FROM passenger_accounts WHERE id=$1', [b.user.id]);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM passenger_favorite_routes')).rows[0].n, 0);
    });
  } finally {
    if (pool) await pool.end();
    if (/^favorites_test_[0-9a-f]{24}$/.test(schema)) await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await admin.end();
  }
});
