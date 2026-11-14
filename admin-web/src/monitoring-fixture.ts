// Automated tests only. Never imported by production modules or seeded into owner data.
import type { MonitoringRow, MonitoringSnapshot } from "./monitoring";
export function monitoringFixture(): MonitoringSnapshot {
  const timestamp = new Date(Date.now() - 10000).toISOString();
  const row: MonitoringRow = {
    id: "QA-ONE",
    name: "DEMO isolated test fixture",
    plateNumber: "TEST 01",
    active: true,
    source: "device",
    route: {
      id: "route-fixture",
      origin: "Boac",
      destination: "Gasan",
      active: true,
    },
    devices: [
      {
        id: "QA-DEVICE",
        enabled: true,
        legacy: false,
        credentialState: "Provisioned",
        timestamp,
        lastSeenAt: timestamp,
      },
    ],
    position: { latitude: 13.4, longitude: 121.8 },
    coordinateState: "VALID",
    timestamp,
    reportReceivedAt: timestamp,
    lastSeenAt: timestamp,
    freshness: "FRESH",
    status: "AVAILABLE",
    lastReportedStatus: "AVAILABLE",
    reportDevice: {
      id: "QA-DEVICE",
      enabled: true,
      currentJeepneyId: "QA-ONE",
      credentialRevoked: false,
    },
  };
  return {
    items: [
      row,
      {
        ...row,
        id: "QA-NONE",
        position: null,
        coordinateState: "MISSING",
        timestamp: null,
        lastSeenAt: null,
        reportReceivedAt: null,
        freshness: "MISSING",
        status: "UNKNOWN",
        reportDevice: null,
        devices: [],
      },
    ],
    selected: null,
    total: 2,
    page: 1,
    pageSize: 100,
    updatedAt: new Date().toISOString(),
    staleAfterSeconds: 120,
    counts: {
      jeepneys: 2,
      fresh: 1,
      stale: 0,
      missing: 1,
      restricted: 0,
      excludedTestVehicles: 2,
      validUntil: new Date(Date.now() + 110000).toISOString(),
    },
  };
}
