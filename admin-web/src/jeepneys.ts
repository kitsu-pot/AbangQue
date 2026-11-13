import { ApiError } from "./api";
export type RouteOption = {
  id: string;
  origin: string;
  destination: string;
  active: boolean;
};
export type Jeepney = {
  id: string;
  name: string;
  active: boolean;
  source: "device" | "demo" | "simulated";
  plateNumber: string | null;
  description: string;
  administrativeNotes: string;
  route: RouteOption | null;
  version: number;
  createdAt: string;
  updatedAt: string;
  position: { latitude: number; longitude: number } | null;
  timestamp: string | null;
  lastSeenAt: string | null;
  freshness: "FRESH" | "STALE" | "MISSING";
  status: "FULL" | "AVAILABLE" | "UNKNOWN";
  lastReportedStatus: string | null;
  eta: null;
};
export type JeepneyPage = {
  items: Jeepney[];
  total: number;
  registeredTotal: number;
  page: number;
  pageSize: number;
  updatedAt: string;
  staleAfterSeconds: number;
};
export type VehicleForm = {
  id: string;
  name: string;
  plateNumber: string;
  description: string;
  administrativeNotes: string;
  routeId: string;
  active: boolean;
};
export const direction = (r: RouteOption | null) =>
  r
    ? `${r.origin} → ${r.destination}${r.active ? "" : " (inactive)"}`
    : "Unassigned";
export const displayTime = (v: string | null) =>
  v
    ? new Date(v).toLocaleString("en-PH", {
        dateStyle: "medium",
        timeStyle: "medium",
      })
    : "No report";
export function validateVehicle(form: VehicleForm) {
  const errors: Record<string, string> = {};
  if (!/^[A-Z0-9][A-Z0-9_-]{0,63}$/.test(form.id))
    errors.id = "Use 1–64 uppercase letters, digits, hyphens or underscores.";
  if (!form.name.trim() || form.name.trim().length > 120)
    errors.name = "Enter a vehicle display name of 1–120 characters.";
  if (
    form.plateNumber.trim() &&
    !/^[A-Z0-9][A-Z0-9 -]{1,19}$/.test(form.plateNumber.trim().toUpperCase())
  )
    errors.plateNumber = "Use 2–20 letters, digits, spaces or hyphens.";
  for (const key of ["name", "description", "administrativeNotes"] as const) {
    if (/[\u0000-\u001f\u007f]/u.test(form[key]))
      errors[key] = "Use plain text without line breaks or control characters.";
  }
  if (form.description.trim().length > 500)
    errors.description = "Use at most 500 characters.";
  if (form.administrativeNotes.trim().length > 2000)
    errors.administrativeNotes = "Use at most 2,000 characters.";
  return errors;
}
export function vehicleError(error: unknown, saving = false) {
  if (error instanceof ApiError) {
    const messages: Record<string, string> = {
      JEEPNEY_ID_EXISTS:
        "This identifier is already registered. Check the existing record before submitting again.",
      RECORD_CHANGED:
        "This record changed since you opened it. Your entries are preserved. Close the form, reload the record and review the latest values before saving.",
      ROUTE_INELIGIBLE:
        "The selected route is missing or inactive. Reload route choices or leave the vehicle unassigned.",
      TEST_RECORD_READ_ONLY:
        "DEMO and SIMULATED records are managed by the existing test tools and are read-only here.",
      JEEPNEY_NOT_FOUND: "This jeepney record could not be found.",
      ADMIN_WRITE_RATE_LIMITED:
        "Too many changes. Wait a minute before trying again.",
      INVALID_JEEPNEY_INPUT: "Please review the highlighted fields.",
    };
    if (saving && (error.status === 0 || error.status >= 500))
      return "The save outcome could not be confirmed. Your entries are preserved. Reload the list and check the record before retrying.";
    if (error.status === 403)
      return "This request was not permitted. Sign in again from the configured administrator site.";
    return messages[error.code] ?? error.message;
  }
  return "The request could not be completed. Please retry.";
}
export function currentReport(row: Jeepney, now: number, staleSeconds: number) {
  const fresh =
    row.timestamp &&
    row.lastSeenAt &&
    Date.parse(row.timestamp) <= now &&
    Date.parse(row.lastSeenAt) <= now &&
    now - Date.parse(row.timestamp) < staleSeconds * 1000 &&
    now - Date.parse(row.lastSeenAt) < staleSeconds * 1000;
  return {
    freshness: !row.timestamp ? "No report" : fresh ? "Fresh" : "Stale",
    status:
      fresh && row.active && row.source === "device" ? row.status : "UNKNOWN",
  };
}
