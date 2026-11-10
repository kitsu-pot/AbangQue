import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import pg from 'pg';
import request from 'supertest';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { PostgresRepository } from '../src/repository.js';
import { PassengerRepository } from '../src/passenger-repository.js';
import { FavoriteRepository } from '../src/favorite-repository.js';
import { hashToken, passwordOptions } from '../src/passenger-auth.js';

test('real PostgreSQL account management and transactional privacy', { skip: process.env.AUTH_INTEGRATION !== 'true' }, async t => {
  const config = loadConfig({ ...process.env, NODE_ENV: 'test', AUTH_RATE_LIMIT: '100' });
  const schema = 'account_test_' + randomBytes(12).toString('hex');
  const admin = new pg.Pool({ connectionString: config.DATABASE_URL, connectionTimeoutMillis: 5000 });
  let pool;
  try {
    await admin.query(`CREATE SCHEMA "${schema}"`);
    pool = new pg.Pool({ connectionString: config.DATABASE_URL, options: `-c search_path=${schema}`, connectionTimeoutMillis: 5000 });
    for (const file of ['001_initial.sql', '002_passenger_auth.sql', '003_simulated_device_source.sql', '004_favorite_routes.sql'])
      await pool.query(await readFile(new URL('../migrations/' + file, import.meta.url), 'utf8'));
    const passenger = new PassengerRepository(pool);
    const app = createApp({ repository: new PostgresRepository(pool), passengerRepository: passenger, favoriteRepository: new FavoriteRepository(pool), config });
    const initial = randomBytes(24).toString('base64url'), changed = randomBytes(24).toString('base64url');
    const later = randomBytes(24).toString('base64url');
    const register = async email => (await request(app).post('/api/auth/register')
      .send({ fullName: 'Account Test', email, password: initial }).expect(201)).body.data;
    const a = await register('account-a@example.test'), b = await register('account-b@example.test');
    const login = async password => (await request(app).post('/api/auth/login')
      .send({ email: a.user.email, password }).expect(200)).body.data;
    const other = await login(initial);
    const bearer = session => 'Bearer ' + session.token;
    const currentHash = async () => (await pool.query('SELECT password_hash FROM passenger_accounts WHERE id=$1', [a.user.id])).rows[0].password_hash;
    const originalHash = await currentHash();
    const route = randomUUID();
    await pool.query("INSERT INTO registered_routes(id,origin,destination) VALUES($1,'Boac','Gasan')", [route]);
    await pool.query("INSERT INTO jeepneys(id,name,source) VALUES('ACCOUNT-TEST','Test fixture','device')");
    for (const account of [a,b]) await request(app).put('/api/favorites/' + route).set('Authorization', bearer(account)).expect(204);
    const changeBody = { currentPassword: initial, newPassword: changed, confirmPassword: changed };
    await t.test('profile uses session identity, normalizes name and preserves unchanged fields', async () => {
      const updated = await request(app).patch('/api/auth/me').set('Authorization', bearer(a)).send({ fullName: '  Edited Passenger  ' }).expect(200);
      assert.deepEqual(updated.body.data.user, { ...a.user, fullName: 'Edited Passenger' });
      for (const body of [{ fullName: '' }, { fullName: 'x'.repeat(121) }, { fullName: 'A\nB' },
        { fullName: 'X', id: b.user.id }, { fullName: 'X', email: b.user.email }, { fullName: 'X', role: 'ADMIN' }])
        await request(app).patch('/api/auth/me').set('Authorization', bearer(a)).send(body).expect(400);
      await request(app).patch('/api/auth/me').send({ fullName: 'No' }).expect(401);
      const unchanged = (await request(app).get('/api/auth/me').set('Authorization', bearer(b)).expect(200)).body.data.user;
      assert.deepEqual(unchanged, b.user);
    });
    await t.test('incorrect password, policy and confirmation failures cannot change an account', async () => {
      await request(app).post('/api/auth/me/password').set('Authorization', bearer(a)).send({ ...changeBody, currentPassword: 'wrong' }).expect(403);
      await request(app).post('/api/auth/me/password').set('Authorization', bearer(a)).send({ ...changeBody, confirmPassword: 'wrong' }).expect(400);
      await request(app).post('/api/auth/me/password').set('Authorization', bearer(a)).send({ ...changeBody, newPassword: 'short', confirmPassword: 'short' }).expect(400);
      assert.equal(await currentHash(), originalHash);
      await request(app).get('/api/auth/me').set('Authorization', bearer(other)).expect(200);
    });
    await t.test('session revocation failure rolls back the password hash', async () => {
      await pool.query(`CREATE FUNCTION block_session_change() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'test-only revocation failure'; END $$;
        CREATE TRIGGER block_session_change BEFORE UPDATE ON passenger_sessions FOR EACH ROW EXECUTE FUNCTION block_session_change()`);
      await request(app).post('/api/auth/me/password').set('Authorization', bearer(a)).send(changeBody).expect(503);
      assert.equal(await currentHash(), originalHash);
      await request(app).get('/api/auth/me').set('Authorization', bearer(other)).expect(200);
      await pool.query('DROP TRIGGER block_session_change ON passenger_sessions; DROP FUNCTION block_session_change()');
    });
    let afterChange;
    await t.test('password change revokes other sessions atomically and rejects login with the old password', async () => {
      await request(app).post('/api/auth/me/password').set('Authorization', bearer(a)).send(changeBody).expect(204);
      assert.ok(await argon2.verify(await currentHash(), changed));
      await request(app).get('/api/auth/me').set('Authorization', bearer(other)).expect(401);
      await request(app).get('/api/favorites').set('Authorization', bearer(other)).expect(401);
      await request(app).get('/api/auth/me').set('Authorization', bearer(b)).expect(200);
      const current = (await request(app).get('/api/auth/me').set('Authorization', bearer(a)).expect(200)).body.data;
      assert.equal(current.expiresAt, a.expiresAt);
      await request(app).post('/api/auth/login').send({ email: a.user.email, password: initial }).expect(401);
      afterChange = await login(changed);
      // A login that verified an old hash before the change must not mint a token.
      assert.equal(await passenger.login(a.user.id, hashToken('test-only-raced-token'), 3600, originalHash), null);
    });
    await t.test('concurrent password changes recheck revocation after acquiring the account lock', async () => {
      const entered = Promise.withResolvers(), release = Promise.withResolvers();
      const changing = passenger.changePassword(hashToken(a.token), async hash => {
        assert.ok(await argon2.verify(hash, changed)); entered.resolve(); await release.promise;
        return argon2.hash(later, passwordOptions);
      });
      await entered.promise;
      const competing = passenger.changePassword(hashToken(afterChange.token), async () => { throw new Error('Revoked verifier must not run'); });
      const resultsPromise = Promise.allSettled([changing, competing]);
      release.resolve();
      const results = await resultsPromise;
      assert.equal(results[0].status, 'fulfilled');
      assert.equal(results[1].status, 'rejected');
      assert.equal(results[1].reason.accountError, 'SESSION_INVALID');
      assert.ok(await argon2.verify(await currentHash(), later));
    });
    await t.test('unauthenticated, cross-account and wrong-password deletion fail safely', async () => {
      await request(app).delete('/api/auth/me').send({ currentPassword: later }).expect(401);
      await request(app).delete('/api/auth/me').set('Authorization', bearer(a)).send({ currentPassword: later, id: b.user.id }).expect(400);
      await request(app).delete('/api/auth/me').set('Authorization', bearer(a)).send({ currentPassword: 'wrong' }).expect(403);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM passenger_accounts')).rows[0].n, 2);
    });
    await t.test('deletion rollback preserves account, sessions and favorites when a cascade fails', async () => {
      await pool.query(`CREATE FUNCTION block_favorite_delete() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'test-only delete failure'; END $$;
        CREATE TRIGGER block_favorite_delete BEFORE DELETE ON passenger_favorite_routes FOR EACH ROW EXECUTE FUNCTION block_favorite_delete()`);
      await request(app).delete('/api/auth/me').set('Authorization', bearer(a)).send({ currentPassword: later }).expect(503);
      await request(app).get('/api/auth/me').set('Authorization', bearer(a)).expect(200);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM passenger_favorite_routes WHERE passenger_id=$1', [a.user.id])).rows[0].n, 1);
      await pool.query('DROP TRIGGER block_favorite_delete ON passenger_favorite_routes; DROP FUNCTION block_favorite_delete()');
    });
    await t.test('repeated concurrent deletion removes only the authenticated account and its owned records', async () => {
      const results = await Promise.all([1,2].map(() => request(app).delete('/api/auth/me').set('Authorization', bearer(a)).send({ currentPassword: later })));
      assert.deepEqual(results.map(r => r.status).sort(), [204,401]);
      for (const table of ['passenger_sessions', 'passenger_favorite_routes']) {
        assert.equal((await pool.query(`SELECT count(*)::int AS n FROM ${table} WHERE passenger_id=$1`, [a.user.id])).rows[0].n, 0);
      }
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM passenger_accounts WHERE id=$1', [a.user.id])).rows[0].n, 0);
      await request(app).get('/api/auth/me').set('Authorization', bearer(a)).expect(401);
      await request(app).post('/api/auth/login').send({ email: a.user.email, password: later }).expect(401);
      const remaining = (await request(app).get('/api/favorites').set('Authorization', bearer(b)).expect(200)).body.data;
      assert.equal(remaining.length, 1);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM registered_routes')).rows[0].n, 1);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM jeepneys')).rows[0].n, 1);
      await request(app).get('/api/routes').expect(200);
      await request(app).get('/api/jeepneys').expect(200);
      await request(app).post('/api/auth/logout').set('Authorization', bearer(a)).expect(204);
    });
  } finally {
    if (pool) await pool.end();
    if (/^account_test_[0-9a-f]{24}$/.test(schema)) await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await admin.end();
  }
});
