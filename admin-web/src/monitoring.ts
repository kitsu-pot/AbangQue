import type { RouteOption } from "./jeepneys";
export type MonitoringDevice = {
  id: string;
  enabled: boolean;
  legacy: boolean;
  credentialState: string;
  timestamp: string | null;
  lastSeenAt: string | null;
};
export type MonitoringRow = {
  id: string;
  name: string;
  plateNumber: string | null;
  active: boolean;
  source: "device";
  route: RouteOption | null;
  devices: MonitoringDevice[];
  position: { latitude: number; longitude: number } | null;
  coordinateState: "VALID" | "INVALID" | "MISSING";
  timestamp: string | null;
  reportReceivedAt: string | null;
  lastSeenAt: string | null;
  freshness: "FRESH" | "STALE" | "MISSING";
  status: "FULL" | "AVAILABLE" | "UNKNOWN";
  lastReportedStatus: string | null;
  reportDevice: {
    id: string;
    enabled: boolean;
    currentJeepneyId: string | null;
    credentialRevoked: boolean;
  } | null;
};
export type MonitoringSnapshot = {
  items: MonitoringRow[];
  selected: MonitoringRow | null;
  total: number;
  page: number;
  pageSize: number;
  updatedAt: string;
  staleAfterSeconds: number;
  counts: {
    jeepneys: number;
    fresh: number;
    stale: number;
    missing: number;
    restricted: number;
    excludedTestVehicles: number;
    validUntil: string | null;
  };
};
export function reportState(
  row: MonitoringRow,
  now: number,
  stale: number,
  verified: boolean,
) {
  const measured = Date.parse(row.timestamp ?? ""),
    received = Date.parse(row.lastSeenAt ?? "");
  const fresh =
    row.freshness === "FRESH" &&
    measured <= now &&
    received <= now &&
    now - measured < stale * 1000 &&
    now - received < stale * 1000;
  const historical =
    !row.active ||
    !row.reportDevice?.enabled ||
    row.reportDevice.credentialRevoked ||
    row.reportDevice.currentJeepneyId !== row.id;
  return {
    label: !verified
      ? "Unverified"
      : !row.timestamp
        ? "No report"
        : fresh
          ? "Fresh report"
          : "Stale report",
    tone: !verified
      ? "unverified"
      : historical
        ? "restricted"
        : fresh
          ? "fresh"
          : "stale",
    status:
      verified && fresh && !historical && row.coordinateState === "VALID"
        ? row.status
        : "UNKNOWN",
    historical: historical || !fresh || !verified,
  };
}
export function manilaTime(value: string | null) {
  return value
    ? new Date(value).toLocaleString("en-PH", {
        timeZone: "Asia/Manila",
        dateStyle: "medium",
        timeStyle: "medium",
      }) + " PHT"
    : "No report";
}
export function deviceReportLabel(
  timestamp: string | null,
  lastSeenAt: string | null,
  now: number,
  stale: number,
  verified: boolean,
) {
  if (!verified) return "Unverified device reporting";
  if (!timestamp) return "No device reports";
  const measurement = Date.parse(timestamp),
    received = Date.parse(lastSeenAt ?? "");
  return measurement <= now &&
    received <= now &&
    now - measurement < stale * 1000 &&
    now - received < stale * 1000
    ? "Fresh device report"
    : "Stale device report";
}
export function pollInterval(value: unknown) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 10 && n <= 300 ? n * 1000 : 30000;
}
