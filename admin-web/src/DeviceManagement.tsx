import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { api, ApiError } from "./api";
import { Modal } from "./JeepneyManagement";
import { displayTime } from "./jeepneys";
import "./routes.css";
import "./devices.css";
type Device = {
  id: string;
  label: string | null;
  model: string | null;
  description: string | null;
  administrativeNotes: string | null;
  source: "device" | "simulated";
  legacy: boolean;
  enabled: boolean;
  jeepneyId: string | null;
  plateNumber: string | null;
  jeepneyActive: boolean | null;
  version: number;
  credentialState: string;
  validCredentials: number;
  timestamp: string | null;
  lastSeenAt: string | null;
  reportJeepneyId: string | null;
  latitude: number | null;
  longitude: number | null;
  lastReportedStatus: string | null;
  createdAt: string;
  updatedAt: string;
};
type Choice = { id: string; plateNumber: string | null; active: boolean };
type Page = {
  items: Device[];
  total: number;
  pageSize: number;
  counts: {
    total: number;
    enabled: number;
    disabled: number;
    fresh: number;
    staleOrMissing: number;
    validUntil: string | null;
  };
  updatedAt: string;
  staleAfterSeconds: number;
};
type Detail = {
  record: Device;
  events: {
    action: string;
    createdAt: string;
    jeepneyId: string | null;
    previousJeepneyId: string | null;
  }[];
  updatedAt: string;
  staleAfterSeconds: number;
};
type Action = "assignment" | "state" | "provision" | "rotate" | "revoke";
const fields = [
  ["label", "Device label", 120],
  ["model", "Hardware model", 120],
  ["description", "Description", 500],
  ["administrativeNotes", "Administrative notes", 2000],
] as const;
export function deviceReport(d: Device, now: number, stale: number) {
  const t = Date.parse(d.timestamp ?? ""),
    s = Date.parse(d.lastSeenAt ?? "");
  const fresh =
    t <= now && s <= now && now - t < stale * 1000 && now - s < stale * 1000;
  return {
    freshness: !d.timestamp
      ? "No reports"
      : fresh
        ? "Fresh report"
        : "Stale report",
    status:
      fresh &&
      d.enabled &&
      d.validCredentials &&
      d.source === "device" &&
      d.jeepneyActive &&
      d.jeepneyId === d.reportJeepneyId
        ? d.lastReportedStatus
        : "UNKNOWN",
  };
}
function errorMessage(e: unknown, write = false) {
  if (e instanceof ApiError) {
    const messages: Record<string, string> = {
      DEVICE_ID_EXISTS: "This device identifier is already registered.",
      ASSIGNMENT_CONFLICT:
        "Another enabled device is assigned to that jeepney. Explicitly disable or unassign it first.",
      RECORD_CHANGED:
        "This device changed. Your entries are preserved. Close and reopen the latest record before saving.",
      JEEPNEY_INELIGIBLE:
        "Choose an active real jeepney or leave the device unassigned.",
      DEVICE_NOT_READY:
        "Enable the device and assign an active real jeepney before provisioning.",
      ALREADY_PROVISIONED:
        "A credential already exists. Use Rotate credentials to replace it.",
      TEST_RECORD_READ_ONLY:
        "SIMULATED registrations are read-only here. Use the existing simulator tools.",
      DEVICE_WRITE_RATE_LIMITED:
        "Too many device changes. Wait a minute before retrying.",
    };
    if (write && (e.status === 0 || e.status >= 500))
      return "Outcome unconfirmed. Check the device before retrying. If a token was lost, rotate again; it cannot be retrieved.";
    if (e.code === "INVALID_DEVICE_INPUT")
      return e.fields.map((f) => f.field + ": " + f.message).join(" ");
    return messages[e.code] ?? e.message;
  }
  return "Request failed. Please retry.";
}
export function DeviceManagement({ onExpire }: { onExpire: () => void }) {
  const [filter, setFilter] = useState({
      search: "",
      reporting: "all",
      assignment: "all",
      state: "all",
      page: 1,
    }),
    [search, setSearch] = useState("");
  const [data, setData] = useState<Page | null>(null),
    [detail, setDetail] = useState<Detail | null>(null),
    [choices, setChoices] = useState<Choice[]>([]),
    [choiceError, setChoiceError] = useState("");
  const [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false),
    [saving, setSaving] = useState(false),
    [revision, setRevision] = useState(0),
    [choiceRevision, setChoiceRevision] = useState(0);
  const [panel, setPanel] = useState<
      "create" | "edit" | "details" | "action" | "secret" | null
    >(null),
    [action, setAction] = useState<Action>("state"),
    [assignment, setAssignment] = useState(""),
    [secret, setSecret] = useState<{ token: string; jeepneyId: string } | null>(
      null,
    );
  const [tick, setTick] = useState(performance.now());
  const snapshot = useRef({ server: 0, started: 0 }),
    detailClock = useRef({ server: 0, started: 0 });
  const generation = useRef(0),
    pending = useRef(false),
    alive = useRef(true);
  const refresh = () => setRevision((v) => v + 1);
  function fail(e: unknown, write = false) {
    setError(errorMessage(e, write));
    if (e instanceof ApiError && e.status === 401) onExpire();
  }
  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
      generation.current++;
    };
  }, []);
  useEffect(() => {
    let cancelled = false;
    const started = performance.now();
    setBusy(true);
    setData(null);
    setError("");
    api<Page>(
      "/devices?" +
        new URLSearchParams({ ...filter, page: String(filter.page) }),
    )
      .then((v) => {
        if (!cancelled) {
          snapshot.current = { server: Date.parse(v.updatedAt), started };
          setData(v);
          setTick(performance.now());
        }
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
  useEffect(() => {
    let cancelled = false;
    setChoiceError("");
    api<Choice[]>("/device-jeepney-options")
      .then((v) => {
        if (!cancelled) setChoices(v);
      })
      .catch((e) => {
        if (!cancelled) {
          setChoiceError(errorMessage(e));
          if (e instanceof ApiError && e.status === 401) onExpire();
        }
      });
    return () => {
      cancelled = true;
    };
  }, [choiceRevision, onExpire]);
  useEffect(() => {
    const timer = setInterval(() => setTick(performance.now()), 1000);
    const poll = setInterval(() => {
      if (!document.hidden && !panel) setRevision((v) => v + 1);
    }, 30000);
    return () => {
      clearInterval(timer);
      clearInterval(poll);
    };
  }, [panel]);
  const now =
      snapshot.current.server + Math.max(0, tick - snapshot.current.started),
    detailNow =
      detailClock.current.server +
      Math.max(0, tick - detailClock.current.started);
  const countsCurrent =
    data &&
    (!data.counts.validUntil || now < Date.parse(data.counts.validUntil));
  function close() {
    generation.current++;
    setBusy(false);
    setPanel(null);
    setDetail(null);
    setSecret(null);
    setError("");
    refresh();
  }
  async function open(id: string) {
    const seq = ++generation.current;
    setBusy(true);
    setError("");
    const started = performance.now();
    try {
      const result = await api<Detail>("/devices/" + encodeURIComponent(id));
      if (alive.current && generation.current === seq) {
        detailClock.current = { server: Date.parse(result.updatedAt), started };
        setDetail(result);
        setTick(performance.now());
        setPanel("details");
      }
    } catch (e) {
      if (alive.current && generation.current === seq) fail(e);
    } finally {
      if (alive.current && generation.current === seq) setBusy(false);
    }
  }
  function selectAction(a: Action) {
    if (!detail) return;
    setAction(a);
    setAssignment(detail.record.jeepneyId ?? "");
    setError("");
    setPanel("action");
    if (a === "assignment") setChoiceRevision((v) => v + 1);
  }
  async function perform() {
    if (!detail || pending.current) return;
    pending.current = true;
    setSaving(true);
    setError("");
    const body = {
      expectedVersion: detail.record.version,
      ...(action === "state"
        ? { enabled: !detail.record.enabled }
        : action === "assignment"
          ? { jeepneyId: assignment || null }
          : {}),
    };
    try {
      const result = await api<{ token?: string; jeepneyId?: string }>(
        "/devices/" + encodeURIComponent(detail.record.id) + "/" + action,
        body,
      );
      if (!alive.current) return;
      if (result.token && result.jeepneyId) {
        setSecret({ token: result.token, jeepneyId: result.jeepneyId });
        setPanel("secret");
      } else {
        close();
        setNotice("Device change saved. Historical reports are preserved.");
      }
    } catch (e) {
      if (alive.current) fail(e, true);
    } finally {
      pending.current = false;
      if (alive.current) setSaving(false);
    }
  }
  return (
    <section className="vehicle-management">
      <div className="overview-heading">
        <div className="page-heading">
          <span className="eyebrow">DEVICE ADMINISTRATION</span>
          <h1>IoT Device Management</h1>
          <p>
            Manage registrations and access. Enabled does not mean connected.
          </p>
        </div>
        <button
          className="button primary"
          disabled={busy}
          onClick={() => {
            setPanel("create");
            setDetail(null);
            setError("");
            setNotice("");
            setChoiceRevision((v) => v + 1);
          }}
        >
          + Add Device
        </button>
      </div>
      <div className="device-summary">
        {[
          ["Registered devices", data?.counts.total],
          ["Enabled", data?.counts.enabled],
          ["Disabled", data?.counts.disabled],
          ["Fresh reports", countsCurrent ? data?.counts.fresh : null],
          [
            "Stale / missing reports",
            countsCurrent ? data?.counts.staleOrMissing : null,
          ],
        ].map(([label, value]) => (
          <div className="panel" key={label}>
            <strong>{value ?? "—"}</strong>
            <span>{label}</span>
          </div>
        ))}
      </div>
      <p className="field-help">
        Real registrations only; excludes SIMULATED. Legacy registrations group
        old vehicle-bound credentials and do not verify physical hardware.
        Reporting counts are independent of access state.
      </p>
      {notice && (
        <p role="status" className="notice">
          {notice}
        </p>
      )}
      {error && !panel && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <form
        className="vehicle-filters device-filters"
        onSubmit={(e) => {
          e.preventDefault();
          setFilter((v) => ({ ...v, search: search.trim(), page: 1 }));
        }}
      >
        <div>
          <label htmlFor="device-search">Search devices</label>
          <input
            id="device-search"
            value={search}
            maxLength={120}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <button className="button secondary">Search</button>
        {(
          [
            ["reporting", "Reporting", ["all", "fresh", "stale", "missing"]],
            ["assignment", "Assignment", ["all", "assigned", "unassigned"]],
            ["state", "Access state", ["all", "enabled", "disabled"]],
          ] as const
        ).map(([key, label, options]) => (
          <div key={key}>
            <label htmlFor={"device-" + key}>{label}</label>
            <select
              id={"device-" + key}
              value={filter[key]}
              onChange={(e) =>
                setFilter((v) => ({ ...v, [key]: e.target.value, page: 1 }))
              }
            >
              {options.map((v) => (
                <option key={v} value={v}>
                  {v}
                </option>
              ))}
            </select>
          </div>
        ))}
      </form>
      <button className="button secondary" disabled={busy} onClick={refresh}>
        Refresh devices
      </button>
      {busy ? (
        <p role="status">Loading device records…</p>
      ) : !data ? (
        <p className="empty-state">
          Device records unavailable. Refresh to retry.
        </p>
      ) : (
        <>
          <div className="route-grid device-grid">
            {data.items.map((d) => {
              const report = deviceReport(d, now, data.staleAfterSeconds);
              return (
                <article className="panel route-card" key={d.id}>
                  <h2>{d.id}</h2>
                  {d.source === "simulated" && (
                    <span className="vehicle-demo">
                      DEMO / SIMULATED · read-only
                    </span>
                  )}
                  {d.legacy && <p>Legacy vehicle-bound registration</p>}
                  <p>
                    {d.label || "Label not recorded"} ·{" "}
                    {d.model || "Model not recorded"}
                  </p>
                  <p>
                    {d.jeepneyId ?? "Unassigned"}
                    {d.plateNumber ? " · " + d.plateNumber : ""}
                  </p>
                  <p>
                    {d.enabled ? "Enabled" : "Disabled"} · {d.credentialState}
                  </p>
                  <p>
                    {report.freshness} · Last measured{" "}
                    {displayTime(d.timestamp)}
                  </p>
                  <button
                    className="button secondary"
                    onClick={() => void open(d.id)}
                  >
                    View {d.id}
                  </button>
                </article>
              );
            })}
          </div>
          {!data.items.length && (
            <p className="empty-state">
              No devices found. Register a device or adjust filters.
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
              {Math.max(1, Math.ceil(data.total / data.pageSize))}
            </span>
            <button
              className="button secondary"
              disabled={filter.page * data.pageSize >= data.total}
              onClick={() => setFilter((v) => ({ ...v, page: v.page + 1 }))}
            >
              Next
            </button>
          </div>
        </>
      )}
      {(panel === "create" || panel === "edit") && (
        <DeviceEditor
          row={panel === "edit" ? (detail?.record ?? null) : null}
          choices={choices}
          choiceError={choiceError}
          retry={() => setChoiceRevision((v) => v + 1)}
          close={close}
          onExpire={onExpire}
          saved={() => {
            close();
            setNotice(
              "Device registration saved. No reports or credentials were generated.",
            );
          }}
        />
      )}
      {panel === "details" && detail && (
        <Modal title={"Device " + detail.record.id} close={close}>
          <div className="vehicle-modal-body">
            <p>
              Snapshot retrieved {displayTime(detail.updatedAt)}. Refresh for
              later activity.
            </p>
            {error && (
              <p role="alert" className="error">
                {error}
              </p>
            )}
            <DeviceDetails
              row={detail.record}
              now={detailNow}
              stale={detail.staleAfterSeconds}
              unavailable={!!error || busy}
            />
            <div className="vehicle-form-actions">
              <button
                className="button secondary"
                disabled={busy}
                onClick={() => void open(detail.record.id)}
              >
                Refresh details
              </button>
              <button className="button secondary" onClick={close}>
                Close details
              </button>
            </div>
            {detail.record.source === "device" && (
              <details className="device-actions">
                <summary>Manage device</summary>
                <button
                  className="button secondary"
                  disabled={busy}
                  onClick={() => setPanel("edit")}
                >
                  Edit metadata
                </button>
                {(
                  [
                    "assignment",
                    "state",
                    "provision",
                    "rotate",
                    "revoke",
                  ] as const
                ).map((a) => (
                  <button
                    className="button secondary"
                    key={a}
                    disabled={busy}
                    onClick={() => selectAction(a)}
                  >
                    {a === "assignment"
                      ? "Change assignment"
                      : a === "state"
                        ? detail.record.enabled
                          ? "Disable device"
                          : "Enable device"
                        : a === "provision"
                          ? "Provision credentials"
                          : a === "rotate"
                            ? "Rotate credentials"
                            : "Revoke credentials"}
                  </button>
                ))}
              </details>
            )}
            <h3>Recent administrative events</h3>
            {detail.events.length ? (
              detail.events.map((e, i) => (
                <p className="field-help" key={i}>
                  {e.action} · {displayTime(e.createdAt)} ·{" "}
                  {e.previousJeepneyId ?? "Unassigned"} →{" "}
                  {e.jeepneyId ?? "Unassigned"}
                </p>
              ))
            ) : (
              <p>
                No admin events recorded. Legacy CLI operations predate this
                audit trail.
              </p>
            )}
          </div>
        </Modal>
      )}
      {panel === "action" && detail && (
        <Modal title="Confirm device change" busy={saving} close={close}>
          <div className="vehicle-modal-body">
            <h3>{detail.record.id}</h3>
            <p>
              {action === "assignment"
                ? "Changing or removing the assignment revokes every old credential. Old GPS remains attached to its original vehicle. Provision a new credential after assigning the replacement vehicle."
                : action === "state"
                  ? detail.record.enabled
                    ? "Disabling rejects device updates and preserves history. Existing credentials remain stored; enabling can restore their access."
                    : "Enabling restores access for valid credentials. It does not mean the device is reporting."
                  : action === "revoke"
                    ? "Revoke all current credentials. Access stays blocked until you intentionally provision another key. History is retained."
                    : "Generate a random bearer token using the existing device protocol. Rotation replaces all old keys atomically. The new token is shown once; lost tokens cannot be recovered. Transfer it only to the assigned hardware through a secure local process."}
            </p>
            {action === "assignment" && (
              <div className="vehicle-form-grid">
                <VehicleChoice
                  value={assignment}
                  change={setAssignment}
                  choices={choices}
                  current={detail.record.jeepneyId}
                  disabled={saving}
                />
                {choiceError && <p role="alert">{choiceError}</p>}
                <button
                  type="button"
                  onClick={() => setChoiceRevision((v) => v + 1)}
                >
                  Reload jeepney choices
                </button>
              </div>
            )}
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
                onClick={() => void perform()}
              >
                {saving
                  ? "Saving…"
                  : action === "rotate" || action === "provision"
                    ? "Generate one-time credential"
                    : "Confirm change"}
              </button>
            </div>
          </div>
        </Modal>
      )}
      {panel === "secret" && secret && (
        <Modal title="One-time device credential" close={close}>
          <div className="vehicle-modal-body">
            <p>
              Saved successfully for jeepney {secret.jeepneyId}. Copy this token
              directly to your secure provisioning process. Closing this dialog
              clears it from the interface. It cannot be displayed again; rotate
              if lost.
            </p>
            <label htmlFor="device-token">Bearer token — secret</label>
            <textarea
              id="device-token"
              className="device-token"
              readOnly
              autoComplete="off"
              spellCheck={false}
              value={secret.token}
            />
            <p>
              Never put this in Flutter, Git, screenshots, chat, logs or browser
              storage.
            </p>
            <button className="button primary" onClick={close}>
              I have saved it securely — close
            </button>
          </div>
        </Modal>
      )}
    </section>
  );
}
function VehicleChoice({
  value,
  change,
  choices,
  current,
  disabled,
}: {
  value: string;
  change: (v: string) => void;
  choices: Choice[];
  current?: string | null;
  disabled: boolean;
}) {
  return (
    <div className="vehicle-form-wide">
      <label htmlFor="device-vehicle">Assigned jeepney</label>
      <select
        id="device-vehicle"
        value={value}
        disabled={disabled}
        onChange={(e) => change(e.target.value)}
      >
        <option value="">Unassigned</option>
        {current && !choices.some((v) => v.id === current) && (
          <option value={current}>{current} · existing assignment</option>
        )}
        {choices.map((v) => (
          <option key={v.id} value={v.id} disabled={!v.active}>
            {v.id} · {v.plateNumber || "No plate"}
            {v.active ? "" : " · inactive"}
          </option>
        ))}
      </select>
    </div>
  );
}
function DeviceEditor({
  row,
  choices,
  choiceError,
  retry,
  close,
  saved,
  onExpire,
}: {
  row: Device | null;
  choices: Choice[];
  choiceError: string;
  retry: () => void;
  close: () => void;
  saved: () => void;
  onExpire: () => void;
}) {
  const [form, setForm] = useState(() => ({
      id: row?.id ?? "",
      label: row?.label ?? "",
      model: row?.model ?? "",
      description: row?.description ?? "",
      administrativeNotes: row?.administrativeNotes ?? "",
      enabled: row?.enabled ?? true,
      jeepneyId: row?.jeepneyId ?? "",
    })),
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
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (pending.current) return;
    setError("");
    if (
      !/^[A-Z0-9][A-Z0-9_-]{0,95}$/.test(form.id) ||
      (!row &&
        ["LEGACY-", "SIM-", "DEMO-"].some((prefix) =>
          form.id.startsWith(prefix),
        ))
    ) {
      setError(
        "Use 1–96 uppercase letters, digits, hyphens or underscores. LEGACY-, SIM- and DEMO- are reserved.",
      );
      return;
    }
    if (
      fields.some(
        ([key, , max]) =>
          form[key].trim().length > max ||
          /[\u0000-\u001f\u007f]/u.test(form[key]),
      )
    ) {
      setError("Review field lengths and remove control characters.");
      return;
    }
    pending.current = true;
    setBusy(true);
    const values = Object.fromEntries(
      fields.map(([key]) => [key, form[key].trim() || null]),
    );
    try {
      await api(
        row ? "/devices/" + encodeURIComponent(row.id) : "/devices",
        row
          ? { ...values, expectedVersion: row.version }
          : {
              ...values,
              id: form.id,
              enabled: form.enabled,
              jeepneyId: form.jeepneyId || null,
            },
        row ? "PUT" : "POST",
      );
      if (alive.current) saved();
    } catch (e) {
      if (alive.current) {
        setError(errorMessage(e, true));
        if (e instanceof ApiError && e.status === 401) onExpire();
      }
    } finally {
      pending.current = false;
      if (alive.current) setBusy(false);
    }
  }
  return (
    <Modal
      title={row ? "Edit device metadata" : "Register device"}
      busy={busy}
      close={close}
    >
      <form className="vehicle-modal-body" onSubmit={submit} noValidate>
        <p>
          Registration creates no GPS report or credential. Enabled is an access
          setting, not a connection indicator.
        </p>
        <div className="vehicle-form-grid">
          <div className="vehicle-form-wide">
            <label htmlFor="new-device-id">Device identifier *</label>
            <input
              id="new-device-id"
              maxLength={96}
              disabled={busy}
              readOnly={!!row}
              value={form.id}
              onChange={(e) =>
                setForm((v) => ({ ...v, id: e.target.value.toUpperCase() }))
              }
            />
          </div>
          {fields.map(([key, label, max]) => (
            <div className="vehicle-form-wide" key={key}>
              <label htmlFor={"new-device-" + key}>{label} (optional)</label>
              <input
                id={"new-device-" + key}
                maxLength={max}
                disabled={busy}
                value={form[key]}
                onChange={(e) =>
                  setForm((v) => ({ ...v, [key]: e.target.value }))
                }
              />
            </div>
          ))}
          {!row && (
            <>
              <div>
                <label htmlFor="new-device-enabled">Administrative state</label>
                <select
                  id="new-device-enabled"
                  disabled={busy}
                  value={String(form.enabled)}
                  onChange={(e) =>
                    setForm((v) => ({
                      ...v,
                      enabled: e.target.value === "true",
                    }))
                  }
                >
                  <option value="true">Enabled</option>
                  <option value="false">Disabled</option>
                </select>
              </div>
              <VehicleChoice
                value={form.jeepneyId}
                change={(id) => setForm((v) => ({ ...v, jeepneyId: id }))}
                choices={choices}
                disabled={busy}
              />
              {choiceError && <p role="alert">{choiceError}</p>}
              <button type="button" onClick={retry}>
                Reload jeepney choices
              </button>
            </>
          )}
        </div>
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        <div className="vehicle-form-actions">
          <button
            type="button"
            disabled={busy}
            className="button secondary"
            onClick={close}
          >
            Cancel
          </button>
          <button className="button primary" disabled={busy}>
            {busy ? "Saving…" : row ? "Save metadata" : "Register Device"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
function DeviceDetails({
  row: d,
  now,
  stale,
  unavailable,
}: {
  row: Device;
  now: number;
  stale: number;
  unavailable: boolean;
}) {
  const report = deviceReport(d, now, stale);
  return (
    <dl className="vehicle-details">
      {Object.entries({
        Label: d.label ?? "Not recorded",
        Model: d.model ?? "Not recorded",
        Description: d.description ?? "Not recorded",
        "Administrative notes": d.administrativeNotes ?? "None",
        Source:
          d.source === "simulated"
            ? "DEMO / SIMULATED"
            : "Device registration — hardware unverified",
        "Registration origin": d.legacy
          ? "Legacy vehicle-bound credentials"
          : "Admin registered",
        Assignment: d.jeepneyId ?? "Unassigned",
        Access: d.enabled ? "Enabled" : "Disabled",
        Credentials: d.credentialState,
        "Reporting freshness": report.freshness,
        "Location measured": displayTime(d.timestamp),
        "Last accepted communication": displayTime(d.lastSeenAt),
        "Last report vehicle": d.reportJeepneyId ?? "No report",
        "Last reported coordinates": d.timestamp
          ? `${d.latitude}, ${d.longitude}`
          : "No report",
        "Current driver report": unavailable
          ? "UNKNOWN"
          : (report.status ?? "UNKNOWN"),
        "Historical driver report":
          (d.lastReportedStatus ?? "No report") + " — not current availability",
        Created: displayTime(d.createdAt),
        "Record updated": displayTime(d.updatedAt),
      }).map(([label, value]) => (
        <div key={label}>
          <dt>{label}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  );
}
