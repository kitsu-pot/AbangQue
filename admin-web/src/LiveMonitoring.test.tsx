// @vitest-environment jsdom
import React from "react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
  cleanup,
  render,
  screen,
  waitFor,
  within,
  fireEvent,
  act,
  renderHook,
} from "@testing-library/react";
import { Map as LeafletMap } from "leaflet";
import { LiveMonitoring } from "./LiveMonitoring";
import { MonitoringMap } from "./MonitoringMap";
import { api, ApiError } from "./api";
import { reportState, pollInterval, manilaTime } from "./monitoring";
import { monitoringFixture } from "./monitoring-fixture";
import { useMonitoring } from "./useMonitoring";
vi.mock("./api", async (original) => ({
  ...(await original<typeof import("./api")>()),
  api: vi.fn(),
}));
const mocked = vi.mocked(api);
beforeEach(() => {
  mocked.mockReset();
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
  Object.defineProperty(document, "hidden", {
    configurable: true,
    value: false,
  });
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});
function respond() {
  mocked.mockImplementation(async (path) =>
    path === "/route-options" ? [] : monitoringFixture(),
  );
}
test("mobile filters collapse and selected details use a dismissible dialog", async () => {
  vi.stubGlobal("matchMedia", () => ({
    matches: true,
    addEventListener() {},
    removeEventListener() {},
  }));
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function () {
    this.removeAttribute("open");
  };
  respond();
  render(<LiveMonitoring onExpire={vi.fn()} />);
  const button = await screen.findByRole("button", {
    name: /QA-NONE.*No report/,
  });
  expect(
    document.querySelector(".monitor-filter-disclosure")?.hasAttribute("open"),
  ).toBe(false);
  fireEvent.click(button);
  const dialog = await screen.findByRole("dialog");
  expect(within(dialog).getByText("No GPS reports received yet.")).toBeTruthy();
  fireEvent.click(within(dialog).getByRole("button", { name: "Close dialog" }));
  await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
});
test("valid stored markers, missing coordinates, selection and filters with separate historical status", async () => {
  respond();
  render(<LiveMonitoring onExpire={vi.fn()} />);
  const button = await screen.findByRole("button", {
    name: /QA-ONE.*Fresh report/,
  });
  expect(document.querySelectorAll(".monitor-pin").length).toBe(1);
  fireEvent.click(button);
  const detail = await screen.findByRole("region", {
    name: "Selected jeepney QA-ONE",
  });
  expect(within(detail).getByText("13.4, 121.8")).toBeTruthy();
  expect(within(detail).getAllByText(/PHT/).length).toBeGreaterThan(0);
  fireEvent.change(screen.getByLabelText("GPS reporting"), {
    target: { value: "stale" },
  });
  await waitFor(() =>
    expect(mocked.mock.calls.at(-1)?.[0]).toContain("reporting=stale"),
  );
  expect(
    screen.getByRole("region", { name: "Selected jeepney QA-ONE" }),
  ).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: /QA-NONE.*No report/ }));
  expect(await screen.findByText("No GPS reports received yet.")).toBeTruthy();
});
test("map camera and instance survive data refresh; explicit selection focuses stored coordinate without animation", () => {
  const data = monitoringFixture(),
    onSelect = vi.fn();
  const camera = vi.spyOn(LeafletMap.prototype, "setView");
  const { rerender } = render(
    <MonitoringMap
      rows={data.items}
      selectedId=""
      focus={null}
      onSelect={onSelect}
      now={Date.now()}
      stale={120}
      verified
    />,
  );
  const container = document.querySelector(".leaflet-container");
  camera.mockClear();
  const focus = { latitude: 13.4, longitude: 121.8, revision: 1 };
  rerender(
    <MonitoringMap
      rows={data.items}
      selectedId="QA-ONE"
      focus={focus}
      onSelect={onSelect}
      now={Date.now()}
      stale={120}
      verified
    />,
  );
  expect(camera).toHaveBeenCalledWith(
    [13.4, 121.8],
    14,
    expect.objectContaining({ animate: false }),
  );
  camera.mockClear();
  rerender(
    <MonitoringMap
      rows={structuredClone(data.items)}
      selectedId="QA-ONE"
      focus={focus}
      onSelect={onSelect}
      now={Date.now() + 1000}
      stale={120}
      verified
    />,
  );
  expect(document.querySelector(".leaflet-container")).toBe(container);
  expect(camera).not.toHaveBeenCalled();
  fireEvent.click(document.querySelector(".monitor-pin")!);
  expect(onSelect).toHaveBeenCalledWith(data.items[0]);
  expect(screen.getAllByText("OpenStreetMap").length).toBeGreaterThan(0);
});
test("connection failure preserves locations as unverified UNKNOWN and successful refresh recovers", async () => {
  respond();
  render(<LiveMonitoring onExpire={vi.fn()} />);
  await screen.findByRole("button", { name: /QA-ONE.*Fresh report/ });
  mocked.mockRejectedValueOnce(new ApiError(503, "Unavailable"));
  fireEvent.click(screen.getByRole("button", { name: "Refresh monitoring" }));
  expect((await screen.findByRole("alert")).textContent).toContain(
    "not currently verified",
  );
  expect(
    screen.getByRole("button", { name: /QA-ONE.*Unverified/ }).textContent,
  ).toContain("UNKNOWN");
  expect(document.querySelectorAll(".monitor-pin").length).toBe(1);
  fireEvent.click(screen.getByRole("button", { name: "Refresh monitoring" }));
  await screen.findByRole("button", { name: /QA-ONE.*Fresh report/ });
  expect(screen.queryByRole("alert")).toBeNull();
});
test("single-flight polling, backoff recovery, visibility resume and request cleanup", async () => {
  vi.useFakeTimers();
  let resolve!: (value: unknown) => void;
  mocked.mockImplementationOnce(
    () =>
      new Promise((r) => {
        resolve = r;
      }),
  );
  const expire = vi.fn(),
    hook = renderHook(() => useMonitoring("", expire));
  act(() => hook.result.current.refresh());
  await act(async () => {
    await vi.advanceTimersByTimeAsync(60000);
  });
  expect(mocked).toHaveBeenCalledTimes(1);
  await act(async () => resolve(monitoringFixture()));
  mocked.mockRejectedValueOnce(new ApiError(503, "Unavailable"));
  await act(async () => {
    await vi.advanceTimersByTimeAsync(30000);
  });
  expect(mocked).toHaveBeenCalledTimes(2);
  expect(hook.result.current.verified).toBe(false);
  mocked.mockResolvedValue(monitoringFixture());
  await act(async () => {
    await vi.advanceTimersByTimeAsync(59999);
  });
  expect(mocked).toHaveBeenCalledTimes(2);
  await act(async () => {
    await vi.advanceTimersByTimeAsync(1);
  });
  expect(mocked).toHaveBeenCalledTimes(3);
  expect(hook.result.current.verified).toBe(true);
  Object.defineProperty(document, "hidden", {
    configurable: true,
    value: true,
  });
  act(() => document.dispatchEvent(new Event("visibilitychange")));
  await act(async () => {
    await vi.advanceTimersByTimeAsync(90000);
  });
  expect(mocked).toHaveBeenCalledTimes(3);
  Object.defineProperty(document, "hidden", {
    configurable: true,
    value: false,
  });
  await act(async () => document.dispatchEvent(new Event("visibilitychange")));
  expect(mocked).toHaveBeenCalledTimes(4);
  const signal = mocked.mock.calls.at(-1)?.[3];
  hook.unmount();
  expect(signal?.aborted).toBe(true);
  await vi.advanceTimersByTimeAsync(300000);
  expect(mocked).toHaveBeenCalledTimes(4);
});
test("obsolete filters abort requests and expired sessions stop polling", async () => {
  mocked.mockImplementationOnce(() => new Promise(() => {}));
  const expire = vi.fn(),
    hook = renderHook(({ query }) => useMonitoring(query, expire), {
      initialProps: { query: "page=1" },
    });
  const oldSignal = mocked.mock.calls[0][3];
  mocked.mockRejectedValueOnce(new ApiError(401, "Expired"));
  hook.rerender({ query: "page=2" });
  expect(oldSignal?.aborted).toBe(true);
  await waitFor(() => expect(expire).toHaveBeenCalledOnce());
});
test("freshness expires independently of refresh; revoked and reassigned reports stay UNKNOWN; Manila time and bounded configuration", () => {
  const row = monitoringFixture().items[0],
    now = Date.now();
  expect(reportState(row, now, 120, true).status).toBe("AVAILABLE");
  expect(
    reportState(row, Date.parse(row.timestamp!) + 120000, 120, true).status,
  ).toBe("UNKNOWN");
  expect(reportState(row, now, 120, false).status).toBe("UNKNOWN");
  for (const patch of [
    { enabled: false },
    { credentialRevoked: true },
    { currentJeepneyId: "OTHER" },
  ])
    expect(
      reportState(
        { ...row, reportDevice: { ...row.reportDevice!, ...patch } },
        now,
        120,
        true,
      ).status,
    ).toBe("UNKNOWN");
  expect(manilaTime("2026-01-01T00:00:00Z")).toMatch(/8:00:00.*PHT/);
  expect(pollInterval("5")).toBe(30000);
  expect(pollInterval("60")).toBe(60000);
  expect(pollInterval("bad")).toBe(30000);
});
