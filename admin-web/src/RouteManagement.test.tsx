// @vitest-environment jsdom
import { beforeEach, afterEach, test, expect, vi } from "vitest";
import { render, screen, within, cleanup } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { api, ApiError } from "./api";
import { RouteManagement } from "./RouteManagement";
vi.mock("./api", async (original) => ({
  ...(await original<typeof import("./api")>()),
  api: vi.fn(),
}));
const mock = vi.mocked(api);
const row = {
  id: "00000000-0000-4000-8000-000000000001",
  origin: "Boac",
  destination: "Gasan",
  active: true,
  version: 1,
  assignedCount: 0,
  displayName: null,
  description: null,
  originTerminal: null,
  destinationTerminal: null,
  boardingNotes: null,
  administrativeNotes: null,
  operationsVerified: false,
  updatedAt: new Date().toISOString(),
};
beforeEach(() => {
  mock.mockReset();
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function () {
    this.removeAttribute("open");
  };
  mock.mockImplementation(async (path) =>
    path.includes("?")
      ? {
          items: [row],
          total: 1,
          page: 1,
          pageSize: 20,
          counts: { total: 1, active: 1, inactive: 0 },
        }
      : row,
  );
});
afterEach(cleanup);
test("registration validates direction and retains input after duplicate failure", async () => {
  render(<RouteManagement onExpire={vi.fn()} />);
  await screen.findByText("Boac → Gasan");
  await userEvent.click(screen.getByText("+ Add Route"));
  const d = screen.getByRole("dialog");
  await userEvent.click(within(d).getByText("Register Route"));
  expect(await within(d).findByRole("alert")).toBeTruthy();
  await userEvent.selectOptions(
    within(d).getByLabelText("Origin municipality *"),
    "Boac",
  );
  await userEvent.selectOptions(
    within(d).getByLabelText("Destination municipality *"),
    "Gasan",
  );
  await userEvent.type(
    within(d).getByLabelText("Origin terminal (optional)"),
    "Verified by owner",
  );
  mock.mockRejectedValueOnce(new ApiError(409, "Conflict", "ROUTE_EXISTS"));
  await userEvent.click(within(d).getByText("Register Route"));
  expect((await within(d).findByRole("alert")).textContent).toContain(
    "already registered",
  );
  expect(
    (within(d).getByLabelText("Origin terminal (optional)") as HTMLInputElement)
      .value,
  ).toBe("Verified by owner");
  expect(mock).toHaveBeenLastCalledWith(
    "/routes",
    expect.objectContaining({
      operationsVerified: false,
      origin: "Boac",
      destination: "Gasan",
    }),
    "POST",
  );
});
test("editing locks direction and requires reconfirmation after operational changes", async () => {
  render(<RouteManagement onExpire={vi.fn()} />);
  await screen.findByText("Boac → Gasan");
  await userEvent.click(screen.getByText("Edit"));
  const d = screen.getByRole("dialog");
  expect(
    (within(d).getByLabelText("Origin municipality *") as HTMLSelectElement)
      .disabled,
  ).toBe(true);
  await userEvent.click(within(d).getByRole("checkbox"));
  await userEvent.type(
    within(d).getByLabelText("Boarding-practice information (optional)"),
    "Verified boarding note",
  );
  expect((within(d).getByRole("checkbox") as HTMLInputElement).checked).toBe(
    false,
  );
  mock.mockRejectedValueOnce(new ApiError(409, "Conflict", "RECORD_CHANGED"));
  await userEvent.click(within(d).getByText("Save Changes"));
  expect((await within(d).findByRole("alert")).textContent).toContain(
    "record changed",
  );
});
test("deactivation requires confirmation and outage offers refresh", async () => {
  render(<RouteManagement onExpire={vi.fn()} />);
  await screen.findByText("Boac → Gasan");
  await userEvent.click(screen.getByText("Deactivate"));
  await userEvent.click(screen.getByText("Cancel"));
  expect(mock.mock.calls.some((c) => c[0].endsWith("/activation"))).toBe(false);
  await screen.findByText("Boac → Gasan");
  await userEvent.click(screen.getByText("Deactivate"));
  await userEvent.click(screen.getByText("Confirm deactivation"));
  await screen.findByText(/Route status saved/);
  mock.mockRejectedValueOnce(new ApiError(503, "Service unavailable"));
  await userEvent.click(screen.getByText("Refresh routes"));
  await screen.findByRole("alert");
  expect(screen.queryByText("Boac → Gasan")).toBeNull();
});
