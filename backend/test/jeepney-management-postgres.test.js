import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { randomBytes, randomUUID } from 'node:crypto';
import * as argon2 from 'argon2';
import pg from 'pg';
import request from 'supertest';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { AdminRepository } from '../src/admin-repository.js';
import { AdminJeepneyRepository } from '../src/admin-jeepney-repository.js';
import { PostgresRepository } from '../src/repository.js';
import { PassengerRepository } from '../src/passenger-repository.js';
import { FavoriteRepository } from '../src/favorite-repository.js';
import { passwordOptions } from '../src/passenger-auth.js';
import { issueCredential } from '../src/security.js';

test('real PostgreSQL jeepney management and passenger/device compatibility', { skip: process.env.AUTH_INTEGRATION !== 'true' }, async t => {
  const config = loadConfig({ ...process.env, NODE_ENV: 'test', ENABLE_GPS_SIMULATOR: 'false', ADMIN_AUTH_RATE_LIMIT: '100' });
  const schema = 'jeepneys_test_' + randomBytes(12).toString('hex');
  const control = new pg.Pool({ connectionString: config.DATABASE_URL, connectionTimeoutMillis: 5000 });
  let pool;
  try {
    await control.query(`CREATE SCHEMA "${schema}"`);
    pool = new pg.Pool({ connectionString: config.DATABASE_URL, options: `-c search_path=${schema}`, connectionTimeoutMillis: 5000 });
    const dir = new URL('../migrations/', import.meta.url);
    for (const name of (await readdir(dir)).filter(n => n.endsWith('.sql') && n < '006').sort()) await pool.query(await readFile(new URL(name, dir), 'utf8'));
    // Test-only data created before migration 006; never inserted in the public schema.
    await pool.query("INSERT INTO jeepneys(id,name,source) VALUES('EXISTING','Existing test vehicle','device'),('DEMO-TEST','DEMO test fixture','demo'),('SIM-GPS-001','SIMULATED test fixture','simulated')");
    const historical = issueCredential();
    await pool.query("INSERT INTO device_credentials(id,jeepney_id,source,secret_hash) VALUES($1,'EXISTING','device',$2)", [historical.id, historical.secretHash]);
    await pool.query("INSERT INTO location_status_updates(jeepney_id,source,credential_id,latitude,longitude,status,recorded_at) VALUES('EXISTING','device',$1,13.4,121.8,'AVAILABLE',now()-interval '10 minutes')", [historical.id]);
    const historyBefore = (await pool.query('SELECT * FROM location_status_updates')).rows;
    await pool.query(await readFile(new URL('006_jeepney_management.sql', dir), 'utf8'));
    const admin = new AdminRepository(pool), vehicles = new AdminJeepneyRepository(pool);
    const app = createApp({ config, adminRepository: admin, adminJeepneyRepository: vehicles, repository: new PostgresRepository(pool), passengerRepository: new PassengerRepository(pool), favoriteRepository: new FavoriteRepository(pool) });
    const password = randomBytes(24).toString('base64url');
    await admin.provisionFirst('admin@example.test', await argon2.hash(password, passwordOptions));
    const origin = config.ADMIN_WEB_ORIGINS.split(',')[0];
    const result = await request(app).post('/api/admin/login').set('Origin', origin).set('X-AbangQue-Admin', '1').send({ email: 'admin@example.test', password }).expect(200);
    const cookie = result.headers['set-cookie'][0].split(';')[0];
    const get = path => request(app).get('/api/admin' + path).set('Cookie', cookie);
    const write = (method, path) => request(app)[method]('/api/admin' + path).set('Cookie', cookie).set('Origin', origin).set('X-AbangQue-Admin', '1');
    const detail = async id => (await get('/jeepneys/' + id).expect(200)).body.data.record;
    const create = { id: 'REGISTERED-01', name: 'Test registration', plateNumber: 'AB 1234', description: 'Test-only description', administrativeNotes: 'Private test note', active: true, routeId: null };
    const edit = row => ({ name: row.name, plateNumber: row.plateNumber, description: row.description, administrativeNotes: row.administrativeNotes, routeId: row.route?.id ?? null, expectedVersion: row.version });
    const forward = randomUUID(), reverse = randomUUID(), inactive = randomUUID();
    await t.test('migration preserves pre-existing identities, history and source; seeds no routes', async () => {
      assert.deepEqual((await pool.query('SELECT * FROM location_status_updates')).rows, historyBefore);
      assert.equal((await detail('EXISTING')).active, true);
      assert.equal((await detail('EXISTING')).status, 'UNKNOWN');
      assert.equal((await detail('SIM-GPS-001')).source, 'simulated');
      assert.equal((await get('/route-options').expect(200)).body.data.length, 0);
    });
    await t.test('registers real record without GPS/device credentials and rejects duplicates', async () => {
      const created = (await write('post', '/jeepneys').send(create).expect(201)).body.data;
      assert.equal(created.source, 'device'); assert.equal(created.position, null); assert.equal(created.status, 'UNKNOWN'); assert.equal(created.timestamp, null);
      assert.equal(created.freshness, 'MISSING'); assert.equal(created.route, null);
      await write('post', '/jeepneys').send(create).expect(409);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM device_credentials')).rows[0].n, 1);
      assert.equal((await pool.query('SELECT count(*)::int AS n FROM location_status_updates')).rows[0].n, 1);
      for (const patch of [{ source: 'demo' }, { status: 'FULL' }, { latitude: 0 }, { plateNumber: '!!' }, { role: 'ADMIN' }])
        await write('post', '/jeepneys').send({ ...create, id: 'INVALID', ...patch }).expect(400);
    });
    await t.test('assigns only existing active directional routes; retains inactive assignment on unrelated edits', async () => {
      await pool.query("INSERT INTO registered_routes(id,origin,destination,active) VALUES($1,'Boac','Gasan',true),($2,'Gasan','Boac',true),($3,'Boac','Mogpog',false)", [forward, reverse, inactive]);
      const choices = (await get('/route-options').expect(200)).body.data;
      assert.equal(choices.length, 3); assert.equal(choices.find(r => r.id === inactive).active, false);
      let row = await detail(create.id);
      for (const routeId of [inactive, randomUUID()]) await write('put', '/jeepneys/' + row.id).send({ ...edit(row), routeId }).expect(409);
      await write('put', '/jeepneys/' + row.id).send({ ...edit(row), routeId: forward, name: 'Edited vehicle' }).expect(200);
      let catalog = (await request(app).get('/api/routes').expect(200)).body.data;
      assert.deepEqual(catalog.assignments, [{ routeId: forward, jeepneyId: row.id }]);
      row = await detail(row.id);
      await write('put', '/jeepneys/' + row.id).send({ ...edit(row), routeId: reverse }).expect(200);
      catalog = (await request(app).get('/api/routes').expect(200)).body.data;
      assert.deepEqual(catalog.assignments, [{ routeId: reverse, jeepneyId: row.id }]);
      await pool.query('UPDATE registered_routes SET active=false WHERE id=$1', [reverse]);
      row = await detail(row.id);
      await write('put', '/jeepneys/' + row.id).send({ ...edit(row), description: 'Retained inactive direction' }).expect(200);
      assert.equal((await detail(row.id)).route.active, false);
      assert.deepEqual((await request(app).get('/api/routes').expect(200)).body.data.assignments, []);
      row = await detail(row.id);
      await write('put', '/jeepneys/' + row.id).send({ ...edit(row), routeId: forward }).expect(200);
    });
    await t.test('concurrent editors and repeated saves cannot overwrite the winning change', async () => {
      const row = await detail(create.id), value = { ...edit(row), description: 'One confirmed edit' };
      const results = await Promise.all([1, 2].map(() => write('put', '/jeepneys/' + row.id).send(value)));
      assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
      const next = await detail(row.id); assert.equal(next.version, row.version + 1); assert.equal(next.description, value.description);
      await write('put', '/jeepneys/' + row.id).send({ ...edit(next), id: 'RENAMED' }).expect(400);
      await write('put', '/jeepneys/' + row.id).send({ ...edit(next), active: false }).expect(400);
      await write('put', '/jeepneys/MISSING').send(edit(next)).expect(404);
    });
    await t.test('device ingestion remains authenticated; inactive records/history preserved and hidden from passengers', async () => {
      const key = issueCredential();
      await pool.query("INSERT INTO device_credentials(id,jeepney_id,source,secret_hash) VALUES($1,$2,'device',$3)", [key.id, create.id, key.secretHash]);
      const update = { jeepneyId: create.id, latitude: 13.41, longitude: 121.81, status: 'FULL', timestamp: new Date(Date.now() - 2000).toISOString() };
      await request(app).post('/api/device-updates').set('Authorization', 'Bearer ' + key.token).send(update).expect(201);
      let row = await detail(create.id); assert.equal(row.status, 'FULL'); assert.equal(row.freshness, 'FRESH');
      const before = (await pool.query('SELECT * FROM location_status_updates ORDER BY id')).rows;
      assert.equal((await get('/dashboard').expect(200)).body.data.summary.full, 1);
      await write('post', '/jeepneys/' + row.id + '/activation').send({ active: false, expectedVersion: row.version }).expect(200);
      assert.deepEqual((await pool.query('SELECT * FROM location_status_updates ORDER BY id')).rows, before);
      assert.equal((await detail(row.id)).lastReportedStatus, 'FULL'); assert.equal((await detail(row.id)).status, 'UNKNOWN');
      await request(app).get('/api/jeepneys/' + row.id).expect(404);
      assert.ok(!(await request(app).get('/api/jeepneys').expect(200)).body.data.some(j => j.id === row.id));
      assert.deepEqual((await request(app).get('/api/routes').expect(200)).body.data.assignments, []);
      assert.equal((await get('/dashboard').expect(200)).body.data.summary.full, 0);
      assert.equal((await get('/dashboard').expect(200)).body.data.summary.jeepneys, 2);
      await request(app).post('/api/device-updates').set('Authorization', 'Bearer ' + key.token).send({ ...update, timestamp: new Date(Date.now() - 1000).toISOString() }).expect(201);
      await request(app).post('/api/device-updates').set('Authorization', 'Bearer ' + key.token).send(update).expect(409);
      await request(app).post('/api/device-updates').send(update).expect(401);
      await pool.query("UPDATE location_status_updates SET recorded_at=recorded_at-interval '10 minutes' WHERE jeepney_id=$1", [row.id]);
      row = await detail(row.id);
      await write('post', '/jeepneys/' + row.id + '/activation').send({ active: true, expectedVersion: row.version }).expect(200);
      const passenger = (await request(app).get('/api/jeepneys/' + row.id).expect(200)).body.data;
      assert.equal(passenger.status, null); assert.equal(passenger.isStale, true); assert.equal(passenger.eta, null);
      assert.deepEqual((await request(app).get('/api/routes').expect(200)).body.data.assignments, [{ routeId: forward, jeepneyId: row.id }]);
      assert.ok(!JSON.stringify(passenger).includes('administrativeNotes'));
      assert.ok(!JSON.stringify(await detail(row.id)).includes(key.secretHash));
      const existingHistory = (await pool.query("SELECT * FROM location_status_updates WHERE jeepney_id='EXISTING'")).rows;
      assert.deepEqual(existingHistory, historyBefore);
    });
    await t.test('unassignment removes route association; test provenance is read-only', async () => {
      const row = await detail(create.id);
      await write('put', '/jeepneys/' + row.id).send({ ...edit(row), routeId: null }).expect(200);
      assert.deepEqual((await request(app).get('/api/routes').expect(200)).body.data.assignments, []);
      for (const id of ['DEMO-TEST', 'SIM-GPS-001']) {
        const demo = await detail(id);
        await write('put', '/jeepneys/' + id).send(edit(demo)).expect(409);
        await write('post', '/jeepneys/' + id + '/activation').send({ active: false, expectedVersion: demo.version }).expect(409);
      }
      assert.equal((await detail('SIM-GPS-001')).source, 'simulated');
    });
    await t.test('search, status, route filters, stable pagination and no duplicate plate policy', async () => {
      await write('post', '/jeepneys').send({ ...create, id: 'SECOND-01', active: false, routeId: forward }).expect(201);
      let page = (await get('/jeepneys?search=AB%201234').expect(200)).body.data;
      assert.equal(page.total, 2); // A plate is optional metadata, not an invented uniqueness rule.
      page = (await get('/jeepneys?status=inactive').expect(200)).body.data; assert.equal(page.total, 1);
      page = (await get('/jeepneys?routeId=' + forward).expect(200)).body.data; assert.equal(page.items[0].id, 'SECOND-01');
      const first = (await get('/jeepneys?pageSize=2&page=1').expect(200)).body.data;
      const second = (await get('/jeepneys?pageSize=2&page=2').expect(200)).body.data;
      assert.equal(first.total, 5); assert.equal(first.registeredTotal, 3); assert.equal(first.items.length, 2);
      assert.ok(!first.items.some(a => second.items.some(b => a.id === b.id)));
      assert.equal((await get('/jeepneys?search=%25').expect(200)).body.data.total, 0);
      assert.equal((await get('/jeepneys?search=missing').expect(200)).body.data.items.length, 0);
      assert.ok((await get('/jeepneys?routeId=unassigned').expect(200)).body.data.items.every(j => j.route === null));
    });
    await t.test('real passenger login cannot use administrator read/write endpoints', async () => {
      const passenger = (await request(app).post('/api/auth/register').send({ email: 'passenger@example.test', fullName: 'Test Passenger', password }).expect(201)).body.data;
      for (const [method, path] of [['post', '/jeepneys'], ['put', '/jeepneys/' + create.id], ['post', '/jeepneys/' + create.id + '/activation']]) {
        await request(app)[method]('/api/admin' + path).set('Origin', origin).set('X-AbangQue-Admin', '1').set('Authorization', 'Bearer ' + passenger.token).send(create).expect(401);
      }
      await request(app).get('/api/admin/jeepneys').set('Authorization', 'Bearer ' + passenger.token).expect(401);
      const after = await detail(create.id); assert.equal(after.active, true);
    });
  } finally {
    await pool?.end();
    if (/^jeepneys_test_[0-9a-f]{24}$/.test(schema)) await control.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
    await control.end();
  }
});
