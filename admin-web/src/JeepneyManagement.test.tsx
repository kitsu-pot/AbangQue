// @vitest-environment jsdom
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
  cleanup,
  render,
  screen,
  within,
  waitFor,
  act,
} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { JeepneyManagement } from "./JeepneyManagement";
import { api, ApiError } from "./api";
import { currentReport, validateVehicle } from "./jeepneys";
import type { Jeepney, JeepneyPage, RouteOption } from "./jeepneys";
vi.mock("./api", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./api")>()),
  api: vi.fn(),
}));
const mockedApi = vi.mocked(api);
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
const route: RouteOption = {
  id: "a1b2c3d4-0000-4000-8000-000000000001",
  origin: "Boac",
  destination: "Gasan",
  active: true,
};
const inactive = {
  ...route,
  id: "a1b2c3d4-0000-4000-8000-000000000002",
  origin: "Gasan",
  destination: "Boac",
  active: false,
};
const row: Jeepney = {
  id: "TEST-01",
  name: "Test fixture",
  source: "device",
  active: true,
  plateNumber: null,
  description: "",
  administrativeNotes: "",
  route: null,
  version: 3,
  createdAt: "2026-01-01T00:00:00Z",
  updatedAt: "2026-01-01T00:00:00Z",
  position: null,
  timestamp: null,
  lastSeenAt: null,
  freshness: "MISSING",
  status: "UNKNOWN",
  lastReportedStatus: null,
  eta: null,
};
const page = (items: Jeepney[] = [row]): JeepneyPage => ({
  items,
  total: items.length,
  registeredTotal: items.filter((r) => r.source === "device").length,
  page: 1,
  pageSize: 20,
  updatedAt: new Date().toISOString(),
  staleAfterSeconds: 120,
});
function setup(items = [row]) {
  mockedApi.mockImplementation(async (path) => {
    if (path === "/route-options") return [route, inactive];
    if (path.startsWith("/jeepneys?")) return page(items);
    if (path === "/jeepneys/TEST-01")
      return {
        record: items[0],
        updatedAt: new Date().toISOString(),
        staleAfterSeconds: 120,
      };
    return items[0];
  });
}
beforeEach(() => {
  mockedApi.mockReset();
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function () {
    this.removeAttribute("open");
  };
});
afterEach(() => cleanup());
test("empty registry and missing routes offer truthful registration without fabricated reports", async () => {
  setup([]);
  render(<JeepneyManagement onExpire={vi.fn()} />);
  await screen.findByText("No jeepneys found");
  await userEvent.click(screen.getByRole("button", { name: "+ Add Jeepney" }));
  const dialog = screen.getByRole("dialog");
  await userEvent.click(
    within(dialog).getByRole("button", { name: "Register Jeepney" }),
  );
  expect(within(dialog).getByText(/Use 1–64 uppercase/)).toBeTruthy();
  await userEvent.type(
    within(dialog).getByLabelText("Jeepney identifier *"),
    "NEW-01",
  );
  await userEvent.type(
    within(dialog).getByLabelText("Vehicle display name *"),
    "New vehicle",
  );
  expect(
    (
      within(dialog).getByRole("option", {
        name: /Gasan → Boac/,
      }) as HTMLOptionElement
    ).disabled,
  ).toBe(true);
  await userEvent.click(
    within(dialog).getByRole("button", { name: "Register Jeepney" }),
  );
  await screen.findByText("Jeepney record saved.");
  expect(mockedApi).toHaveBeenCalledWith(
    "/jeepneys",
    {
      id: "NEW-01",
      name: "New vehicle",
      active: true,
      routeId: null,
      plateNumber: null,
      description: "",
      administrativeNotes: "",
    },
    "POST",
  );
});
test("edit preserves identifier and typed values on concurrent conflict and route rejection", async () => {
  setup();
  render(<JeepneyManagement onExpire={vi.fn()} />);
  await screen.findByText("1 matching records");
  await userEvent.click(
    screen.getAllByRole("button", { name: "Edit TEST-01" })[0],
  );
  const dialog = screen.getByRole("dialog");
  expect(
    (within(dialog).getByLabelText("Jeepney identifier *") as HTMLInputElement)
      .readOnly,
  ).toBe(true);
  await userEvent.type(
    within(dialog).getByLabelText("Vehicle description (optional)"),
    "My pending edit",
  );
  await userEvent.selectOptions(
    within(dialog).getByLabelText("Registered route (optional)"),
    route.id,
  );
  mockedApi.mockRejectedValueOnce(
    new ApiError(409, "Conflict", "RECORD_CHANGED"),
  );
  await userEvent.click(
    within(dialog).getByRole("button", { name: "Save Changes" }),
  );
  expect((await screen.findByRole("alert")).textContent).toContain(
    "record changed",
  );
  expect(
    (
      within(dialog).getByLabelText(
        "Vehicle description (optional)",
      ) as HTMLInputElement
    ).value,
  ).toBe("My pending edit");
  expect(mockedApi).toHaveBeenCalledWith(
    "/jeepneys/TEST-01",
    expect.objectContaining({
      expectedVersion: 3,
      routeId: route.id,
      description: "My pending edit",
    }),
    "PUT",
  );
  const sent = mockedApi.mock.calls.find((c) => c[2] === "PUT")?.[1];
  expect(sent).not.toHaveProperty("id");
  expect(sent).not.toHaveProperty("active");
  mockedApi.mockRejectedValueOnce(
    new ApiError(409, "Route inactive", "ROUTE_INELIGIBLE"),
  );
  await userEvent.click(
    within(dialog).getByRole("button", { name: "Save Changes" }),
  );
  expect((await screen.findByRole("alert")).textContent).toContain(
    "route is missing or inactive",
  );
});
test("deactivation requires confirmation and sends version; cancellation sends no write", async () => {
  setup();
  render(<JeepneyManagement onExpire={vi.fn()} />);
  await screen.findByText("1 matching records");
  await userEvent.click(
    screen.getAllByRole("button", { name: "Deactivate TEST-01" })[0],
  );
  await screen.findByRole("heading", { name: "Deactivate TEST-01?" });
  await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(mockedApi.mock.calls.some((c) => c[0].endsWith("/activation"))).toBe(
    false,
  );
  await screen.findByText("1 matching records");
  await userEvent.click(
    screen.getAllByRole("button", { name: "Deactivate TEST-01" })[0],
  );
  await userEvent.click(
    screen.getByRole("button", { name: "Confirm deactivation" }),
  );
  await screen.findByText(/Jeepney deactivated/);
  expect(mockedApi).toHaveBeenCalledWith("/jeepneys/TEST-01/activation", {
    active: false,
    expectedVersion: 3,
  });
});
test("filters reset pagination, paging uses backend limits and delayed searches cannot restore older rows", async () => {
  const old = deferred<JeepneyPage>();
  setup();
  mockedApi.mockImplementation(async (path) => {
    if (path === "/route-options") return [route];
    const params = new URLSearchParams(path.split("?")[1]);
    if (params.get("search") === "old") return old.promise;
    return { ...page(), total: 21 };
  });
  render(<JeepneyManagement onExpire={vi.fn()} />);
  await screen.findByText("21 matching records");
  await userEvent.click(screen.getByRole("button", { name: "Next" }));
  await waitFor(() =>
    expect(mockedApi.mock.calls.some((c) => c[0].includes("page=2"))).toBe(
      true,
    ),
  );
  await userEvent.selectOptions(
    screen.getByLabelText("Record status"),
    "inactive",
  );
  await waitFor(() =>
    expect(
      mockedApi.mock.calls.some(
        (c) => c[0].includes("status=inactive") && c[0].includes("page=1"),
      ),
    ).toBe(true),
  );
  await userEvent.type(screen.getByLabelText("Search records"), "old");
  await userEvent.click(screen.getByRole("button", { name: "Search" }));
  await userEvent.clear(screen.getByLabelText("Search records"));
  await userEvent.type(screen.getByLabelText("Search records"), "new");
  await userEvent.click(screen.getByRole("button", { name: "Search" }));
  await screen.findByText("21 matching records");
  await act(async () => old.resolve(page([{ ...row, id: "OLD-RESULT" }])));
  expect(screen.queryByText("OLD-RESULT")).toBeNull();
});
test("details distinguish missing GPS, metadata, historical status and read-only test source", async () => {
  setup([{ ...row, source: "simulated", lastReportedStatus: "AVAILABLE" }]);
  render(<JeepneyManagement onExpire={vi.fn()} />);
  await screen.findByText("1 matching records");
  expect(screen.queryByRole("button", { name: "Edit TEST-01" })).toBeNull();
  await userEvent.click(
    screen.getAllByRole("button", { name: "View TEST-01" })[0],
  );
  const dialog = screen.getByRole("dialog");
  expect(within(dialog).getByText("No GPS report")).toBeTruthy();
  expect(
    within(dialog).getByText("AVAILABLE — not current availability"),
  ).toBeTruthy();
  expect(within(dialog).getByText("UNKNOWN")).toBeTruthy();
});
test("backend error clears list and expiry invokes the protected-session handler", async () => {
  setup();
  const expire = vi.fn();
  render(<JeepneyManagement onExpire={expire} />);
  await screen.findByText("1 matching records");
  mockedApi.mockRejectedValueOnce(new ApiError(503, "Server unavailable"));
  await userEvent.click(screen.getByRole("button", { name: "Refresh list" }));
  await screen.findByRole("alert");
  expect(screen.queryAllByText("TEST-01")).toHaveLength(0);
  mockedApi.mockRejectedValueOnce(new ApiError(401, "Session ended"));
  await userEvent.click(screen.getByRole("button", { name: "Retry list" }));
  await waitFor(() => expect(expire).toHaveBeenCalled());
});
test("duplicate submission is single-flight and uncertain saves retain form data", async () => {
  setup([]);
  render(<JeepneyManagement onExpire={vi.fn()} />);
  await screen.findByText("No jeepneys found");
  await userEvent.click(screen.getByRole("button", { name: "+ Add Jeepney" }));
  await userEvent.type(
    screen.getByLabelText("Jeepney identifier *"),
    "TEST-NEW",
  );
  await userEvent.type(
    screen.getByLabelText("Vehicle display name *"),
    "Retain my entry",
  );
  const save = deferred<unknown>();
  mockedApi.mockReturnValueOnce(save.promise);
  await userEvent.dblClick(
    screen.getByRole("button", { name: "Register Jeepney" }),
  );
  expect(mockedApi.mock.calls.filter((c) => c[0] === "/jeepneys")).toHaveLength(
    1,
  );
  await act(async () => save.reject(new ApiError(0, "Timed out")));
  expect((await screen.findByRole("alert")).textContent).toContain(
    "outcome could not be confirmed",
  );
  expect(
    (screen.getByLabelText("Vehicle display name *") as HTMLInputElement).value,
  ).toBe("Retain my entry");
});
test("detail refresh failure hides availability and a late response cannot reopen a closed dialog", async () => {
  const timestamp = new Date().toISOString();
  const fresh: Jeepney = {
    ...row,
    timestamp,
    lastSeenAt: timestamp,
    status: "AVAILABLE",
    freshness: "FRESH",
  };
  setup([fresh]);
  render(<JeepneyManagement onExpire={vi.fn()} />);
  await screen.findByText("1 matching records");
  await userEvent.click(
    screen.getAllByRole("button", { name: "View TEST-01" })[0],
  );
  const dialog = screen.getByRole("dialog");
  expect(within(dialog).getByText("AVAILABLE")).toBeTruthy();
  mockedApi.mockRejectedValueOnce(new ApiError(503, "Service unavailable"));
  await userEvent.click(
    within(dialog).getByRole("button", { name: "Refresh details" }),
  );
  await within(dialog).findByRole("alert");
  expect(within(dialog).getByText("UNKNOWN")).toBeTruthy();
  const pending = deferred<unknown>();
  mockedApi.mockReturnValueOnce(pending.promise);
  await userEvent.click(
    within(dialog).getByRole("button", { name: "Refresh details" }),
  );
  await userEvent.click(
    within(dialog).getByRole("button", { name: "Close details" }),
  );
  await act(async () =>
    pending.resolve({
      record: fresh,
      updatedAt: timestamp,
      staleAfterSeconds: 120,
    }),
  );
  expect(screen.queryByRole("dialog")).toBeNull();
});

test("freshness expires at the threshold and never promotes demo/inactive availability", () => {
  const now = Date.now(),
    fresh = {
      ...row,
      timestamp: new Date(now).toISOString(),
      lastSeenAt: new Date(now).toISOString(),
      status: "AVAILABLE" as const,
    };
  expect(currentReport(fresh, now, 120).status).toBe("AVAILABLE");
  expect(currentReport(fresh, now + 120000, 120)).toEqual({
    freshness: "Stale",
    status: "UNKNOWN",
  });
  expect(currentReport({ ...fresh, active: false }, now, 120).status).toBe(
    "UNKNOWN",
  );
  expect(
    currentReport({ ...fresh, source: "simulated" }, now, 120).status,
  ).toBe("UNKNOWN");
  expect(
    validateVehicle({
      id: "X",
      name: "Name",
      active: true,
      plateNumber: "!!",
      routeId: "",
      description: "",
      administrativeNotes: "",
    }),
  ).toHaveProperty("plateNumber");
});
