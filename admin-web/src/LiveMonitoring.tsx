import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ApiError } from "./api";
import { direction } from "./jeepneys";
import type { RouteOption } from "./jeepneys";
import { JeepneyManagement, Modal } from "./JeepneyManagement";
import { DeviceManagement } from "./DeviceManagement";
import { MonitoringMap } from "./MonitoringMap";
import type { MapFocus } from "./MonitoringMap";
import { manilaTime, reportState, deviceReportLabel } from "./monitoring";
import type { MonitoringRow } from "./monitoring";
import { useMonitoring } from "./useMonitoring";
import "./monitoring.css";

type Target = { kind: "jeepney" | "device"; id: string };
export function LiveMonitoring({ onExpire }: { onExpire: () => void }) {
  const [target, setTarget] = useState<Target | null>(null);
  if (target)
    return (
      <>
        <button className="button" onClick={() => setTarget(null)}>
          ← Back to monitoring
        </button>
        {target.kind === "jeepney" ? (
          <JeepneyManagement initialId={target.id} onExpire={onExpire} />
        ) : (
          <DeviceManagement initialId={target.id} onExpire={onExpire} />
        )}
      </>
    );
  return <MonitorView onExpire={onExpire} openManagement={setTarget} />;
}
function MonitorView({
  onExpire,
  openManagement,
}: {
  onExpire: () => void;
  openManagement: (v: Target) => void;
}) {
  const [filters, setFilters] = useState({
    search: "",
    routeId: "all",
    reporting: "all",
    status: "all",
    device: "all",
    page: 1,
  });
  const [search, setSearch] = useState(""),
    [selectedId, setSelectedId] = useState(""),
    [focus, setFocus] = useState<MapFocus>(null),
    [listOpen, setListOpen] = useState(true);
  const [small, setSmall] = useState(
    () =>
      typeof matchMedia === "function" &&
      matchMedia("(max-width:650px)").matches,
  );
  useEffect(() => {
    if (typeof matchMedia !== "function") return;
    const media = matchMedia("(max-width:650px)"),
      change = () => setSmall(media.matches);
    media.addEventListener("change", change);
    return () => media.removeEventListener("change", change);
  }, []);
  const [routes, setRoutes] = useState<RouteOption[]>([]),
    [routeError, setRouteError] = useState(false),
    [routeRevision, setRouteRevision] = useState(0);
  const query = useMemo(
    () =>
      new URLSearchParams({
        ...filters,
        page: String(filters.page),
        ...(selectedId ? { selectedId } : {}),
      }).toString(),
    [filters, selectedId],
  );
  const { data, error, busy, hidden, now, refresh, interval, verified } =
    useMonitoring(query, onExpire);
  useEffect(() => {
    const timer = setTimeout(
      () =>
        setFilters((v) =>
          v.search === search ? v : { ...v, search, page: 1 },
        ),
      300,
    );
    return () => clearTimeout(timer);
  }, [search]);
  useEffect(() => {
    let active = true,
      pending = false,
      last = 0;
    const controller = new AbortController();
    async function load() {
      if (pending || document.hidden || Date.now() - last < 300000) return;
      pending = true;
      try {
        const values = await api<RouteOption[]>(
          "/route-options",
          undefined,
          "POST",
          controller.signal,
        );
        if (active) {
          setRoutes(values);
          setRouteError(false);
          last = Date.now();
        }
      } catch (e) {
        if (active) {
          setRouteError(true);
          if (e instanceof ApiError && e.status === 401) onExpire();
        }
      } finally {
        pending = false;
      }
    }
    void load();
    const timer = setInterval(() => void load(), 60000);
    const visible = () => void load();
    document.addEventListener("visibilitychange", visible);
    return () => {
      active = false;
      controller.abort();
      clearInterval(timer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [onExpire, routeRevision]);
  const select = useCallback((row: MonitoringRow) => {
    setSelectedId(row.id);
    if (row.position)
      setFocus((v) => ({ ...row.position!, revision: (v?.revision ?? 0) + 1 }));
  }, []);
  const selected =
    data?.selected?.id === selectedId
      ? data.selected
      : data?.items.find((r) => r.id === selectedId);
  const rows = useMemo(() => {
    const items = data?.items ?? [];
    return selected && !items.some((r) => r.id === selected.id)
      ? [...items, selected]
      : items;
  }, [data, selected]);
  const countsCurrent =
    verified &&
    data &&
    (!data.counts.validUntil || now < Date.parse(data.counts.validUntil));
  function filter(name: keyof typeof filters, value: string) {
    setFilters((v) => ({ ...v, [name]: value, page: 1 }));
  }
  const stats = data?.counts;
  return (
    <div className="monitoring">
      <header className="monitor-heading">
        <div>
          <span className="eyebrow">MARINDUQUE · REPORTING OVERVIEW</span>
          <h1>Live Monitoring</h1>
          <p>
            Latest accepted device reports. A marker does not confirm movement
            or connectivity.
          </p>
        </div>
        <button className="button primary" disabled={busy} onClick={refresh}>
          {busy ? "Refreshing…" : "Refresh monitoring"}
        </button>
      </header>
      <div className="monitor-refresh">
        <span className={"monitor-auto " + (error ? "warning" : "")}>
          {hidden
            ? "Auto refresh paused"
            : error
              ? "Retry backoff active"
              : `Auto refresh · ${interval / 1000}s`}
        </span>
        <span>
          Last successful refresh:{" "}
          <strong>
            {data ? manilaTime(data.updatedAt) : "Not yet loaded"}
          </strong>
        </span>
      </div>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      {!verified && data && !error && (
        <p role="status" className="monitor-notice">
          {hidden
            ? "Tab hidden. Reports are not currently verified."
            : "Updating this view. Displayed records are from the previous successful snapshot."}
        </p>
      )}
      <section
        className="monitor-stats"
        aria-label="Real-source registration summary"
      >
        {[
          ["Registered jeepneys", stats?.jeepneys],
          [
            "Devices with fresh reports",
            countsCurrent ? stats?.fresh : undefined,
          ],
          [
            "Devices with stale reports",
            countsCurrent ? stats?.stale : undefined,
          ],
          ["Devices with no reports", stats?.missing],
          ["Disabled or revoked devices", stats?.restricted],
        ].map(([label, value]) => (
          <div key={label}>
            <span>{label}</span>
            <strong>{value ?? "—"}</strong>
          </div>
        ))}
      </section>
      <p className="monitor-scope">
        Counts cover all real-source registrations, including unassigned
        devices. Reporting freshness and access restrictions can overlap.{" "}
        {stats?.excludedTestVehicles ?? "—"} DEMO / SIMULATED vehicles excluded.
      </p>
      <details className="monitor-filter-disclosure" open={!small}>
        <summary>Filter jeepney reports</summary>
        <section className="monitor-filters" aria-label="Monitoring filters">
          <label className="monitor-search">
            Search jeepneys
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Identifier or plate number"
              maxLength={120}
            />
          </label>
          <label>
            Registered direction
            <select
              value={filters.routeId}
              onChange={(e) => filter("routeId", e.target.value)}
            >
              <option value="all">All routes</option>
              <option value="unassigned">Unassigned route</option>
              {routes.map((r) => (
                <option key={r.id} value={r.id}>
                  {direction(r)}
                </option>
              ))}
            </select>
          </label>
          <label>
            GPS reporting
            <select
              value={filters.reporting}
              onChange={(e) => filter("reporting", e.target.value)}
            >
              <option value="all">All reports</option>
              <option value="fresh">Fresh reports</option>
              <option value="stale">Stale reports</option>
              <option value="missing">No reports</option>
            </select>
          </label>
          <label>
            Vehicle status
            <select
              value={filters.status}
              onChange={(e) => filter("status", e.target.value)}
            >
              <option value="all">All vehicles</option>
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
            </select>
          </label>
          <label>
            Assigned device
            <select
              value={filters.device}
              onChange={(e) => filter("device", e.target.value)}
            >
              <option value="all">All device states</option>
              <option value="enabled">Enabled</option>
              <option value="disabled">Disabled</option>
              <option value="revoked">Revoked credentials</option>
              <option value="unprovisioned">Not provisioned</option>
              <option value="unassigned">No assigned device</option>
            </select>
          </label>
        </section>
      </details>
      {routeError && (
        <p role="status" className="monitor-notice">
          Route choices could not be verified.{" "}
          <button onClick={() => setRouteRevision((v) => v + 1)}>
            Retry route choices
          </button>
        </p>
      )}
      <div className="monitor-workspace">
        <div className="monitor-map-column">
          <MonitoringMap
            rows={rows}
            selectedId={selectedId}
            focus={focus}
            onSelect={select}
            now={now}
            stale={data?.staleAfterSeconds ?? 120}
            verified={verified}
          />
          <div className="monitor-legend">
            <span>
              <i className="fresh" />
              Fresh report
            </span>
            <span>
              <i className="stale" />
              Stale report
            </span>
            <span>
              <i className="restricted" />
              Historical / restricted
            </span>
            <span>
              <i className="unverified" />
              Unverified
            </span>
          </div>
          {selected &&
            (small ? (
              <Modal
                title="Jeepney report details"
                close={() => setSelectedId("")}
              >
                <SelectedDetails
                  row={selected}
                  now={now}
                  stale={data!.staleAfterSeconds}
                  verified={verified}
                  onClose={() => setSelectedId("")}
                  openManagement={openManagement}
                />
              </Modal>
            ) : (
              <SelectedDetails
                row={selected}
                now={now}
                stale={data!.staleAfterSeconds}
                verified={verified}
                onClose={() => setSelectedId("")}
                openManagement={openManagement}
              />
            ))}
          {selectedId && !selected && !busy && verified && (
            <p role="status" className="monitor-notice">
              The selected jeepney is no longer available in monitoring.
            </p>
          )}
        </div>
        <aside className="monitor-list-panel">
          <button
            className="monitor-list-toggle"
            onClick={() => setListOpen(!listOpen)}
            aria-expanded={listOpen}
          >
            Jeepney reports{" "}
            <span>
              {data?.total ?? "—"} vehicles {listOpen ? "−" : "+"}
            </span>
          </button>
          {listOpen && (
            <>
              <p className="monitor-list-note">
                Map shows this page
                {selected && !data?.items.some((r) => r.id === selectedId)
                  ? " plus your selected jeepney"
                  : ""}
                . Select a report to inspect it.
              </p>
              {!data && (
                <p className="monitor-list-note" role="status">
                  {busy
                    ? "Loading registered jeepneys…"
                    : "Reports unavailable. Use Refresh monitoring to retry."}
                </p>
              )}
              {data?.items.length === 0 && (
                <p className="monitor-list-note">
                  {stats?.jeepneys === 0
                    ? "No real-source jeepneys registered yet."
                    : "No jeepneys match these filters."}
                </p>
              )}
              <div className="monitor-list">
                {data?.items.map((row) => {
                  const state = reportState(
                    row,
                    now,
                    data.staleAfterSeconds,
                    verified,
                  );
                  return (
                    <button
                      key={row.id}
                      className={
                        "monitor-row " +
                        (selectedId === row.id ? "selected" : "")
                      }
                      aria-pressed={selectedId === row.id}
                      onClick={() => select(row)}
                    >
                      <span className="monitor-row-top">
                        <strong>{row.id}</strong>
                        <span className={"monitor-badge " + state.tone}>
                          {state.label}
                        </span>
                      </span>
                      <span>
                        {row.plateNumber ?? "No plate recorded"} ·{" "}
                        {row.active ? "Active vehicle" : "Inactive vehicle"}
                      </span>
                      <span>{direction(row.route)}</span>
                      <span>
                        Device:{" "}
                        {row.devices
                          .map(
                            (d) =>
                              `${d.id} (${d.enabled ? "enabled" : "disabled"} · ${d.credentialState})`,
                          )
                          .join(", ") || "Unassigned"}
                      </span>
                      <small>GPS: {manilaTime(row.timestamp)}</small>
                      <span>
                        Driver status: <b>{state.status}</b>
                      </span>
                    </button>
                  );
                })}
              </div>
              {data && (
                <div className="monitor-pagination">
                  <button
                    className="button"
                    disabled={busy || data.page <= 1}
                    onClick={() =>
                      setFilters((v) => ({ ...v, page: data.page - 1 }))
                    }
                  >
                    Previous
                  </button>
                  <span>
                    {data.page} /{" "}
                    {Math.max(1, Math.ceil(data.total / data.pageSize))}
                  </span>
                  <button
                    className="button"
                    disabled={busy || data.page * data.pageSize >= data.total}
                    onClick={() =>
                      setFilters((v) => ({ ...v, page: data.page + 1 }))
                    }
                  >
                    Next
                  </button>
                </div>
              )}
            </>
          )}
        </aside>
      </div>
      <p className="monitor-scope">
        Driver status is manually reported, not measured occupancy or a boarding
        guarantee. ETA unavailable. Map tiles load from OpenStreetMap; your IP
        address and viewed area are shared with that service.
      </p>
    </div>
  );
}
function SelectedDetails({
  row,
  now,
  stale,
  verified,
  onClose,
  openManagement,
}: {
  row: MonitoringRow;
  now: number;
  stale: number;
  verified: boolean;
  onClose: () => void;
  openManagement: (v: Target) => void;
}) {
  const state = reportState(row, now, stale, verified);
  return (
    <section
      className="monitor-detail"
      aria-label={`Selected jeepney ${row.id}`}
    >
      <header>
        <div>
          <span className="eyebrow">SELECTED JEEPNEY · DEVICE RECORD</span>
          <h2>{row.id}</h2>
          <p>{row.name}</p>
        </div>
        <button
          className="button"
          onClick={onClose}
          aria-label="Close jeepney details"
        >
          Close
        </button>
      </header>
      <p className={"monitor-notice " + state.tone}>
        {!row.timestamp
          ? "No GPS reports received yet."
          : !verified
            ? "Connection or view not verified. Preserved last-known information only."
            : state.historical
              ? "Last known location. The report is stale, restricted or belongs to a previous assignment."
              : "Latest accepted GPS report. Current movement and connectivity are not established."}
      </p>
      <div className="monitor-detail-grid">
        <div>
          <h3>Jeepney & assignment</h3>
          <dl>
            <dt>Plate number</dt>
            <dd>{row.plateNumber ?? "Not recorded"}</dd>
            <dt>Registered direction</dt>
            <dd>{direction(row.route)}</dd>
            <dt>Vehicle administration</dt>
            <dd>{row.active ? "Active" : "Inactive"}</dd>
            <dt>Current assigned devices</dt>
            <dd>
              {row.devices.length
                ? row.devices.map((d) => (
                    <div key={d.id}>
                      <button
                        className="monitor-link"
                        onClick={() =>
                          openManagement({ kind: "device", id: d.id })
                        }
                      >
                        {d.id}
                      </button>{" "}
                      · {d.enabled ? "Enabled" : "Disabled"} ·{" "}
                      {d.credentialState}
                      {d.legacy ? " · Legacy registration" : ""}
                      <small>
                        {deviceReportLabel(
                          d.timestamp,
                          d.lastSeenAt,
                          now,
                          stale,
                          verified,
                        )}
                        <br />
                        Device measurement: {manilaTime(d.timestamp)}
                        <br />
                        Device communication: {manilaTime(d.lastSeenAt)}
                        <br />
                        These device times may belong to a prior assignment.
                      </small>
                    </div>
                  ))
                : "No assigned device"}
            </dd>
          </dl>
          <button
            className="monitor-link"
            onClick={() => openManagement({ kind: "jeepney", id: row.id })}
          >
            Open Jeepney Management →
          </button>
        </div>
        <div>
          <h3>GPS & reporting</h3>
          <dl>
            <dt>Report freshness</dt>
            <dd>{state.label}</dd>
            <dt>Last reported coordinates</dt>
            <dd>
              {row.position
                ? `${row.position.latitude}, ${row.position.longitude}`
                : row.coordinateState === "INVALID"
                  ? "Invalid coordinates — no map marker"
                  : "No coordinates"}
            </dd>
            <dt>Coordinate validation</dt>
            <dd>
              {row.coordinateState === "VALID"
                ? "Within geographic bounds; GPS accuracy unavailable"
                : row.coordinateState}
            </dd>
            <dt>Original GPS measurement</dt>
            <dd>{manilaTime(row.timestamp)}</dd>
            <dt>That report accepted</dt>
            <dd>{manilaTime(row.reportReceivedAt)}</dd>
            <dt>Latest vehicle communication</dt>
            <dd>{manilaTime(row.lastSeenAt)}</dd>
            <dt>Original reporting device</dt>
            <dd>
              {row.reportDevice ? (
                <>
                  <button
                    className="monitor-link"
                    onClick={() =>
                      openManagement({
                        kind: "device",
                        id: row.reportDevice!.id,
                      })
                    }
                  >
                    {row.reportDevice.id}
                  </button>{" "}
                  · {row.reportDevice.enabled ? "Enabled" : "Disabled"} ·{" "}
                  {row.reportDevice.credentialRevoked
                    ? "Report credential revoked"
                    : "Report credential not revoked"}
                  <small>
                    Currently assigned to:{" "}
                    {row.reportDevice.currentJeepneyId ?? "Unassigned"}
                  </small>
                </>
              ) : (
                "No reporting device"
              )}
            </dd>
          </dl>
        </div>
        <div>
          <h3>Driver-reported availability</h3>
          <strong className={"monitor-badge " + state.tone}>
            {state.status}
          </strong>
          <p>Last driver report: {row.lastReportedStatus ?? "No report"}</p>
          <p className="monitor-scope">
            Status measured: {manilaTime(row.timestamp)}. Historical FULL /
            AVAILABLE does not establish current availability.
          </p>
        </div>
      </div>
    </section>
  );
}
