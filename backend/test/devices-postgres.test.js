import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import * as argon2 from 'argon2';
import pg from 'pg';
import request from 'supertest';
import { AdminDeviceRepository } from '../src/admin-device-repository.js';
import { AdminRepository } from '../src/admin-repository.js';
import { PostgresRepository } from '../src/repository.js';
import { PassengerRepository } from '../src/passenger-repository.js';
import { FavoriteRepository } from '../src/favorite-repository.js';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { hashToken } from '../src/passenger-auth.js';
import { issueCredential } from '../src/security.js';
test(
  'PostgreSQL device lifecycle, credentials, access races and history',
  { skip: process.env.AUTH_INTEGRATION !== 'true' },
  async (t) => {
    const config = loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        ENABLE_GPS_SIMULATOR: 'false',
      }),
      schema = 'devices_test_' + randomBytes(12).toString('hex');
    const control = new pg.Pool({ connectionString: config.DATABASE_URL });
    let pool;
    try {
      await control.query(`CREATE SCHEMA "${schema}"`);
      pool = new pg.Pool({
        connectionString: config.DATABASE_URL,
        options: `-c search_path=${schema}`,
      });
      const directory = new URL('../migrations/', import.meta.url);
      for (const file of (await readdir(directory))
        .filter((n) => n.endsWith('.sql') && n < '008')
        .sort())
        await pool.query(await readFile(new URL(file, directory), 'utf8'));
      await pool.query(
        "INSERT INTO jeepneys(id,name,source,active) VALUES('LEGACY-JEEP','Legacy fixture','device',true),('SIM-GPS-001','SIMULATED fixture','simulated',true),('TARGET-A','DEMO fixture A','device',true),('TARGET-B','DEMO fixture B','device',true),('INACTIVE','Inactive fixture','device',false)",
      );
      const legacy = issueCredential(),
        sim = issueCredential();
      for (const [key, id, source] of [
        [legacy, 'LEGACY-JEEP', 'device'],
        [sim, 'SIM-GPS-001', 'simulated'],
      ])
        await pool.query(
          'INSERT INTO device_credentials(id,jeepney_id,source,secret_hash) VALUES($1,$2,$3,$4)',
          [key.id, id, source, key.secretHash],
        );
      await pool.query(
        "INSERT INTO location_status_updates(jeepney_id,source,credential_id,latitude,longitude,status,recorded_at) VALUES('LEGACY-JEEP','device',$1,13,121,'FULL',now()-interval '10 minutes')",
        [legacy.id],
      );
      const history = (
        await pool.query('SELECT * FROM location_status_updates')
      ).rows;
      await pool.query(
        await readFile(new URL('008_device_management.sql', directory), 'utf8'),
      );
      const admin = new AdminRepository(pool),
        devices = new AdminDeviceRepository(pool),
        repository = new PostgresRepository(pool);
      await admin.provisionFirst(
        'devices@example.test',
        await argon2.hash(randomBytes(24).toString('base64url')),
      );
      const user = await admin.findByEmail('devices@example.test');
      const token = 'aqa_' + randomBytes(32).toString('base64url');
      await admin.login(user, hashToken(token), 600);
      const appOptions = {
        config,
        adminRepository: admin,
        adminDeviceRepository: devices,
        repository,
        passengerRepository: new PassengerRepository(pool),
        favoriteRepository: new FavoriteRepository(pool),
      };
      let app = createApp(appOptions);
      t.beforeEach(() => {
        app = createApp(appOptions);
      });
      const get = (path) =>
        request(app)
          .get('/api/admin' + path)
          .set('Cookie', 'abangque_admin=' + token);
      const write = (method, path, v) =>
        request(app)
          [method]('/api/admin' + path)
          .set('Cookie', 'abangque_admin=' + token)
          .set('Origin', config.ADMIN_WEB_ORIGINS)
          .set('X-AbangQue-Admin', '1')
          .send(v);
      const detail = async (id = 'ESP-TEST') =>
        (await get('/devices/' + id).expect(200)).body.data.record;
      const metadata = {
        label: 'DEMO device fixture',
        model: null,
        description: null,
        administrativeNotes: null,
      };
      const op = async (action, extra = {}) => {
        const row = await detail();
        return {
          expect: (status) =>
            write('post', '/devices/ESP-TEST/' + action, {
              expectedVersion: row.version,
              ...extra,
            }).expect(status),
        };
      };
      let key;
      const update = (bearer, jeepneyId = 'TARGET-A', age = 0) =>
        request(app)
          .post('/api/device-updates')
          .set('Authorization', 'Bearer ' + bearer)
          .send({
            jeepneyId,
            latitude: 13.4,
            longitude: 121.8,
            status: 'AVAILABLE',
            timestamp: new Date(Date.now() - age).toISOString(),
          });
      await t.test(
        'migration preserves credentials and history; simulator remains read-only',
        async () => {
          assert.deepEqual(
            (await pool.query('SELECT * FROM location_status_updates')).rows,
            history,
          );
          assert.equal(
            (
              await pool.query(
                'SELECT secret_hash FROM device_credentials WHERE id=$1',
                [legacy.id],
              )
            ).rows[0].secret_hash,
            legacy.secretHash,
          );
          assert.equal((await detail('LEGACY-LEGACY-JEEP')).legacy, true);
          assert.equal(
            (await detail('LEGACY-SIM-GPS-001')).source,
            'simulated',
          );
          await write('post', '/devices/LEGACY-SIM-GPS-001/revoke', {
            expectedVersion: 1,
          }).expect(409);
          await update(sim.token, 'SIM-GPS-001').expect(403);
          await update(legacy.token, 'LEGACY-JEEP').expect(201);
        },
      );
      await t.test(
        'registration is unique, optional assignment has no reports or automatic keys',
        async () => {
          const input = {
            id: 'ESP-TEST',
            ...metadata,
            enabled: true,
            jeepneyId: null,
          };
          await write('post', '/devices', input).expect(201);
          await write('post', '/devices', input).expect(409);
          const row = await detail();
          assert.equal(row.freshness, 'MISSING');
          assert.equal(row.credentialState, 'Not provisioned');
          assert.equal(row.status, 'UNKNOWN');
          assert.equal(row.timestamp, null);
          await (await op('provision')).expect(409);
          await write('post', '/devices', {
            ...input,
            id: 'INVALID',
            jeepneyId: 'INACTIVE',
          }).expect(409);
          await write('post', '/devices', {
            ...input,
            id: 'INVALID',
            source: 'simulated',
          }).expect(400);
        },
      );
      await t.test(
        'assignment and enable conflicts are enforced; metadata edits conflict safely',
        async () => {
          await (await op('assignment', { jeepneyId: 'TARGET-A' })).expect(200);
          await write('post', '/devices', {
            id: 'CONFLICT',
            ...metadata,
            enabled: true,
            jeepneyId: 'TARGET-A',
          }).expect(409);
          await write('post', '/devices', {
            id: 'DISABLED',
            ...metadata,
            enabled: false,
            jeepneyId: 'TARGET-A',
          }).expect(201);
          await write('post', '/devices/DISABLED/state', {
            expectedVersion: 1,
            enabled: true,
          }).expect(409);
          const row = await detail();
          const body = {
            ...metadata,
            description: 'Edited',
            expectedVersion: row.version,
          };
          const results = await Promise.all([
            write('put', '/devices/ESP-TEST', body),
            write('put', '/devices/ESP-TEST', body),
          ]);
          assert.deepEqual(results.map((r) => r.status).sort(), [200, 409]);
        },
      );
      await t.test(
        'provisioned key authenticates existing protocol and never appears in reads/audit',
        async () => {
          const result = await (await op('provision')).expect(200);
          key = result.body.data.token;
          assert.ok(key);
          await update(key).expect(201);
          const row = await detail();
          assert.equal(row.freshness, 'FRESH');
          assert.equal(row.status, 'AVAILABLE');
          assert.equal(row.reportJeepneyId, 'TARGET-A');
          for (const path of ['/devices', '/devices/ESP-TEST']) {
            const result = await get(path).expect(200);
            const text = JSON.stringify(result.body);
            assert.ok(!text.includes(key));
            assert.ok(!text.includes('secret_hash'));
          }
          assert.ok(
            !JSON.stringify(
              (await pool.query('SELECT * FROM admin_device_events')).rows,
            ).includes(key),
          );
          await (await op('provision')).expect(409);
        },
      );
      await t.test(
        'disable rejects updates including previously authenticated requests; enabling preserves keys',
        async () => {
          const before = await repository.credential(key.split('.')[0]);
          await (await op('state', { enabled: false })).expect(200);
          await update(key).expect(401);
          const result = await repository.insertUpdate(before, {
            jeepneyId: 'TARGET-A',
            latitude: 13,
            longitude: 121,
            status: 'FULL',
            timestamp: new Date().toISOString(),
          });
          assert.equal(result.revoked, true);
          await (await op('state', { enabled: true })).expect(200);
          await update(key).expect(201);
        },
      );
      await t.test(
        'failed rotation rolls back revocation; successful rotation invalidates old keys',
        async () => {
          const invalid = new AdminDeviceRepository(pool, {
            issue: () => ({ ...issueCredential(), secretHash: 'invalid' }),
          });
          await assert.rejects(
            invalid.change(
              'ESP-TEST',
              { expectedVersion: (await detail()).version },
              user.id,
              'ROTATE',
            ),
          );
          await update(key).expect(201);
          const result = await (await op('rotate')).expect(200),
            old = key;
          key = result.body.data.token;
          await update(old).expect(401);
          await update(key).expect(201);
        },
      );
      await t.test(
        'reassignment revokes keys, keeps reports on original vehicle, and creates no replacement position',
        async () => {
          const historyBefore = (
            await pool.query(
              "SELECT * FROM location_status_updates WHERE jeepney_id='TARGET-A' ORDER BY id",
            )
          ).rows;
          await (await op('assignment', { jeepneyId: 'TARGET-B' })).expect(200);
          await update(key).expect(401);
          assert.deepEqual(
            (
              await pool.query(
                "SELECT * FROM location_status_updates WHERE jeepney_id='TARGET-A' ORDER BY id",
              )
            ).rows,
            historyBefore,
          );
          assert.equal((await detail()).reportJeepneyId, 'TARGET-A');
          assert.equal((await detail()).status, 'UNKNOWN');
          assert.equal(
            (await request(app).get('/api/jeepneys/TARGET-B').expect(200)).body
              .data.position,
            null,
          );
          key = (await (await op('provision')).expect(200)).body.data.token;
          await update(key, 'TARGET-A').expect(403);
          await update(key, 'TARGET-B').expect(201);
          await pool.query(
            "UPDATE location_status_updates SET recorded_at=recorded_at-interval '10 minutes' WHERE credential_id IN (SELECT id FROM device_credentials WHERE device_id='ESP-TEST')",
          );
          assert.equal((await detail()).freshness, 'STALE');
          assert.equal((await detail()).status, 'UNKNOWN');
        },
      );
      await t.test(
        'revocation/unassignment preserve data, counters and filtered pagination; real passenger denied',
        async () => {
          // Repository checks also verify revocation and unassignment preserve references.
          const row = await detail();
          await devices.change(
            row.id,
            { expectedVersion: row.version },
            user.id,
            'REVOKE',
          );
          await update(key, 'TARGET-B').expect(401);
          const next = await detail();
          await devices.change(
            next.id,
            { expectedVersion: next.version, jeepneyId: null },
            user.id,
            'ASSIGN',
          );
          assert.equal((await detail()).jeepneyId, null);
          const page = (
            await get('/devices?assignment=unassigned&pageSize=1').expect(200)
          ).body.data;
          assert.equal(page.items.length, 1);
          assert.equal(page.items[0].id, 'ESP-TEST');
          assert.equal(
            (await get('/devices?search=missing').expect(200)).body.data.total,
            0,
          );
          assert.equal(
            (await get('/devices?state=disabled').expect(200)).body.data.total,
            1,
          );
          assert.equal(
            (await get('/dashboard').expect(200)).body.data.summary.devices,
            3,
          );
          const passenger = (
            await request(app)
              .post('/api/auth/register')
              .send({
                fullName: 'Test passenger',
                email: 'passenger@example.test',
                password: randomBytes(24).toString('base64url'),
              })
              .expect(201)
          ).body.data;
          await request(app)
            .post('/api/admin/devices/ESP-TEST/rotate')
            .set('Authorization', 'Bearer ' + passenger.token)
            .set('Origin', config.ADMIN_WEB_ORIGINS)
            .set('X-AbangQue-Admin', '1')
            .send({ expectedVersion: 1 })
            .expect(401);
        },
      );
    } finally {
      await pool?.end();
      await control.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await control.end();
    }
  },
);
