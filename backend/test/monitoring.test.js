import { test } from "node:test";
import assert from "node:assert/strict";
import request from "supertest";
import { createApp } from "../src/app.js";
import { loadConfig } from "../src/config.js";
import { monitoringQuery } from "../src/admin-monitoring.js";
import { presentMonitoring } from "../src/admin-monitoring-repository.js";
const config = loadConfig({
  DATABASE_URL: "postgresql://unused@127.0.0.1/unused",
});
test("monitoring validates bounded filters and disallows simulation/source overrides", () => {
  assert.equal(monitoringQuery.parse({}).page, 1);
  for (const input of [
    { page: 0 },
    { page: 100001 },
    { search: "x".repeat(121) },
    { routeId: "Boac-Gasan" },
    { source: "simulated" },
    { selectedId: "bad id" },
    { device: "online" },
    { reporting: ["fresh", "stale"] },
  ])
    assert.equal(monitoringQuery.safeParse(input).success, false);
});
test("monitoring is admin-only, no-store and sanitizes database errors", async () => {
  let calls = 0;
  const denied = createApp({
    config,
    adminRepository: { session: async () => null },
    adminMonitoringRepository: {
      snapshot: async () => {
        calls++;
      },
    },
  });
  for (const headers of [
    {},
    { Authorization: "Bearer passenger" },
    { Cookie: "abangque_passenger=passenger" },
    { Cookie: "abangque_admin=invalid" },
  ])
    await request(denied).get("/api/admin/monitoring").set(headers).expect(401);
  assert.equal(calls, 0);
  const adminRepository = {
    session: async () => ({
      id: "test",
      role: "ADMIN",
      expires_at: new Date(Date.now() + 60000),
    }),
  };
  const app = createApp({
    config,
    adminRepository,
    adminMonitoringRepository: {
      snapshot: async () => {
        throw new Error("private SQL credential value");
      },
    },
  });
  const cookie = "abangque_admin=aqa_" + "x".repeat(43);
  await request(app)
    .get("/api/admin/monitoring?page=-1")
    .set("Cookie", cookie)
    .expect(400);
  const r = await request(app)
    .get("/api/admin/monitoring")
    .set("Cookie", cookie)
    .expect(503);
  assert.equal(r.headers["cache-control"], "no-store");
  assert.equal(JSON.stringify(r.body).includes("private"), false);
  const passenger = createApp({
    config,
    adminRepository: {
      session: async () => ({
        role: "PASSENGER",
        expires_at: new Date(Date.now() + 60000),
      }),
    },
    adminMonitoringRepository: {},
  });
  await request(passenger)
    .get("/api/admin/monitoring")
    .set("Cookie", cookie)
    .expect(401);
});
test("invalid or historical coordinates and revoked/previous assignments cannot grant availability", () => {
  const row = {
    id: "A",
    source: "device",
    active: true,
    latitude: 13.4,
    longitude: 121.8,
    timestamp: new Date(),
    fresh: true,
    lastReportedStatus: "AVAILABLE",
    reportDevice: {
      id: "D",
      enabled: true,
      credentialRevoked: false,
      currentJeepneyId: "A",
    },
  };
  assert.equal(presentMonitoring(row).status, "AVAILABLE");
  for (const patch of [
    { latitude: NaN },
    { longitude: 181 },
    { latitude: null },
    { active: false },
    { fresh: false },
    { reportDevice: { ...row.reportDevice, enabled: false } },
    { reportDevice: { ...row.reportDevice, credentialRevoked: true } },
    { reportDevice: { ...row.reportDevice, currentJeepneyId: "B" } },
  ])
    assert.equal(presentMonitoring({ ...row, ...patch }).status, "UNKNOWN");
  assert.equal(
    presentMonitoring({ ...row, latitude: NaN }).coordinateState,
    "INVALID",
  );
  assert.equal(
    presentMonitoring({
      ...row,
      latitude: null,
      longitude: null,
      timestamp: null,
    }).coordinateState,
    "MISSING",
  );
});
