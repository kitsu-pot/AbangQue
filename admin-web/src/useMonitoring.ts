import { useCallback, useEffect, useRef, useState } from "react";
import { api, ApiError } from "./api";
import { pollInterval } from "./monitoring";
import type { MonitoringSnapshot } from "./monitoring";

export function useMonitoring(query: string, onExpire: () => void) {
  const [snapshot, setSnapshot] = useState<{
    data: MonitoringSnapshot;
    started: number;
    wall: number;
    query: string;
  } | null>(null);
  const [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [hidden, setHidden] = useState(document.hidden);
  const [tick, setTick] = useState(performance.now());
  const action = useRef<() => void>(() => {});
  const interval = pollInterval(import.meta.env.VITE_MONITORING_POLL_SECONDS);
  useEffect(() => {
    let alive = true,
      pending = false,
      failures = 0,
      timer: ReturnType<typeof setTimeout> | undefined;
    let controller: AbortController | null = null;
    async function run() {
      clearTimeout(timer);
      if (!alive || pending || document.hidden) return;
      pending = true;
      controller = new AbortController();
      setBusy(true);
      const started = performance.now(),
        wall = Date.now();
      try {
        const data = await api<MonitoringSnapshot>(
          "/monitoring?" + query,
          undefined,
          "POST",
          controller.signal,
        );
        if (!alive) return;
        setSnapshot({ data, started, wall, query });
        setTick(performance.now());
        setError("");
        failures = 0;
      } catch (e) {
        if (!alive) return;
        if (e instanceof ApiError && e.status === 401) {
          alive = false;
          onExpire();
          return;
        }
        failures++;
        setError(
          "Connection warning. Preserved reports are not currently verified. Retrying automatically.",
        );
      } finally {
        pending = false;
        if (alive) {
          setBusy(false);
          if (!document.hidden)
            timer = setTimeout(
              () => void run(),
              Math.min(interval * 2 ** Math.min(failures, 4), 300000),
            );
        }
      }
    }
    action.current = () => void run();
    const visibility = () => {
      setHidden(document.hidden);
      setTick(performance.now());
      clearTimeout(timer);
      if (!document.hidden) void run();
    };
    document.addEventListener("visibilitychange", visibility);
    const ticker = setInterval(() => {
      if (!document.hidden) setTick(performance.now());
    }, 1000);
    void run();
    return () => {
      alive = false;
      controller?.abort();
      clearTimeout(timer);
      clearInterval(ticker);
      document.removeEventListener("visibilitychange", visibility);
    };
  }, [query, onExpire, interval]);
  const refresh = useCallback(() => action.current(), []);
  // Count request latency conservatively and continue aging through system sleep.
  const now = snapshot
    ? Date.parse(snapshot.data.updatedAt) +
      Math.max(0, tick - snapshot.started, Date.now() - snapshot.wall)
    : 0;
  return {
    data: snapshot?.data ?? null,
    error,
    busy,
    hidden,
    now,
    refresh,
    interval,
    verified: !!snapshot && snapshot.query === query && !error && !hidden,
  };
}
