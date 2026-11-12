import { afterEach, expect, test, vi } from "vitest";
import { api, ApiError } from "./api";
afterEach(() => vi.unstubAllGlobals());
test("browser requests use cookies, CSRF header, no bearer tokens, no redirects or caching", async () => {
  const fetcher = vi
    .fn()
    .mockResolvedValue(
      new Response(JSON.stringify({ data: { ok: true } }), { status: 200 }),
    );
  vi.stubGlobal("fetch", fetcher);
  expect(
    await api("/login", { email: "test@example.test", password: "test-only" }),
  ).toEqual({ ok: true });
  const [url, options] = fetcher.mock.calls[0];
  expect(url).toBe("/api/admin/login");
  expect(options.credentials).toBe("include");
  expect(options.redirect).toBe("error");
  expect(options.cache).toBe("no-store");
  expect(options.headers).toEqual({
    "Content-Type": "application/json",
    "X-AbangQue-Admin": "1",
  });
  expect(options.signal).toBeInstanceOf(AbortSignal);
});
test("network failures, expired sessions, rate limits and malformed responses are actionable errors", async () => {
  const fetcher = vi.fn();
  vi.stubGlobal("fetch", fetcher);
  fetcher.mockRejectedValueOnce(new Error("Internal network details"));
  await expect(api("/session")).rejects.toThrow("Unable to reach the server");
  for (const status of [401, 429, 503]) {
    fetcher.mockResolvedValueOnce(new Response("", { status }));
    await expect(api("/session")).rejects.toMatchObject({ status });
  }
  fetcher.mockResolvedValueOnce(new Response("not json"));
  await expect(api("/dashboard")).rejects.toBeInstanceOf(ApiError);
  fetcher.mockResolvedValueOnce(new Response(null, { status: 204 }));
  expect(await api("/logout", {})).toBeUndefined();
});
