// @vitest-environment jsdom
import React from "react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import {
  cleanup,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { App } from "./App";
import { api, ApiError } from "./api";
vi.mock("./api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./api")>();
  return { ...actual, api: vi.fn() };
});
const mockApi = vi.mocked(api);
const session = {
  user: { id: "test", email: "admin@example.test", role: "ADMIN" },
  expiresAt: new Date(Date.now() + 3600000).toISOString(),
};
const empty = {
  updatedAt: new Date().toISOString(),
  staleAfterSeconds: 120,
  summary: {
    jeepneys: 0,
    routes: 0,
    devices: null,
    demoJeepneys: 0,
    fresh: 0,
    staleOrMissing: 0,
    available: 0,
    full: 0,
    validUntil: null,
  },
  recent: [],
};
beforeEach(() => {
  location.hash = "";
  mockApi.mockReset();
  HTMLDialogElement.prototype.showModal = function () {
    this.setAttribute("open", "");
  };
  HTMLDialogElement.prototype.close = function () {
    this.removeAttribute("open");
  };
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});
function authenticated() {
  mockApi.mockImplementation(async (path) =>
    path === "/session" ? session : path === "/dashboard" ? empty : undefined,
  );
}
test("deep links remain protected and login shows generic errors with password visibility", async () => {
  location.hash = "#/settings";
  mockApi.mockRejectedValue(new ApiError(401, "Session invalid"));
  render(<App />);
  const user = userEvent.setup();
  await screen.findByRole("heading", { name: "Welcome back." });
  expect(screen.queryByRole("heading", { name: "Settings" })).toBeNull();
  expect(screen.queryByText(/create.*account/i)).toBeNull();
  await user.type(screen.getByLabelText("Email address"), "admin@example.test");
  await user.type(screen.getByLabelText("Password"), "incorrect");
  await user.click(screen.getByRole("button", { name: "Show password" }));
  expect(screen.getByLabelText("Password").getAttribute("type")).toBe("text");
  await user.click(
    screen.getByRole("button", { name: /Sign in to workspace/ }),
  );
  expect((await screen.findByRole("alert")).textContent).toContain(
    "Email or password is incorrect",
  );
});
test("backend unavailable during session recovery offers retry without granting access", async () => {
  mockApi.mockRejectedValue(new ApiError(0, "Unable to reach the server."));
  render(<App />);
  await screen.findByRole("heading", { name: "Unable to connect" });
  expect(screen.queryByRole("heading", { name: "Dashboard" })).toBeNull();
  authenticated();
  await userEvent.click(
    screen.getByRole("button", { name: "Retry connection" }),
  );
  await screen.findByRole("heading", { name: "Dashboard" });
});
test("successful form login loads the protected dashboard", async () => {
  mockApi.mockRejectedValueOnce(new ApiError(401, "Not signed in"));
  render(<App />);
  await screen.findByRole("heading", { name: "Welcome back." });
  const user = userEvent.setup();
  await user.type(screen.getByLabelText("Email address"), "admin@example.test");
  await user.type(screen.getByLabelText("Password"), "test-only-password");
  mockApi.mockImplementation(async (path) =>
    path === "/login" ? session : empty,
  );
  await user.click(
    screen.getByRole("button", { name: /Sign in to workspace/ }),
  );
  await screen.findByText("No registered jeepneys yet");
});
test("dashboard displays empty database without inventing statistics and clears reports on failure", async () => {
  authenticated();
  render(<App />);
  await screen.findByText("No registered jeepneys yet");
  expect(screen.getByText("Not available")).toBeTruthy();
  mockApi.mockRejectedValue(new ApiError(503, "Server unavailable."));
  await userEvent.click(
    screen.getByRole("button", { name: "Refresh overview" }),
  );
  expect((await screen.findByRole("alert")).textContent).toContain(
    "Dashboard unavailable",
  );
  expect(screen.queryByText("No registered jeepneys yet")).toBeNull();
  expect(screen.getByText("Connection failed")).toBeTruthy();
  expect(screen.getByText("Last successful update")).toBeTruthy();
});
test("mobile navigation, sidebar collapse, planned sections and settings/logout work", async () => {
  authenticated();
  render(<App />);
  await screen.findByRole("heading", { name: "Dashboard" });
  await userEvent.click(
    screen.getByRole("button", { name: "Collapse sidebar" }),
  );
  expect(screen.getByRole("button", { name: "Expand sidebar" })).toBeTruthy();
  await userEvent.click(
    screen.getByRole("button", { name: "Open navigation" }),
  );
  const dialog = screen.getByRole("dialog");
  await userEvent.click(within(dialog).getByRole("link", { name: /Routes/ }));
  await screen.findByRole("heading", { name: "Routes, in the next phase." });
  expect(screen.queryByRole("dialog")).toBeNull();
  await userEvent.click(screen.getByRole("link", { name: "Settings" }));
  await screen.findByText(session.user.email);
  mockApi.mockRejectedValueOnce(new ApiError(0, "Network failed."));
  await userEvent.click(
    screen.getByRole("button", { name: "Sign out of workspace" }),
  );
  expect((await screen.findByRole("alert")).textContent).toContain(
    "Sign out was not confirmed",
  );
  await userEvent.click(
    screen.getByRole("button", { name: "Sign out of workspace" }),
  );
  await screen.findByRole("heading", { name: "Welcome back." });
  expect(mockApi).toHaveBeenCalledWith("/logout", {});
});
test("server session expiration returns to login and removes dashboard", async () => {
  authenticated();
  render(<App />);
  await screen.findByText("No registered jeepneys yet");
  mockApi.mockRejectedValue(new ApiError(401, "Expired"));
  await userEvent.click(
    screen.getByRole("button", { name: "Refresh overview" }),
  );
  await screen.findByRole("heading", { name: "Welcome back." });
  expect(
    screen.getByText("Your session has ended. Please sign in again."),
  ).toBeTruthy();
  expect(screen.queryByText("No registered jeepneys yet")).toBeNull();
});
test("local absolute session expiration removes protected content", async () => {
  authenticated();
  mockApi.mockResolvedValueOnce({
    ...session,
    expiresAt: new Date(Date.now() + 200).toISOString(),
  });
  render(<App />);
  await screen.findByRole("heading", { name: "Dashboard" });
  await screen.findByRole("heading", { name: "Welcome back." });
});
test("old snapshots cannot continue presenting current availability while offline", async () => {
  authenticated();
  mockApi.mockImplementation(async (path) =>
    path === "/session"
      ? session
      : {
          ...empty,
          summary: {
            ...empty.summary,
            available: 7,
            validUntil: new Date(
              Date.parse(empty.updatedAt) - 1000,
            ).toISOString(),
          },
        },
  );
  render(<App />);
  await screen.findByRole("heading", { name: "Dashboard" });
  await waitFor(() => expect(screen.queryByText("7")).toBeNull());
  expect(screen.getByText(/Refreshing report freshness/)).toBeTruthy();
});
