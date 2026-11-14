import { test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import pg from "pg";
import request from "supertest";
import { applyTestMigrations } from "../test-support/migrations.js";
import { AdminMonitoringRepository } from "../src/admin-monitoring-repository.js";
import { AdminDeviceRepository } from "../src/admin-device-repository.js";
import { AdminJeepneyRepository } from "../src/admin-jeepney-repository.js";
import { AdminRepository } from "../src/admin-repository.js";
import { PostgresRepository } from "../src/repository.js";
import { createApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { hashToken } from "../src/passenger-auth.js";
import { issueCredential } from "../src/security.js";
import { monitoringQuery } from "../src/admin-monitoring.js";

test(
  "PostgreSQL monitoring preserves ownership, timestamps, device states and directional filters",
  { skip: process.env.AUTH_INTEGRATION !== "true" },
  async (t) => {
    const config = loadConfig({
      ...process.env,
      NODE_ENV: "test",
      ENABLE_GPS_SIMULATOR: "false",
    });
    const schema = "monitor_test_" + randomBytes(12).toString("hex"),
      control = new pg.Pool({ connectionString: config.DATABASE_URL });
    let pool;
    try {
      await control.query(`CREATE SCHEMA "${schema}"`);
      pool = new pg.Pool({
        connectionString: config.DATABASE_URL,
        options: `-c search_path=${schema}`,
      });
      await applyTestMigrations(pool);
      const now = Date.now(),
        timestamp = new Date(now - 10000).toISOString();
      const repo = new AdminMonitoringRepository(pool),
        admin = new AdminRepository(pool),
        devices = new AdminDeviceRepository(pool);
      const user = (
        await pool.query(
          "INSERT INTO admin_accounts(id,email,password_hash) VALUES($1,'monitor@example.test',$2) RETURNING id,email,role,password_hash",
          [randomUUID(), "$argon2id$test-only-unusable-hash"],
        )
      ).rows[0];
      const token = "aqa_" + randomBytes(32).toString("base64url");
      await admin.login(user, hashToken(token), 600);
      const app = createApp({
        config,
        clock: () => now,
        adminRepository: admin,
        adminMonitoringRepository: repo,
        adminJeepneyRepository: new AdminJeepneyRepository(pool),
        repository: new PostgresRepository(pool),
      });
      const get = (q) =>
        request(app)
          .get(
            "/api/admin/monitoring" + (q ? "?" + new URLSearchParams(q) : ""),
          )
          .set("Cookie", "abangque_admin=" + token);
      const routes = (
        await pool.query(
          "INSERT INTO registered_routes(origin,destination) VALUES('Boac','Gasan'),('Gasan','Boac') RETURNING id",
        )
      ).rows;
      await pool.query(
        "INSERT INTO jeepneys(id,name,source,route_id) VALUES('A','DEMO isolated test A','device',$1),('B','DEMO isolated test B','device',$2),('C','DEMO isolated no-device fixture','device',NULL),('SIM-GPS-001','DEMO simulated fixture','simulated',NULL),('DEMO-1','DEMO historical fixture','demo',NULL)",
        [routes[0].id, routes[1].id],
      );
      const key = issueCredential(),
        sim = issueCredential();
      for (const [k, id, source] of [
        [key, "A", "device"],
        [sim, "SIM-GPS-001", "simulated"],
      ])
        await pool.query(
          "INSERT INTO device_credentials(id,jeepney_id,source,secret_hash) VALUES($1,$2,$3,$4)",
          [k.id, id, source, k.secretHash],
        );
      await devices.create(
        {
          id: "NO-REPORT",
          label: null,
          model: null,
          description: null,
          administrativeNotes: null,
          enabled: true,
          jeepneyId: "B",
        },
        user.id,
      );
      for (const [k, id, source] of [
        [key, "A", "device"],
        [sim, "SIM-GPS-001", "simulated"],
      ])
        await pool.query(
          "INSERT INTO location_status_updates(jeepney_id,source,credential_id,latitude,longitude,status,recorded_at,received_at) VALUES($1,$2,$3,13.4,121.8,'AVAILABLE',$4,$5)",
          [id, source, k.id, timestamp, new Date(now - 5000)],
        );
      await t.test(
        "empty positions, real-source counts, original coordinates and secret-free admin response",
        async () => {
          const { body } = await get().expect(200),
            data = body.data;
          assert.equal(data.counts.jeepneys, 3);
          assert.equal(data.counts.excludedTestVehicles, 2);
          assert.equal(data.counts.fresh, 1);
          assert.equal(data.counts.missing, 1);
          assert.deepEqual(
            data.items.map((r) => r.id),
            ["A", "B", "C"],
          );
          assert.deepEqual(data.items[0].position, {
            latitude: 13.4,
            longitude: 121.8,
          });
          assert.equal(data.items[0].timestamp, timestamp);
          assert.equal(data.items[0].status, "AVAILABLE");
          assert.equal(data.items[1].position, null);
          assert.equal(data.items[1].freshness, "MISSING");
          assert.equal(data.items[2].devices.length, 0);
          for (const secret of [
            key.token,
            key.secretHash,
            "password_hash",
            "secret_hash",
            "administrativeNotes",
          ])
            assert.ok(!JSON.stringify(data).includes(secret));
          assert.equal(
            (await get().expect(200)).body.data.items[0].timestamp,
            timestamp,
          );
        },
      );
      await t.test(
        "out-of-order receipt does not replace the latest GPS measurement",
        async () => {
          await pool.query(
            "INSERT INTO location_status_updates(jeepney_id,source,credential_id,latitude,longitude,status,recorded_at,received_at) VALUES('A','device',$1,13.5,121.9,'FULL',$2,$3)",
            [key.id, new Date(now - 50000), new Date(now - 1000)],
          );
          const row = (await get().expect(200)).body.data.items[0];
          assert.equal(row.timestamp, timestamp);
          assert.equal(
            row.reportReceivedAt,
            new Date(now - 5000).toISOString(),
          );
          assert.equal(row.lastSeenAt, new Date(now - 1000).toISOString());
          assert.equal(row.lastReportedStatus, "AVAILABLE");
        },
      );
      await t.test(
        "direction, device, search and activation filters; selected detail survives filters",
        async () => {
          assert.deepEqual(
            (
              await get({ routeId: routes[0].id }).expect(200)
            ).body.data.items.map((r) => r.id),
            ["A"],
          );
          assert.deepEqual(
            (
              await get({ routeId: routes[1].id, selectedId: "A" }).expect(200)
            ).body.data.items.map((r) => r.id),
            ["B"],
          );
          assert.equal(
            (await get({ routeId: routes[1].id, selectedId: "A" })).body.data
              .selected.id,
            "A",
          );
          assert.deepEqual(
            (await get({ device: "unassigned" })).body.data.items.map(
              (r) => r.id,
            ),
            ["C"],
          );
          assert.equal((await get({ search: "%" })).body.data.total, 0);
          await pool.query(
            "UPDATE registered_routes SET active=false WHERE id=$1",
            [routes[0].id],
          );
          assert.equal(
            (await get({ search: "A" })).body.data.items[0].route.active,
            false,
          );
          await pool.query("UPDATE jeepneys SET active=false WHERE id='A'");
          const inactive = (await get({ status: "inactive" })).body.data
            .items[0];
          assert.equal(inactive.id, "A");
          assert.equal(inactive.status, "UNKNOWN");
          await pool.query(
            "UPDATE jeepneys SET active=true,route_id=$1 WHERE id='A'",
            [routes[1].id],
          );
          assert.equal(
            (await get({ routeId: routes[0].id })).body.data.total,
            0,
          );
        },
      );
      await t.test(
        "disabled and revoked remain fresh measurements but UNKNOWN availability",
        async () => {
          await devices.change(
            "LEGACY-A",
            { enabled: false, expectedVersion: 1 },
            user.id,
            "DISABLE",
          );
          const d = (await get({ device: "disabled" })).body.data;
          assert.equal(d.items[0].freshness, "FRESH");
          assert.equal(d.items[0].status, "UNKNOWN");
          assert.equal(d.counts.restricted, 1);
          await devices.change(
            "LEGACY-A",
            { enabled: true, expectedVersion: 2 },
            user.id,
            "ENABLE",
          );
          await devices.change(
            "LEGACY-A",
            { expectedVersion: 3 },
            user.id,
            "REVOKE",
          );
          const revoked = (await get({ device: "revoked" })).body.data.items[0];
          assert.equal(revoked.status, "UNKNOWN");
          assert.equal(revoked.reportDevice.credentialRevoked, true);
        },
      );
      await t.test(
        "reassignment never moves old vehicle coordinates to new vehicle",
        async () => {
          await devices.change(
            "NO-REPORT",
            { jeepneyId: null, expectedVersion: 1 },
            user.id,
            "ASSIGN",
          );
          await devices.change(
            "LEGACY-A",
            { jeepneyId: "B", expectedVersion: 4 },
            user.id,
            "ASSIGN",
          );
          const { items } = (await get()).body.data;
          assert.equal(items[0].devices.length, 0);
          assert.equal(items[0].reportDevice.currentJeepneyId, "B");
          assert.equal(items[0].status, "UNKNOWN");
          assert.equal(items[0].timestamp, timestamp);
          assert.equal(items[1].devices[0].id, "LEGACY-A");
          assert.equal(items[1].position, null);
          assert.equal(items[1].timestamp, null);
        },
      );
      await t.test(
        "freshness boundary, future reports and delayed communication are conservative",
        async () => {
          const query = monitoringQuery.parse({});
          const aged = await repo.snapshot(query, now + 110000, 120);
          assert.equal(aged.items[0].freshness, "STALE");
          assert.equal(aged.items[0].status, "UNKNOWN");
          assert.equal(aged.counts.fresh, 0);
          const before = await repo.snapshot(query, now - 20000, 120);
          assert.equal(before.items[0].freshness, "STALE");
          await pool.query(
            "UPDATE location_status_updates SET received_at=$1 WHERE jeepney_id='A'",
            [new Date(now - 130000)],
          );
          assert.equal((await get()).body.data.items[0].freshness, "STALE");
        },
      );
      await t.test(
        "bounded pages and latest-communication index exist",
        async () => {
          await pool.query(
            "INSERT INTO jeepneys(id,name,source) SELECT 'PAGE-'||lpad(n::text,3,'0'),'DEMO pagination fixture','device' FROM generate_series(1,101)n",
          );
          const first = (await get()).body.data,
            second = (await get({ page: "2" })).body.data;
          assert.equal(first.items.length, 100);
          assert.equal(second.items.length, 4);
          assert.equal(second.total, 104);
          assert.equal(
            (
              await pool.query(
                "SELECT 1 FROM pg_indexes WHERE schemaname=$1 AND indexname='updates_credential_received'",
                [schema],
              )
            ).rowCount,
            1,
          );
        },
      );
    } finally {
      if (pool) await pool.end();
      await control.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await control.end();
    }
  },
);
