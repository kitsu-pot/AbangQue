import { useCallback, useEffect, useRef, useState } from "react";
import type { FormEvent, ReactNode } from "react";
import { api, ApiError } from "./api";
import {
  currentReport,
  direction,
  displayTime,
  validateVehicle,
  vehicleError,
} from "./jeepneys";
import type {
  Jeepney,
  JeepneyPage,
  RouteOption,
  VehicleForm,
} from "./jeepneys";
import "./jeepneys.css";

function Modal({
  title,
  close,
  busy = false,
  children,
}: {
  title: string;
  close: () => void;
  busy?: boolean;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);
  return (
    <dialog
      className="vehicle-modal"
      ref={ref}
      aria-labelledby="vehicle-modal-title"
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) close();
      }}
    >
      <div className="vehicle-modal-header">
        <h2 id="vehicle-modal-title">{title}</h2>
        <button
          type="button"
          className="icon-button"
          aria-label="Close dialog"
          disabled={busy}
          onClick={close}
        >
          ×
        </button>
      </div>
      {children}
    </dialog>
  );
}
function Source({ row }: { row: Jeepney }) {
  return row.source === "device" ? null : (
    <span className="vehicle-demo">
      {row.source === "simulated" ? "DEMO / SIMULATED" : "DEMO"}
    </span>
  );
}
export function JeepneyManagement({ onExpire }: { onExpire: () => void }) {
  const [search, setSearch] = useState(""),
    [filter, setFilter] = useState({
      search: "",
      status: "all",
      routeId: "all",
      page: 1,
    });
  const [data, setData] = useState<JeepneyPage | null>(null),
    [routes, setRoutes] = useState<RouteOption[]>([]);
  const [routeError, setRouteError] = useState(""),
    [error, setError] = useState(""),
    [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false),
    [revision, setRevision] = useState(0),
    [routeRevision, setRouteRevision] = useState(0);
  const [selected, setSelected] = useState<Jeepney | null>(null),
    [panel, setPanel] = useState<
      "create" | "edit" | "details" | "activation" | null
    >(null);
  const [loadingRecord, setLoadingRecord] = useState(false),
    [saving, setSaving] = useState(false),
    [actionError, setActionError] = useState("");
  const [tick, setTick] = useState(performance.now());
  const snapshot = useRef({ server: Date.now(), started: performance.now() });
  const detailsSnapshot = useRef({
    server: Date.now(),
    started: performance.now(),
    staleSeconds: 120,
  });
  const generation = useRef(0),
    alive = useRef(true),
    loading = useRef(false);
  const refresh = () => setRevision((v) => v + 1);
  const handleError = useCallback(
    (e: unknown) => {
      if (e instanceof ApiError && e.status === 401) onExpire();
    },
    [onExpire],
  );
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      generation.current++;
    };
  }, []);
  useEffect(() => {
    let cancelled = false;
    setRouteError("");
    api<RouteOption[]>("/route-options")
      .then((r) => {
        if (!cancelled) setRoutes(r);
      })
      .catch((e) => {
        if (!cancelled) {
          setRoutes([]);
          setRouteError(vehicleError(e));
          handleError(e);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [routeRevision, handleError]);
  useEffect(() => {
    let cancelled = false;
    const started = performance.now();
    setBusy(true);
    setData(null);
    setError("");
    const query = new URLSearchParams({
      ...filter,
      page: String(filter.page),
      pageSize: "20",
    });
    api<JeepneyPage>("/jeepneys?" + query)
      .then((result) => {
        if (cancelled) return;
        snapshot.current = { server: Date.parse(result.updatedAt), started };
        setTick(performance.now());
        setData(result);
      })
      .catch((e) => {
        if (!cancelled) {
          setError(vehicleError(e));
          handleError(e);
        }
      })
      .finally(() => {
        if (!cancelled) setBusy(false);
      });
    return () => {
      cancelled = true;
    };
  }, [filter, revision, handleError]);
  useEffect(() => {
    const tickTimer = setInterval(() => setTick(performance.now()), 1000);
    const poll = setInterval(() => {
      if (!document.hidden && !loading.current) setRevision((v) => v + 1);
    }, 30000);
    const focus = () => {
      setTick(performance.now());
      if (!loading.current) setRevision((v) => v + 1);
    };
    window.addEventListener("focus", focus);
    return () => {
      clearInterval(tickTimer);
      clearInterval(poll);
      window.removeEventListener("focus", focus);
    };
  }, []);
  useEffect(() => {
    loading.current = busy || saving;
  }, [busy, saving]);
  const now =
    snapshot.current.server + Math.max(0, tick - snapshot.current.started);
  const detailsNow =
    detailsSnapshot.current.server +
    Math.max(0, tick - detailsSnapshot.current.started);
  async function openRecord(
    id: string,
    next: "edit" | "details" | "activation",
  ) {
    const request = ++generation.current;
    if (next === "edit") setRouteRevision((v) => v + 1);
    setLoadingRecord(true);
    setError("");
    setActionError("");
    const started = performance.now();
    try {
      const result = await api<{
        record: Jeepney;
        updatedAt: string;
        staleAfterSeconds: number;
      }>("/jeepneys/" + encodeURIComponent(id));
      if (!alive.current || generation.current !== request) return;
      detailsSnapshot.current = {
        server: Date.parse(result.updatedAt),
        started,
        staleSeconds: result.staleAfterSeconds,
      };
      setSelected(result.record);
      setTick(performance.now());
      setPanel(next);
    } catch (e) {
      if (alive.current && generation.current === request) {
        setError(vehicleError(e));
        handleError(e);
      }
    } finally {
      if (alive.current && generation.current === request)
        setLoadingRecord(false);
    }
  }
  function close() {
    generation.current++;
    setLoadingRecord(false);
    setPanel(null);
    setSelected(null);
    setActionError("");
    refresh();
  }
  function saved() {
    setPanel(null);
    setSelected(null);
    setNotice("Jeepney record saved.");
    refresh();
    setRouteRevision((v) => v + 1);
  }
  async function activate() {
    if (!selected || saving) return;
    setSaving(true);
    setActionError("");
    try {
      await api(
        "/jeepneys/" + encodeURIComponent(selected.id) + "/activation",
        { active: !selected.active, expectedVersion: selected.version },
      );
      if (alive.current) {
        setPanel(null);
        setNotice(
          selected.active
            ? "Jeepney deactivated. History and device relationships are preserved."
            : "Jeepney reactivated. Report freshness remains unchanged.",
        );
        refresh();
      }
    } catch (e) {
      if (alive.current) {
        setActionError(vehicleError(e, true));
        handleError(e);
      }
    } finally {
      if (alive.current) setSaving(false);
    }
  }
  const actions = (row: Jeepney) => (
    <div className="vehicle-actions">
      <button
        className="button secondary"
        disabled={loadingRecord}
        onClick={() => void openRecord(row.id, "details")}
        aria-label={"View " + row.id}
      >
        Details
      </button>
      {row.source === "device" && (
        <>
          <button
            className="button secondary"
            disabled={loadingRecord}
            onClick={() => void openRecord(row.id, "edit")}
            aria-label={"Edit " + row.id}
          >
            Edit
          </button>
          <button
            className="vehicle-text-button"
            disabled={loadingRecord}
            onClick={() => void openRecord(row.id, "activation")}
            aria-label={(row.active ? "Deactivate " : "Activate ") + row.id}
          >
            {row.active ? "Deactivate" : "Activate"}
          </button>
        </>
      )}
    </div>
  );
  return (
    <section className="vehicle-management">
      <div className="overview-heading">
        <div className="page-heading">
          <span className="eyebrow">FLEET REGISTRATION</span>
          <h1>Jeepney Management</h1>
          <p>
            Manage vehicle records, route assignments and passenger-service
            eligibility.
          </p>
        </div>
        <button
          className="button primary"
          onClick={() => {
            generation.current++;
            setLoadingRecord(false);
            setRouteRevision((v) => v + 1);
            setPanel("create");
            setNotice("");
          }}
        >
          + Add Jeepney
        </button>
      </div>
      {notice && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}
      <div className="vehicle-summary">
        <strong>{data ? data.registeredTotal : "—"}</strong>
        <span>
          registered jeepneys{" "}
          <small>
            Excludes DEMO / SIMULATED records. Active and inactive registrations
            included.
          </small>
        </span>
        <button className="button secondary" disabled={busy} onClick={refresh}>
          {busy ? "Refreshing…" : "Refresh list"}
        </button>
      </div>
      <form
        className="vehicle-filters"
        onSubmit={(e) => {
          e.preventDefault();
          setFilter((f) => ({ ...f, search: search.trim(), page: 1 }));
        }}
      >
        <div>
          <label htmlFor="vehicle-search">Search records</label>
          <input
            id="vehicle-search"
            type="search"
            maxLength={120}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Identifier, plate or display name"
          />
        </div>
        <button className="button secondary" type="submit">
          Search
        </button>
        <div>
          <label htmlFor="vehicle-status">Record status</label>
          <select
            id="vehicle-status"
            value={filter.status}
            onChange={(e) =>
              setFilter((f) => ({ ...f, status: e.target.value, page: 1 }))
            }
          >
            <option value="all">All records</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
          </select>
        </div>
        <div>
          <label htmlFor="vehicle-route">Registered route</label>
          <select
            id="vehicle-route"
            value={filter.routeId}
            onChange={(e) =>
              setFilter((f) => ({ ...f, routeId: e.target.value, page: 1 }))
            }
          >
            <option value="all">All routes</option>
            <option value="unassigned">Unassigned</option>
            {routes.map((r) => (
              <option value={r.id} key={r.id}>
                {direction(r)} · {r.id.slice(0, 8)}
              </option>
            ))}
          </select>
        </div>
      </form>
      {routeError && (
        <p className="error" role="alert">
          Route choices unavailable. {routeError}{" "}
          <button onClick={() => setRouteRevision((v) => v + 1)}>
            Retry routes
          </button>
        </p>
      )}
      {error && (
        <p className="error" role="alert">
          {error} <button onClick={refresh}>Retry list</button>
        </p>
      )}
      {loadingRecord && (
        <p role="status" className="notice">
          Loading the latest vehicle record…
        </p>
      )}
      <div className="panel">
        <div className="panel-heading vehicle-list-heading">
          <h2>Vehicle registry</h2>
          <span className="small-label">
            {data ? `${data.total} matching records` : "Database records"}
          </span>
        </div>
        {busy ? (
          <div className="empty-state" role="status">
            Loading registered jeepneys…
          </div>
        ) : !data ? (
          <div className="empty-state">
            Records are unavailable. Please retry.
          </div>
        ) : data.items.length === 0 ? (
          <div className="empty-state">
            <h3>No jeepneys found</h3>
            <p>
              {data.total
                ? "This page is empty. Go back to the previous page."
                : "Register a vehicle or adjust your search and filters."}
            </p>
          </div>
        ) : (
          <>
            <div
              className="vehicle-desktop-table table-scroll"
              tabIndex={0}
              role="region"
              aria-label="Jeepney records"
            >
              <table>
                <thead>
                  <tr>
                    <th>Jeepney / plate</th>
                    <th>Registered route</th>
                    <th>Record status</th>
                    <th>GPS report</th>
                    <th>Current driver report</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {data.items.map((row) => {
                    const report = currentReport(
                      row,
                      now,
                      data.staleAfterSeconds,
                    );
                    return (
                      <tr key={row.id}>
                        <td>
                          <strong>{row.id}</strong>
                          <small>{row.name}</small>
                          <small>
                            {row.plateNumber ?? "Plate not recorded"}
                          </small>
                          <Source row={row} />
                        </td>
                        <td>{direction(row.route)}</td>
                        <td>
                          <span
                            className={
                              "status-pill " + (row.active ? "" : "neutral")
                            }
                          >
                            {row.active ? "Active" : "Inactive"}
                          </span>
                        </td>
                        <td>
                          <strong>{report.freshness}</strong>
                          <small>{displayTime(row.timestamp)}</small>
                        </td>
                        <td>
                          <span className="status-pill neutral">
                            {report.status}
                          </span>
                        </td>
                        <td>{actions(row)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            <div className="vehicle-mobile-cards">
              {data.items.map((row) => {
                const report = currentReport(row, now, data.staleAfterSeconds);
                return (
                  <article key={row.id}>
                    <div className="vehicle-card-heading">
                      <h3>{row.id}</h3>
                      <span className="status-pill neutral">
                        {row.active ? "Active" : "Inactive"}
                      </span>
                    </div>
                    <p>{row.name}</p>
                    <Source row={row} />
                    <dl>
                      <dt>Plate</dt>
                      <dd>{row.plateNumber ?? "Not recorded"}</dd>
                      <dt>Route</dt>
                      <dd>{direction(row.route)}</dd>
                      <dt>GPS freshness</dt>
                      <dd>{report.freshness}</dd>
                      <dt>Driver report</dt>
                      <dd>{report.status}</dd>
                      <dt>Location measured</dt>
                      <dd>{displayTime(row.timestamp)}</dd>
                    </dl>
                    {actions(row)}
                  </article>
                );
              })}
            </div>
          </>
        )}
        <div className="vehicle-pagination">
          <button
            className="button secondary"
            disabled={busy || filter.page === 1}
            onClick={() => setFilter((f) => ({ ...f, page: f.page - 1 }))}
          >
            Previous
          </button>
          <span>
            Page {filter.page}
            {data
              ? ` of ${Math.max(1, Math.ceil(data.total / data.pageSize))}`
              : ""}
          </span>
          <button
            className="button secondary"
            disabled={
              busy || !data || filter.page * data.pageSize >= data.total
            }
            onClick={() => setFilter((f) => ({ ...f, page: f.page + 1 }))}
          >
            Next
          </button>
        </div>
      </div>
      <p className="vehicle-guidance">
        Active / Inactive controls registration eligibility. FULL / AVAILABLE is
        a separate driver report from the device, never an administrative
        setting. DEMO / SIMULATED records are read-only here.
      </p>
      {(panel === "create" || panel === "edit") && (
        <VehicleEditor
          row={panel === "edit" ? selected : null}
          routes={routes}
          routeError={routeError}
          retryRoutes={() => setRouteRevision((v) => v + 1)}
          close={close}
          saved={saved}
          onExpire={onExpire}
        />
      )}
      {panel === "activation" && selected && (
        <Modal
          title={
            (selected.active ? "Deactivate " : "Activate ") + selected.id + "?"
          }
          close={close}
          busy={saving}
        >
          <div className="vehicle-modal-body">
            <p>
              {selected.active
                ? "This vehicle will be removed from current passenger API listings. Its GPS history and device relationships will be preserved. Previously cached passenger information cannot update until a successful refresh."
                : "This restores passenger-list eligibility. A registered route assignment is needed for route results, and old GPS reports remain stale. This does not mark the vehicle AVAILABLE."}
            </p>
            {actionError && (
              <p className="error" role="alert">
                {actionError}
              </p>
            )}
            <div className="vehicle-form-actions">
              <button
                className="button secondary"
                disabled={saving}
                onClick={close}
              >
                Cancel
              </button>
              <button
                className="button primary"
                disabled={saving}
                onClick={() => void activate()}
              >
                {saving
                  ? "Saving…"
                  : selected.active
                    ? "Confirm deactivation"
                    : "Confirm activation"}
              </button>
            </div>
          </div>
        </Modal>
      )}
      {panel === "details" && selected && (
        <Modal title={"Jeepney " + selected.id} close={close}>
          <div className="vehicle-modal-body">
            <Source row={selected} />
            <p className="field-help">
              Details snapshot:{" "}
              {displayTime(
                new Date(detailsSnapshot.current.server).toISOString(),
              )}
              . Refresh to retrieve new reports or registration changes.
            </p>
            {error && (
              <p className="error" role="alert">
                Latest data unavailable. {error}
              </p>
            )}
            <dl className="vehicle-details">
              <dt>Display name</dt>
              <dd>{selected.name}</dd>
              <dt>Record status</dt>
              <dd>{selected.active ? "Active" : "Inactive"}</dd>
              <dt>Plate</dt>
              <dd>{selected.plateNumber ?? "Not recorded"}</dd>
              <dt>Assigned route</dt>
              <dd>{direction(selected.route)}</dd>
              <dt>Description</dt>
              <dd>{selected.description || "Not recorded"}</dd>
              <dt>Administrative notes</dt>
              <dd>{selected.administrativeNotes || "None"}</dd>
              <dt>Source</dt>
              <dd>
                {selected.source === "device"
                  ? "Device record — hardware operation unverified"
                  : "DEMO / " + selected.source.toUpperCase()}
              </dd>
              <dt>Last reported position</dt>
              <dd>
                {selected.position
                  ? `${selected.position.latitude}, ${selected.position.longitude}`
                  : "No GPS report"}
              </dd>
              <dt>Location measured</dt>
              <dd>{displayTime(selected.timestamp)}</dd>
              <dt>Last communication</dt>
              <dd>{displayTime(selected.lastSeenAt)}</dd>
              <dt>GPS freshness</dt>
              <dd>
                {
                  currentReport(
                    selected,
                    detailsNow,
                    detailsSnapshot.current.staleSeconds,
                  ).freshness
                }
              </dd>
              <dt>Current driver report</dt>
              <dd>
                {error || loadingRecord
                  ? "UNKNOWN"
                  : currentReport(
                      selected,
                      detailsNow,
                      detailsSnapshot.current.staleSeconds,
                    ).status}
              </dd>
              <dt>Last reported status (historical)</dt>
              <dd>
                {selected.lastReportedStatus ?? "No report"} — not current
                availability
              </dd>
              <dt>Registered</dt>
              <dd>{displayTime(selected.createdAt)}</dd>
              <dt>Record updated</dt>
              <dd>{displayTime(selected.updatedAt)}</dd>
              <dt>ETA</dt>
              <dd>Unavailable</dd>
            </dl>
            <div className="vehicle-form-actions">
              <button className="button secondary" onClick={close}>
                Close details
              </button>
              <button
                className="button secondary"
                disabled={loadingRecord}
                onClick={() => void openRecord(selected.id, "details")}
              >
                {loadingRecord ? "Refreshing…" : "Refresh details"}
              </button>
              {selected.source === "device" && (
                <button
                  className="button primary"
                  disabled={loadingRecord}
                  onClick={() => {
                    setPanel("edit");
                    setRouteRevision((v) => v + 1);
                  }}
                >
                  Edit record
                </button>
              )}
            </div>
          </div>
        </Modal>
      )}
    </section>
  );
}

function VehicleEditor({
  row,
  routes,
  routeError,
  retryRoutes,
  close,
  saved,
  onExpire,
}: {
  row: Jeepney | null;
  routes: RouteOption[];
  routeError: string;
  retryRoutes: () => void;
  close: () => void;
  saved: () => void;
  onExpire: () => void;
}) {
  const [form, setForm] = useState<VehicleForm>(() => ({
    id: row?.id ?? "",
    name: row?.name ?? "",
    plateNumber: row?.plateNumber ?? "",
    description: row?.description ?? "",
    administrativeNotes: row?.administrativeNotes ?? "",
    routeId: row?.route?.id ?? "",
    active: row?.active ?? true,
  }));
  const [errors, setErrors] = useState<Record<string, string>>({}),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const pending = useRef(false),
    alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);
  const change = (key: keyof VehicleForm, value: string | boolean) =>
    setForm((v) => ({ ...v, [key]: value }));
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (pending.current) return;
    const invalid = validateVehicle(form);
    setErrors(invalid);
    setError("");
    if (Object.keys(invalid).length) return;
    pending.current = true;
    setBusy(true);
    const values = {
      name: form.name.trim(),
      plateNumber: form.plateNumber.trim().toUpperCase() || null,
      description: form.description.trim(),
      administrativeNotes: form.administrativeNotes.trim(),
      routeId: form.routeId || null,
    };
    try {
      await api(
        row ? "/jeepneys/" + encodeURIComponent(row.id) : "/jeepneys",
        row
          ? { ...values, expectedVersion: row.version }
          : { ...values, id: form.id, active: form.active },
        row ? "PUT" : "POST",
      );
      if (alive.current) saved();
    } catch (e) {
      if (!alive.current) return;
      setError(vehicleError(e, true));
      if (e instanceof ApiError) {
        setErrors(
          Object.fromEntries(e.fields.map((f) => [f.field, f.message])),
        );
        if (e.status === 401) onExpire();
      }
    } finally {
      pending.current = false;
      if (alive.current) setBusy(false);
    }
  }
  const control = (
    key: "id" | "name" | "plateNumber" | "description" | "administrativeNotes",
    label: string,
    max: number,
    required = false,
  ) => (
    <div
      className={
        key === "administrativeNotes" || key === "description"
          ? "vehicle-form-wide"
          : ""
      }
    >
      <label htmlFor={"form-" + key}>
        {label}
        {required ? " *" : ""}
      </label>
      <input
        id={"form-" + key}
        value={form[key]}
        maxLength={max}
        required={required}
        readOnly={key === "id" && !!row}
        disabled={busy}
        aria-invalid={!!errors[key]}
        aria-describedby={errors[key] ? "error-" + key : undefined}
        onChange={(e) =>
          change(
            key,
            key === "id" || key === "plateNumber"
              ? e.target.value.toUpperCase()
              : e.target.value,
          )
        }
      />
      {errors[key] && (
        <p id={"error-" + key} className="field-error">
          {errors[key]}
        </p>
      )}
    </div>
  );
  return (
    <Modal
      title={row ? "Edit " + row.id : "Register a jeepney"}
      close={close}
      busy={busy}
    >
      <form className="vehicle-modal-body" onSubmit={submit} noValidate>
        <p className="vehicle-form-intro">
          {row
            ? "The identifier is fixed to preserve device and GPS history. Use the separate Activate / Deactivate action to change record status."
            : "Create a registration record. No GPS report or device credential will be generated."}
        </p>
        <div className="vehicle-form-grid">
          {control("id", "Jeepney identifier", 64, true)}
          {control("name", "Vehicle display name", 120, true)}
          {control("plateNumber", "Plate number (optional)", 20)}
          {!row && (
            <div>
              <label htmlFor="form-active">Record status *</label>
              <select
                id="form-active"
                value={String(form.active)}
                disabled={busy}
                onChange={(e) => change("active", e.target.value === "true")}
              >
                <option value="true">Active</option>
                <option value="false">Inactive</option>
              </select>
            </div>
          )}
          <div className="vehicle-form-wide">
            <label htmlFor="form-routeId">Registered route (optional)</label>
            <select
              id="form-routeId"
              value={form.routeId}
              disabled={busy}
              onChange={(e) => change("routeId", e.target.value)}
            >
              <option value="">Unassigned</option>
              {row?.route && !routes.some((r) => r.id === row.route?.id) && (
                <option value={row.route.id}>
                  {direction(row.route)} · existing assignment
                </option>
              )}
              {routes.map((r) => (
                <option
                  value={r.id}
                  key={r.id}
                  disabled={!r.active && r.id !== row?.route?.id}
                >
                  {direction(r)} · {r.id.slice(0, 8)}
                </option>
              ))}
            </select>
            <p className="field-help">
              {routes.some((r) => r.active)
                ? "Choose an existing direction. Inactive routes cannot be newly assigned."
                : "No eligible routes available. You can leave this vehicle unassigned."}
            </p>
            <button
              type="button"
              className="vehicle-text-button"
              disabled={busy}
              onClick={retryRoutes}
            >
              Refresh route choices
            </button>
            {routeError && (
              <p className="field-error">
                Route choices unavailable.{" "}
                <button type="button" onClick={retryRoutes}>
                  Retry routes
                </button>
              </p>
            )}
            {errors.routeId && <p className="field-error">{errors.routeId}</p>}
          </div>
          {control("description", "Vehicle description (optional)", 500)}
          {control(
            "administrativeNotes",
            "Administrative notes (private, optional)",
            2000,
          )}
        </div>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <div className="vehicle-form-actions">
          <button
            type="button"
            className="button secondary"
            onClick={close}
            disabled={busy}
          >
            Cancel
          </button>
          <button className="button primary" disabled={busy}>
            {busy ? "Saving…" : row ? "Save Changes" : "Register Jeepney"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
