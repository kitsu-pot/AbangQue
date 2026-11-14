import { useEffect, useRef, useState } from "react";
import { api, ApiError } from "./api";
import { Modal, JeepneyManagement } from "./JeepneyManagement";
import { currentReport, displayTime } from "./jeepneys";
import type { JeepneyPage } from "./jeepneys";
import "./routes.css";
export const municipalities = [
  "Boac",
  "Mogpog",
  "Gasan",
  "Buenavista",
  "Santa Cruz",
  "Torrijos",
];
type Metadata = {
  displayName: string | null;
  description: string | null;
  originTerminal: string | null;
  destinationTerminal: string | null;
  boardingNotes: string | null;
  administrativeNotes: string | null;
  operationsVerified: boolean;
};
type Route = Metadata & {
  id: string;
  origin: string;
  destination: string;
  active: boolean;
  version: number;
  assignedCount: number;
  updatedAt: string;
};
type Page = {
  items: Route[];
  total: number;
  counts: { total: number; active: number; inactive: number };
  page: number;
  pageSize: number;
};
const fields: [keyof Omit<Metadata, "operationsVerified">, string, number][] = [
  ["displayName", "Display name", 120],
  ["description", "Description (private)", 1000],
  ["originTerminal", "Origin terminal", 200],
  ["destinationTerminal", "Destination terminal", 200],
  ["boardingNotes", "Boarding-practice information", 1000],
  ["administrativeNotes", "Administrative notes (private)", 2000],
];
function message(e: unknown, write = false) {
  if (e instanceof ApiError) {
    if (e.code === "ROUTE_EXISTS")
      return "This direction is already registered. Find the existing record, including inactive routes.";
    if (e.code === "RECORD_CHANGED")
      return "This record changed. Your entries are preserved. Close and reopen the latest record before saving.";
    if (e.code === "INVALID_ROUTE_INPUT")
      return e.fields.map((f) => f.field + ": " + f.message).join(" ");
    if (e.code === "ADMIN_WRITE_RATE_LIMITED")
      return "Too many changes. Please wait a minute.";
    if (write && (e.status === 0 || e.status >= 500))
      return "Save outcome unconfirmed. Your entries are preserved; check the record before retrying.";
    return e.message;
  }
  return "Request failed. Please retry.";
}
export function RouteManagement({ onExpire }: { onExpire: () => void }) {
  const [filter, setFilter] = useState({
    search: "",
    municipality: "all",
    status: "all",
    page: 1,
  });
  const [search, setSearch] = useState(""),
    [page, setPage] = useState<Page | null>(null),
    [revision, setRevision] = useState(0);
  const [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false);
  const [panel, setPanel] = useState<
      "create" | "edit" | "details" | "activation" | null
    >(null),
    [selected, setSelected] = useState<Route | null>(null);
  const [vehicle, setVehicle] = useState<string | null>(null),
    [saving, setSaving] = useState(false);
  const generation = useRef(0),
    pending = useRef(false);
  function fail(e: unknown, write = false) {
    setError(message(e, write));
    if (e instanceof ApiError && e.status === 401) onExpire();
  }
  useEffect(() => {
    let cancelled = false;
    setBusy(true);
    setPage(null);
    setError("");
    api<Page>(
      "/routes?" +
        new URLSearchParams({ ...filter, page: String(filter.page) }),
    )
      .then((v) => {
        if (!cancelled) setPage(v);
      })
      .catch((e) => {
        if (!cancelled) fail(e);
      })
      .finally(() => {
        if (!cancelled) setBusy(false);
      });
    return () => {
      cancelled = true;
    };
  }, [filter, revision, onExpire]);
  useEffect(
    () => () => {
      generation.current++;
    },
    [],
  );
  function close() {
    generation.current++;
    setPanel(null);
    setSelected(null);
    setError("");
    setRevision((v) => v + 1);
  }
  async function open(id: string, next: "edit" | "details" | "activation") {
    const seq = ++generation.current;
    setError("");
    setBusy(true);
    try {
      const v = await api<Route>("/routes/" + id);
      if (seq === generation.current) {
        setSelected(v);
        setPanel(next);
      }
    } catch (e) {
      if (seq === generation.current) fail(e);
    } finally {
      if (seq === generation.current) setBusy(false);
    }
  }
  async function activate() {
    if (!selected || pending.current) return;
    pending.current = true;
    setSaving(true);
    try {
      await api("/routes/" + selected.id + "/activation", {
        active: !selected.active,
        expectedVersion: selected.version,
      });
      close();
      setNotice(
        "Route status saved. Passenger changes take effect after successful refresh.",
      );
    } catch (e) {
      fail(e, true);
    } finally {
      pending.current = false;
      setSaving(false);
    }
  }
  if (vehicle)
    return (
      <>
        <button className="button secondary" onClick={() => setVehicle(null)}>
          ← Back to Routes
        </button>
        <JeepneyManagement initialId={vehicle} onExpire={onExpire} />
      </>
    );
  const actions = (r: Route) => (
    <div className="vehicle-actions">
      <button
        className="button secondary"
        disabled={busy}
        onClick={() => void open(r.id, "details")}
      >
        Details
      </button>
      <button
        className="button secondary"
        disabled={busy}
        onClick={() => void open(r.id, "edit")}
      >
        Edit
      </button>
      <button
        className="vehicle-text-button"
        disabled={busy}
        onClick={() => void open(r.id, "activation")}
      >
        {r.active ? "Deactivate" : "Activate"}
      </button>
    </div>
  );
  return (
    <section className="vehicle-management">
      <div className="overview-heading">
        <div className="page-heading">
          <span className="eyebrow">REGISTERED DIRECTIONS</span>
          <h1>Route Management</h1>
          <p>
            Manage verified municipality services and their boarding
            information.
          </p>
        </div>
        <button
          className="button primary"
          disabled={busy}
          onClick={() => {
            setSelected(null);
            setPanel("create");
            setError("");
            setNotice("");
          }}
        >
          + Add Route
        </button>
      </div>
      <div className="vehicle-summary">
        <span>
          <strong>{page?.counts.total ?? "—"}</strong> registered routes
        </span>
        <span>{page?.counts.active ?? "—"} active</span>
        <span>{page?.counts.inactive ?? "—"} inactive</span>
        <button
          className="button secondary"
          disabled={busy}
          onClick={() => setRevision((v) => v + 1)}
        >
          Refresh routes
        </button>
      </div>
      {notice && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}
      {error && !panel && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <form
        className="vehicle-filters"
        onSubmit={(e) => {
          e.preventDefault();
          setFilter((v) => ({ ...v, search: search.trim(), page: 1 }));
        }}
      >
        <div>
          <label htmlFor="route-search">Search routes</label>
          <input
            id="route-search"
            maxLength={120}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <button className="button secondary">Search</button>
        <div>
          <label htmlFor="route-municipality">Municipality</label>
          <select
            id="route-municipality"
            value={filter.municipality}
            onChange={(e) =>
              setFilter((v) => ({
                ...v,
                municipality: e.target.value,
                page: 1,
              }))
            }
          >
            <option value="all">All municipalities</option>
            {municipalities.map((m) => (
              <option key={m}>{m}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="route-status">Route status</label>
          <select
            id="route-status"
            value={filter.status}
            onChange={(e) =>
              setFilter((v) => ({ ...v, status: e.target.value, page: 1 }))
            }
          >
            <option value="all">All records</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
          </select>
        </div>
      </form>
      {busy ? (
        <p role="status">Loading routes…</p>
      ) : !page ? (
        <p className="empty-state">
          Routes unavailable. Use Refresh routes to retry.
        </p>
      ) : (
        <>
          <div className="route-grid">
            {page.items.map((r) => (
              <article className="panel route-card" key={r.id}>
                <span className="eyebrow">
                  {r.active ? "Active" : "Inactive"}
                </span>
                <h2>
                  {r.origin} → {r.destination}
                </h2>
                <p>{r.displayName || "Registered direction"}</p>
                <small>{r.id}</small>
                <p>{r.assignedCount} assigned jeepneys (vehicles)</p>
                <p>
                  {r.operationsVerified
                    ? "Verified operational information recorded"
                    : "No confirmed operational information"}
                </p>
                {actions(r)}
              </article>
            ))}
          </div>
          {!page.items.length && (
            <p className="empty-state">
              No routes found. Register a verified service or adjust the
              filters.
            </p>
          )}
          <div className="vehicle-pagination">
            <button
              className="button secondary"
              disabled={filter.page === 1}
              onClick={() => setFilter((v) => ({ ...v, page: v.page - 1 }))}
            >
              Previous
            </button>
            <span>
              Page {filter.page} of{" "}
              {Math.max(1, Math.ceil(page.total / page.pageSize))}
            </span>
            <button
              className="button secondary"
              disabled={filter.page * page.pageSize >= page.total}
              onClick={() => setFilter((v) => ({ ...v, page: v.page + 1 }))}
            >
              Next
            </button>
          </div>
        </>
      )}
      {(panel === "create" || panel === "edit") && (
        <RouteEditor
          row={selected}
          close={close}
          onExpire={onExpire}
          saved={() => {
            close();
            setNotice(
              "Route saved. No reverse direction or vehicle report was created.",
            );
          }}
        />
      )}
      {panel === "activation" && selected && (
        <Modal
          title={(selected.active ? "Deactivate" : "Activate") + " route?"}
          close={close}
          busy={saving}
        >
          <div className="vehicle-modal-body">
            <p>
              {selected.origin} → {selected.destination}
            </p>
            <p>
              {selected.assignedCount} assigned vehicles will remain assigned.
              Deactivation removes this direction from passenger selection and
              makes saved favorites unavailable after refresh. History is
              preserved. Reactivation does not change GPS freshness or driver
              status.
            </p>
            {error && (
              <p className="error" role="alert">
                {error}
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
                  : "Confirm " +
                    (selected.active ? "deactivation" : "activation")}
              </button>
            </div>
          </div>
        </Modal>
      )}
      {panel === "details" && selected && (
        <Modal
          title={selected.origin + " → " + selected.destination}
          close={close}
        >
          <div className="vehicle-modal-body">
            <p>
              {selected.active ? "Active" : "Inactive"} · Updated{" "}
              {displayTime(selected.updatedAt)}
            </p>
            <p>
              {selected.operationsVerified
                ? "Operational fields confirmed by an administrator"
                : "Operational fields are unverified and hidden from passengers"}
            </p>
            <dl className="vehicle-details">
              {fields.map(([key, label]) => (
                <div key={key}>
                  <dt>{label}</dt>
                  <dd>{selected[key] || "Not recorded"}</dd>
                </div>
              ))}
            </dl>
            <Assigned
              id={selected.id}
              onExpire={onExpire}
              view={(id) => {
                generation.current++;
                setPanel(null);
                setVehicle(id);
              }}
            />
          </div>
        </Modal>
      )}
    </section>
  );
}
function RouteEditor({
  row,
  close,
  saved,
  onExpire,
}: {
  row: Route | null;
  close: () => void;
  saved: () => void;
  onExpire: () => void;
}) {
  const [form, setForm] = useState(() => ({
    origin: row?.origin ?? "",
    destination: row?.destination ?? "",
    active: row?.active ?? true,
    displayName: row?.displayName ?? "",
    description: row?.description ?? "",
    originTerminal: row?.originTerminal ?? "",
    destinationTerminal: row?.destinationTerminal ?? "",
    boardingNotes: row?.boardingNotes ?? "",
    administrativeNotes: row?.administrativeNotes ?? "",
    operationsVerified: row?.operationsVerified ?? false,
  }));
  const [error, setError] = useState(""),
    [busy, setBusy] = useState(false);
  const pending = useRef(false),
    alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (pending.current) return;
    setError("");
    if (
      !municipalities.includes(form.origin) ||
      !municipalities.includes(form.destination) ||
      form.origin === form.destination
    ) {
      setError("Select distinct origin and destination municipalities.");
      return;
    }
    if (
      fields.some(
        ([key, , max]) =>
          form[key].trim().length > max ||
          /[\u0000-\u001f\u007f]/u.test(form[key]),
      )
    ) {
      setError(
        "Check field lengths and remove line breaks/control characters.",
      );
      return;
    }
    pending.current = true;
    setBusy(true);
    const metadata = {
      ...Object.fromEntries(
        fields.map(([key]) => [key, form[key].trim() || null]),
      ),
      operationsVerified: form.operationsVerified,
    };
    try {
      await api(
        row ? "/routes/" + row.id : "/routes",
        row
          ? { ...metadata, expectedVersion: row.version }
          : {
              ...metadata,
              origin: form.origin,
              destination: form.destination,
              active: form.active,
            },
        row ? "PUT" : "POST",
      );
      if (alive.current) saved();
    } catch (e) {
      if (alive.current) {
        setError(message(e, true));
        if (e instanceof ApiError && e.status === 401) onExpire();
      }
    } finally {
      pending.current = false;
      if (alive.current) setBusy(false);
    }
  }
  return (
    <Modal
      title={row ? "Edit route" : "Register a verified route"}
      close={close}
      busy={busy}
    >
      <form className="vehicle-modal-body" onSubmit={submit}>
        <p>
          Register only verified services. Directions are permanent; reverse
          services require separate registration. Terminal fields stay private
          unless explicitly confirmed below.
        </p>
        <div className="vehicle-form-grid">
          {(["origin", "destination"] as const).map((key) => (
            <div key={key}>
              <label htmlFor={"route-" + key}>
                {key === "origin" ? "Origin" : "Destination"} municipality *
              </label>
              <select
                id={"route-" + key}
                disabled={busy || !!row}
                value={form[key]}
                onChange={(e) =>
                  setForm((v) => ({ ...v, [key]: e.target.value }))
                }
              >
                <option value="">Select municipality</option>
                {municipalities.map((m) => (
                  <option key={m}>{m}</option>
                ))}
              </select>
            </div>
          ))}
          {!row && (
            <div>
              <label htmlFor="new-route-status">Registration status</label>
              <select
                id="new-route-status"
                disabled={busy}
                value={String(form.active)}
                onChange={(e) =>
                  setForm((v) => ({ ...v, active: e.target.value === "true" }))
                }
              >
                <option value="true">Active</option>
                <option value="false">Inactive</option>
              </select>
            </div>
          )}
          {fields.map(([key, label, max]) => (
            <div className="vehicle-form-wide" key={key}>
              <label htmlFor={"route-" + key}>{label} (optional)</label>
              <input
                id={"route-" + key}
                disabled={busy}
                maxLength={max}
                value={form[key]}
                onChange={(e) =>
                  setForm((v) => ({
                    ...v,
                    [key]: e.target.value,
                    operationsVerified: [
                      "originTerminal",
                      "destinationTerminal",
                      "boardingNotes",
                    ].includes(key)
                      ? false
                      : v.operationsVerified,
                  }))
                }
              />
            </div>
          ))}
        </div>
        <label className="route-verification">
          <input
            type="checkbox"
            disabled={busy}
            checked={form.operationsVerified}
            onChange={(e) =>
              setForm((v) => ({ ...v, operationsVerified: e.target.checked }))
            }
          />{" "}
          I independently verified the terminal and boarding information above
          for passenger publication.
        </label>
        <p className="field-help">
          Editing operational information clears confirmation. Private
          description and administrative notes are never published.
        </p>
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <div className="vehicle-form-actions">
          <button
            type="button"
            className="button secondary"
            disabled={busy}
            onClick={close}
          >
            Cancel
          </button>
          <button className="button primary" disabled={busy}>
            {busy ? "Saving…" : row ? "Save Changes" : "Register Route"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
function Assigned({
  id,
  onExpire,
  view,
}: {
  id: string;
  onExpire: () => void;
  view: (id: string) => void;
}) {
  const [data, setData] = useState<JeepneyPage | null>(null),
    [page, setPage] = useState(1),
    [revision, setRevision] = useState(0),
    [error, setError] = useState(""),
    [tick, setTick] = useState(performance.now());
  const snapshot = useRef({ server: 0, started: 0 });
  useEffect(() => {
    let cancelled = false;
    setData(null);
    setError("");
    const started = performance.now();
    api<JeepneyPage>("/routes/" + id + "/jeepneys?page=" + page)
      .then((v) => {
        if (!cancelled) {
          snapshot.current = { server: Date.parse(v.updatedAt), started };
          setData(v);
          setTick(performance.now());
        }
      })
      .catch((e) => {
        if (!cancelled) {
          setError(message(e));
          if (e instanceof ApiError && e.status === 401) onExpire();
        }
      });
    return () => {
      cancelled = true;
    };
  }, [id, page, revision, onExpire]);
  useEffect(() => {
    const timer = setInterval(() => setTick(performance.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  return (
    <section>
      <h3>Assigned jeepneys</h3>
      <p>Snapshot of vehicle reports; refresh for new reports.</p>
      <button
        className="button secondary"
        onClick={() => setRevision((v) => v + 1)}
      >
        Refresh assigned vehicles
      </button>
      {error ? (
        <p role="alert" className="error">
          {error}
        </p>
      ) : !data ? (
        <p role="status">Loading assigned vehicles…</p>
      ) : (
        <>
          {!data.items.length && <p>No assigned jeepneys.</p>}
          {data.items.map((j) => {
            const report = currentReport(
              j,
              snapshot.current.server +
                Math.max(0, tick - snapshot.current.started),
              data.staleAfterSeconds,
            );
            return (
              <article className="route-assigned" key={j.id}>
                <strong>{j.id}</strong>
                <p>
                  {j.plateNumber || "Plate not recorded"} ·{" "}
                  {j.active ? "Active" : "Inactive"} · {report.freshness} ·{" "}
                  {report.status}
                </p>
                <p>
                  Last reported (historical):{" "}
                  {j.lastReportedStatus || "No report"} · Measured{" "}
                  {displayTime(j.timestamp)}
                </p>
                <button className="button secondary" onClick={() => view(j.id)}>
                  View {j.id}
                </button>
              </article>
            );
          })}
          <div className="vehicle-pagination">
            <button disabled={page === 1} onClick={() => setPage((v) => v - 1)}>
              Previous vehicles
            </button>
            <span>Page {page}</span>
            <button
              disabled={page * data.pageSize >= data.total}
              onClick={() => setPage((v) => v + 1)}
            >
              Next vehicles
            </button>
          </div>
        </>
      )}
    </section>
  );
}
