// @vitest-environment jsdom
import { beforeEach, afterEach, test, expect, vi } from "vitest";
import { render, screen, within, cleanup, act } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { api, ApiError } from "./api";
import { DeviceManagement, deviceReport } from "./DeviceManagement";
vi.mock("./api", async (original) => ({
  ...(await original<typeof import("./api")>()),
  api: vi.fn(),
}));
const mock = vi.mocked(api);
const row = {
  id: "DEVICE-TEST",
  label: null,
  model: null,
  description: null,
  administrativeNotes: null,
  source: "device" as "device" | "simulated",
  legacy: false,
  enabled: true,
  jeepneyId: "VEHICLE-A",
  plateNumber: null,
  jeepneyActive: true,
  version: 2,
  credentialState: "Not provisioned",
  validCredentials: 0,
  timestamp: null,
  lastSeenAt: null,
  reportJeepneyId: null,
  latitude: null,
  longitude: null,
  lastReportedStatus: null,
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
};
function setup(items = [row]) {
  mock.mockImplementation(async (path) =>
    path === "/device-jeepney-options"
      ? [
          { id: "VEHICLE-A", active: true, plateNumber: "TEST PLATE" },
          { id: "INACTIVE", active: false, plateNumber: null },
        ]
      : path.startsWith("/devices?")
        ? {
            items,
            total: items.length,
            pageSize: 20,
            counts: {
              total: items.length,
              enabled: items.length,
              disabled: 0,
              fresh: 0,
              staleOrMissing: items.length,
              validUntil: null,
            },
            updatedAt: new Date().toISOString(),
            staleAfterSeconds: 120,
          }
        : {
            record: items[0],
            events: [],
            updatedAt: new Date().toISOString(),
            staleAfterSeconds: 120,
          },
  );
}
beforeEach(() => {
  mock.mockReset();
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function () {
    this.removeAttribute("open");
  };
  setup();
});
afterEach(cleanup);
test("monitoring navigation opens the requested device details without editing", async () => {
  render(<DeviceManagement onExpire={vi.fn()} initialId="DEVICE-TEST" />);
  expect(await screen.findByRole("dialog")).toBeTruthy();
  expect(screen.getByText("Manage device")).toBeTruthy();
  expect(mock.mock.calls.every((call) => call[1] === undefined)).toBe(true);
});
async function details() {
  await screen.findByText("DEVICE-TEST");
  await userEvent.click(screen.getByText("View DEVICE-TEST"));
  await screen.findByText("Manage device");
  await userEvent.click(screen.getByText("Manage device"));
}
test("registration defaults to no reports and no credentials; duplicate failure preserves entries", async () => {
  setup([]);
  render(<DeviceManagement onExpire={vi.fn()} />);
  await screen.findByText(/No devices found/);
  await userEvent.click(screen.getByText("+ Add Device"));
  await userEvent.click(screen.getByText("Register Device"));
  expect((await screen.findByRole("alert")).textContent).toContain("1–96");
  await userEvent.type(screen.getByLabelText("Device identifier *"), "ESP-NEW");
  await userEvent.type(
    screen.getByLabelText("Hardware model (optional)"),
    "Owner recorded model",
  );
  mock.mockRejectedValueOnce(new ApiError(409, "Conflict", "DEVICE_ID_EXISTS"));
  await userEvent.click(screen.getByText("Register Device"));
  expect((await screen.findByRole("alert")).textContent).toContain(
    "already registered",
  );
  expect(
    (screen.getByLabelText("Hardware model (optional)") as HTMLInputElement)
      .value,
  ).toBe("Owner recorded model");
  expect(mock).toHaveBeenLastCalledWith(
    "/devices",
    expect.objectContaining({ id: "ESP-NEW", jeepneyId: null, enabled: true }),
    "POST",
  );
});
test("credential operation is intentional, single-flight, one-time and never stored", async () => {
  const storage = vi.spyOn(Storage.prototype, "setItem");
  render(<DeviceManagement onExpire={vi.fn()} />);
  await details();
  await userEvent.click(screen.getByText("Provision credentials"));
  expect(mock.mock.calls.some((c) => c[0].endsWith("/provision"))).toBe(false);
  let resolve!: (v: unknown) => void;
  const promise = new Promise((r) => {
    resolve = r;
  });
  mock.mockReturnValueOnce(promise);
  await userEvent.dblClick(screen.getByText("Generate one-time credential"));
  expect(
    mock.mock.calls.filter((c) => c[0].endsWith("/provision")),
  ).toHaveLength(1);
  await act(async () =>
    resolve({ token: "TEST-ONLY-ONE-TIME-TOKEN", jeepneyId: "VEHICLE-A" }),
  );
  expect(
    (screen.getByLabelText("Bearer token — secret") as HTMLTextAreaElement)
      .value,
  ).toBe("TEST-ONLY-ONE-TIME-TOKEN");
  expect(storage).not.toHaveBeenCalled();
  await userEvent.click(screen.getByText("I have saved it securely — close"));
  expect(screen.queryByLabelText("Bearer token — secret")).toBeNull();
  storage.mockRestore();
});
test("disable cancellation sends no write; reassignment conflict keeps selected vehicle", async () => {
  render(<DeviceManagement onExpire={vi.fn()} />);
  await details();
  await userEvent.click(screen.getByText("Disable device"));
  await userEvent.click(screen.getByText("Cancel"));
  expect(mock.mock.calls.some((c) => c[0].endsWith("/state"))).toBe(false);
  await details();
  await userEvent.click(screen.getByText("Change assignment"));
  expect(
    (screen.getByRole("option", { name: /INACTIVE/ }) as HTMLOptionElement)
      .disabled,
  ).toBe(true);
  mock.mockRejectedValueOnce(
    new ApiError(409, "Conflict", "ASSIGNMENT_CONFLICT"),
  );
  await userEvent.click(screen.getByText("Confirm change"));
  expect((await screen.findByRole("alert")).textContent).toContain(
    "Another enabled device",
  );
  expect(
    (screen.getByLabelText("Assigned jeepney") as HTMLSelectElement).value,
  ).toBe("VEHICLE-A");
});
test("read outages clear list and expired sessions invoke the auth boundary", async () => {
  const expire = vi.fn();
  render(<DeviceManagement onExpire={expire} />);
  await screen.findByText("DEVICE-TEST");
  mock.mockRejectedValueOnce(new ApiError(503, "Unavailable"));
  await userEvent.click(screen.getByText("Refresh devices"));
  await screen.findByRole("alert");
  expect(screen.queryByText("DEVICE-TEST")).toBeNull();
  mock.mockRejectedValueOnce(new ApiError(401, "Expired"));
  await userEvent.click(screen.getByText("Refresh devices"));
  await screen.findByRole("alert");
  expect(expire).toHaveBeenCalled();
});
test("details contain no token field; simulated records expose no management actions", async () => {
  setup([{ ...row, source: "simulated" as typeof row.source }]);
  render(<DeviceManagement onExpire={vi.fn()} />);
  await screen.findByText("DEVICE-TEST");
  await userEvent.click(screen.getByText("View DEVICE-TEST"));
  const d = screen.getByRole("dialog");
  expect(within(d).queryByText("Manage device")).toBeNull();
  expect(within(d).queryByLabelText(/Bearer token/)).toBeNull();
  expect(within(d).getByText("DEMO / SIMULATED")).toBeTruthy();
});
test("report freshness ages and cannot promote disabled, revoked, reassigned or simulated availability", () => {
  const now = Date.now(),
    fresh = {
      ...row,
      timestamp: new Date(now).toISOString(),
      lastSeenAt: new Date(now).toISOString(),
      validCredentials: 1,
      lastReportedStatus: "AVAILABLE",
      reportJeepneyId: "VEHICLE-A",
    };
  expect(deviceReport(fresh, now, 120).status).toBe("AVAILABLE");
  expect(deviceReport(fresh, now + 120000, 120).status).toBe("UNKNOWN");
  expect(deviceReport({ ...fresh, enabled: false }, now, 120).status).toBe(
    "UNKNOWN",
  );
  expect(deviceReport({ ...fresh, validCredentials: 0 }, now, 120).status).toBe(
    "UNKNOWN",
  );
  expect(
    deviceReport({ ...fresh, jeepneyId: "VEHICLE-B" }, now, 120).status,
  ).toBe("UNKNOWN");
  expect(deviceReport({ ...fresh, source: "simulated" }, now, 120).status).toBe(
    "UNKNOWN",
  );
  expect(deviceReport(row, now, 120).freshness).toBe("No reports");
});
