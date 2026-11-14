import { lazy, Suspense } from "react";
const LiveMonitoring = lazy(() =>
  import("./LiveMonitoring").then((m) => ({ default: m.LiveMonitoring })),
);
import { DeviceManagement } from "./DeviceManagement";
import { RouteManagement } from "./RouteManagement";
import { useCallback, useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { api, ApiError } from "./api";
import type { Dashboard, Session } from "./api";
import { JeepneyManagement } from "./JeepneyManagement";

const sections = [
  "Dashboard",
  "Jeepneys",
  "Routes",
  "IoT Devices",
  "Live Monitoring",
  "Settings",
] as const;
type Section = (typeof sections)[number];
const paths = [
  "dashboard",
  "jeepneys",
  "routes",
  "devices",
  "monitoring",
  "settings",
];
const symbols = [
  "overview",
  "vehicle",
  "route",
  "device",
  "signal",
  "settings",
];
function sectionFromHash(): Section {
  return (
    sections[Math.max(0, paths.indexOf(location.hash.slice(2)))] ?? "Dashboard"
  );
}
function Icon({ name = "overview" }: { name?: string }) {
  const lines: Record<string, React.ReactNode> = {
    overview: (
      <>
        <rect x="3" y="3" width="7" height="7" rx="2" />
        <rect x="14" y="3" width="7" height="7" rx="2" />
        <rect x="3" y="14" width="7" height="7" rx="2" />
        <rect x="14" y="14" width="7" height="7" rx="2" />
      </>
    ),
    vehicle: (
      <>
        <rect x="4" y="5" width="16" height="14" rx="4" />
        <path d="M4 12h16M8 19v2m8-2v2M8 8h8M7 16h1m8 0h1" />
      </>
    ),
    route: (
      <>
        <circle cx="5" cy="5" r="2" />
        <circle cx="19" cy="19" r="2" />
        <path d="M7 5h9a4 4 0 0 1 0 8H8a3 3 0 0 0 0 6h9" />
      </>
    ),
    device: (
      <>
        <rect x="6" y="4" width="12" height="16" rx="3" />
        <path d="M9 1v3m6-3v3M9 20v3m6-3v3M3 8h3m12 0h3M3 16h3m12 0h3M10 9h4v6h-4z" />
      </>
    ),
    signal: (
      <>
        <path d="M3 12h4l3-8 4 16 3-8h4" />
      </>
    ),
    settings: (
      <>
        <path d="M4 7h16M4 17h16" />
        <circle cx="9" cy="7" r="3" />
        <circle cx="16" cy="17" r="3" />
      </>
    ),
    arrow: <path d="M5 12h14m-5-5 5 5-5 5" />,
    refresh: (
      <>
        <path d="M20 7v5h-5M4 17v-5h5M6 6a8 8 0 0 1 14 6M4 12a8 8 0 0 0 14 6" />
      </>
    ),
    lock: (
      <>
        <rect x="5" y="10" width="14" height="11" rx="3" />
        <path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3" />
      </>
    ),
    menu: <path d="M4 6h16M4 12h16M4 18h16" />,
    close: <path d="m6 6 12 12M6 18 18 6" />,
  };
  return (
    <svg
      width="22"
      height="22"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.65"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {lines[name] ?? lines.overview}
    </svg>
  );
}
function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <div className="brand">
      <span className="brand-mark">
        <Icon name="vehicle" />
      </span>
      {!compact && (
        <span>
          AbangQue<small>ADMINISTRATION</small>
        </span>
      )}
    </div>
  );
}
const date = (value: string | null) =>
  value
    ? new Date(value).toLocaleString("en-PH", {
        dateStyle: "medium",
        timeStyle: "medium",
      })
    : "No report";
const message = (error: unknown) =>
  error instanceof Error
    ? error.message
    : "Something went wrong. Please retry.";

function Login({
  onLogin,
  notice,
}: {
  onLogin: (session: Session) => void;
  notice: string;
}) {
  const [email, setEmail] = useState(""),
    [password, setPassword] = useState("");
  const [visible, setVisible] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      onLogin(await api<Session>("/login", { email, password }));
    } catch (e) {
      setError(
        e instanceof ApiError && e.status === 401
          ? "Email or password is incorrect."
          : message(e),
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <main className="login-page">
      <section className="login-story">
        <Brand />
        <div className="story-body">
          <span className="eyebrow">MARINDUQUE, PHILIPPINES</span>
          <h1>
            A clearer view.
            <br />
            <em>A connected journey.</em>
          </h1>
          <p>
            Your workspace for jeepney reports and the transport network you
            help manage.
          </p>
          <div className="journey-art" aria-hidden="true">
            <div className="art-line" />
            <span className="art-point one" />
            <span className="art-point two" />
            <div className="art-vehicle">
              <Icon name="vehicle" />
            </div>
            <div className="art-label">
              <Icon name="signal" /> Every report tells a story.
            </div>
          </div>
        </div>
        <p className="story-footer">
          AbangQue <span>Passenger assistance, thoughtfully connected.</span>
        </p>
      </section>
      <section className="login-side">
        <div className="login-card">
          <span className="icon-tile">
            <Icon name="lock" />
          </span>
          <span className="eyebrow">ADMINISTRATOR ACCESS</span>
          <h2>Welcome back.</h2>
          <p>Sign in to your AbangQue workspace.</p>
          {notice && (
            <p className="notice" role="status">
              {notice}
            </p>
          )}
          <form onSubmit={submit} className="login-form">
            <label htmlFor="email">Email address</label>
            <input
              id="email"
              type="email"
              autoComplete="username"
              required
              maxLength={254}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              disabled={busy}
            />
            <label htmlFor="password">Password</label>
            <div className="password-field">
              <input
                id="password"
                type={visible ? "text" : "password"}
                autoComplete="current-password"
                required
                maxLength={128}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={busy}
              />
              <button
                type="button"
                onClick={() => setVisible(!visible)}
                aria-label={visible ? "Hide password" : "Show password"}
                aria-pressed={visible}
              >
                {visible ? "Hide" : "Show"}
              </button>
            </div>
            {error && (
              <p role="alert" className="error">
                {error}
              </p>
            )}
            <button className="button primary" disabled={busy}>
              {busy ? "Signing in…" : "Sign in to workspace"}
              <Icon name="arrow" />
            </button>
          </form>
          <div className="restricted-note">
            <Icon name="lock" />
            <p>
              For authorized administrators only.
              <br />
              Access is provisioned by the system owner.
            </p>
          </div>
        </div>
        <p className="login-footnote">AbangQue · Administration portal</p>
      </section>
    </main>
  );
}

export function App() {
  const [session, setSession] = useState<Session | null>(null),
    [checking, setChecking] = useState(true);
  const [connectionError, setConnectionError] = useState(""),
    [notice, setNotice] = useState("");
  const [section, setSection] = useState<Section>(sectionFromHash);
  const [collapsed, setCollapsed] = useState(false),
    [mobile, setMobile] = useState(false);
  const [profile, setProfile] = useState(false),
    [logoutBusy, setLogoutBusy] = useState(false),
    [logoutError, setLogoutError] = useState("");
  const drawer = useRef<HTMLDialogElement>(null),
    menuButton = useRef<HTMLButtonElement>(null);
  const expire = useCallback(() => {
    setSession(null);
    setNotice("Your session has ended. Please sign in again.");
    setProfile(false);
    setMobile(false);
  }, []);
  const restore = useCallback(async () => {
    setChecking(true);
    setConnectionError("");
    try {
      setSession(await api<Session>("/session"));
    } catch (e) {
      if (!(e instanceof ApiError && e.status === 401))
        setConnectionError(message(e));
    } finally {
      setChecking(false);
    }
  }, []);
  useEffect(() => {
    void restore();
  }, [restore]);
  useEffect(() => {
    const change = () => setSection(sectionFromHash());
    window.addEventListener("hashchange", change);
    return () => window.removeEventListener("hashchange", change);
  }, []);
  useEffect(() => {
    if (!session) return;
    const timer = window.setTimeout(
      expire,
      Math.max(0, Date.parse(session.expiresAt) - Date.now()),
    );
    const check = () => {
      if (Date.now() >= Date.parse(session.expiresAt)) expire();
    };
    window.addEventListener("focus", check);
    return () => {
      clearTimeout(timer);
      window.removeEventListener("focus", check);
    };
  }, [session, expire]);
  useEffect(() => {
    if (mobile) drawer.current?.showModal();
    else drawer.current?.close();
  }, [mobile]);
  function navigate(next: Section) {
    location.hash = "/" + paths[sections.indexOf(next)];
    setSection(next);
    setMobile(false);
    setProfile(false);
  }
  async function logout() {
    setLogoutBusy(true);
    setLogoutError("");
    try {
      await api("/logout", {});
      setSession(null);
      setNotice("You have been signed out.");
      setProfile(false);
      setMobile(false);
    } catch (e) {
      setLogoutError("Sign out was not confirmed. " + message(e));
    } finally {
      setLogoutBusy(false);
    }
  }
  if (checking)
    return (
      <main className="session-state">
        <Brand />
        <p role="status">Checking your secure session…</p>
      </main>
    );
  if (connectionError)
    return (
      <main className="session-state">
        <Brand />
        <h1>Unable to connect</h1>
        <p role="alert">{connectionError}</p>
        <button className="button primary" onClick={() => void restore()}>
          Retry connection
        </button>
      </main>
    );
  if (!session) return <Login notice={notice} onLogin={setSession} />;
  function navigation(small = false) {
    return (
      <nav aria-label={small ? "Mobile navigation" : "Main navigation"}>
        {sections.map((item, index) => (
          <a
            key={item}
            href={"#/" + paths[index]}
            className={section === item ? "nav-item selected" : "nav-item"}
            aria-current={section === item ? "page" : undefined}
            title={item}
            onClick={(e) => {
              e.preventDefault();
              navigate(item);
            }}
          >
            <Icon name={symbols[index]} />
            <span>{item}</span>
          </a>
        ))}
      </nav>
    );
  }
  return (
    <div className={"app-shell" + (collapsed ? " compact" : "")}>
      <a
        href="#main"
        className="skip-link"
        onClick={(event) => {
          event.preventDefault();
          document.getElementById("main")?.focus();
        }}
      >
        Skip to content
      </a>
      <aside className="sidebar">
        <Brand compact={collapsed} />
        <p className="sidebar-caption">WORKSPACE</p>
        {navigation()}
        <div className="sidebar-bottom">
          <div className="workspace-note">
            <span className="tiny-dot" />
            <span>
              Marinduque network<small>Administration workspace</small>
            </span>
          </div>
          <button
            className="collapse-button"
            onClick={() => setCollapsed(!collapsed)}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            aria-expanded={!collapsed}
          >
            <Icon name="menu" />
            {!collapsed && "Collapse sidebar"}
          </button>
        </div>
      </aside>
      <dialog
        ref={drawer}
        className="mobile-drawer"
        onCancel={() => setMobile(false)}
        onClose={() => {
          setMobile(false);
          menuButton.current?.focus();
        }}
      >
        <div className="flex items-center justify-between gap-4">
          <Brand />
          <button
            className="icon-button"
            aria-label="Close navigation"
            onClick={() => setMobile(false)}
          >
            <Icon name="close" />
          </button>
        </div>
        {navigation(true)}
      </dialog>
      <div className="workspace">
        <header className="topbar">
          <div className="breadcrumb">
            <button
              ref={menuButton}
              className="icon-button mobile-menu"
              aria-label="Open navigation"
              aria-expanded={mobile}
              onClick={() => setMobile(true)}
            >
              <Icon name="menu" />
            </button>
            <span>Workspace</span>
            <span className="slash">/</span>
            <strong>{section}</strong>
          </div>
          <div className="header-right">
            <span className="admin-badge">
              <Icon name="lock" />
              Administrator
            </span>
            <div className="profile-wrap">
              <button
                className="avatar"
                aria-label="Administrator profile"
                aria-expanded={profile}
                onClick={() => setProfile(!profile)}
              >
                AQ
              </button>
              {profile && (
                <div
                  className="profile-panel"
                  onKeyDown={(e) => {
                    if (e.key === "Escape") setProfile(false);
                  }}
                >
                  <strong>Administrator</strong>
                  <p>{session.user.email}</p>
                  <button onClick={() => navigate("Settings")}>
                    Account & session
                  </button>
                  <button disabled={logoutBusy} onClick={() => void logout()}>
                    {logoutBusy ? "Signing out…" : "Sign out"}
                  </button>
                </div>
              )}
            </div>
          </div>
        </header>
        <main id="main" className="main-content" tabIndex={-1}>
          {logoutError && (
            <p role="alert" className="error">
              {logoutError}
            </p>
          )}
          {section === "Dashboard" ? (
            <Overview onExpire={expire} navigate={navigate} />
          ) : section === "Jeepneys" ? (
            <JeepneyManagement onExpire={expire} />
          ) : section === "Routes" ? (
            <RouteManagement onExpire={expire} />
          ) : section === "IoT Devices" ? (
            <DeviceManagement onExpire={expire} />
          ) : section === "Live Monitoring" ? (
            <Suspense fallback={<p role="status">Loading monitoring map…</p>}>
              <LiveMonitoring onExpire={expire} />
            </Suspense>
          ) : section === "Settings" ? (
            <>
              <PageHeading
                title="Settings"
                description="Your administrator account and workspace session."
              />
              <section className="panel settings-panel">
                <span className="eyebrow">ACCOUNT & SECURITY</span>
                <h2>Administrator profile</h2>
                <dl>
                  <dt>Email address</dt>
                  <dd>{session.user.email}</dd>
                  <dt>Access level</dt>
                  <dd>Administrator</dd>
                  <dt>Session expires</dt>
                  <dd>{date(session.expiresAt)}</dd>
                </dl>
                <p>
                  This workspace uses a secure browser session. Account
                  provisioning is managed locally by the system owner.
                </p>
                <button
                  className="button primary"
                  onClick={() => void logout()}
                  disabled={logoutBusy}
                >
                  {logoutBusy ? "Signing out…" : "Sign out of workspace"}
                </button>
              </section>
            </>
          ) : (
            <>
              <PageHeading
                title={section}
                description="A dedicated space for the next stage of your network."
              />
              <section className="panel coming-soon">
                <span className="icon-tile">
                  <Icon name={symbols[sections.indexOf(section)]} />
                </span>
                <span className="eyebrow">COMING SOON</span>
                <h2>{section}, in the next phase.</h2>
                <p>
                  This module is planned. Management and monitoring actions are
                  not available yet.
                </p>
                <button
                  className="button secondary"
                  onClick={() => navigate("Dashboard")}
                >
                  Back to dashboard
                  <Icon name="arrow" />
                </button>
              </section>
            </>
          )}
        </main>
        <footer className="workspace-footer">
          <span>
            AbangQue <span className="muted">/ Administration</span>
          </span>
          <span>Built for the journeys ahead.</span>
        </footer>
      </div>
    </div>
  );
}
function PageHeading({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div className="page-heading">
      <span className="eyebrow">YOUR NETWORK AT A GLANCE</span>
      <h1>{title}</h1>
      <p>{description}</p>
    </div>
  );
}
function Overview({
  onExpire,
  navigate,
}: {
  onExpire: () => void;
  navigate: (section: Section) => void;
}) {
  const [data, setData] = useState<Dashboard | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const [lastSuccess, setLastSuccess] = useState<string | null>(null),
    [now, setNow] = useState(performance.now());
  const [snapshotDeadline, setSnapshotDeadline] = useState(0);
  const inFlight = useRef(false),
    mounted = useRef(true);
  const refresh = useCallback(async () => {
    if (inFlight.current) return;
    inFlight.current = true;
    setBusy(true);
    const started = performance.now();
    try {
      const result = await api<Dashboard>("/dashboard");
      if (!mounted.current) return;
      // Use server-relative age and a monotonic local timer, not the laptop's wall clock.
      const lifetime = result.summary.validUntil
        ? Date.parse(result.summary.validUntil) - Date.parse(result.updatedAt)
        : 30000;
      setSnapshotDeadline(started + Math.min(30000, Math.max(0, lifetime)));
      setData(result);
      setLastSuccess(result.updatedAt);
      setError("");
      setNow(performance.now());
    } catch (e) {
      if (!mounted.current) return;
      setData(null);
      setError(message(e));
      if (e instanceof ApiError && e.status === 401) onExpire();
    } finally {
      inFlight.current = false;
      if (mounted.current) setBusy(false);
    }
  }, [onExpire]);
  useEffect(() => {
    mounted.current = true;
    void refresh();
    const poll = window.setInterval(() => {
      if (!document.hidden) void refresh();
    }, 30000);
    const tick = window.setInterval(() => setNow(performance.now()), 1000);
    const focus = () => {
      setNow(performance.now());
      void refresh();
    };
    window.addEventListener("focus", focus);
    return () => {
      mounted.current = false;
      clearInterval(poll);
      clearInterval(tick);
      window.removeEventListener("focus", focus);
    };
  }, [refresh]);
  const outdated = !!data && now >= snapshotDeadline;
  const current = data && !outdated ? data : null;
  useEffect(() => {
    if (outdated && !error) void refresh();
  }, [outdated, error, refresh]);
  const cards = [
    [
      "Registered Jeepneys",
      current?.summary.jeepneys,
      "vehicle",
      "Active and inactive · excludes DEMO",
    ],
    [
      "Registered Routes",
      current?.summary.routes,
      "route",
      "All stored municipality directions",
    ],
    [
      "Registered Devices",
      current?.summary.devices,
      "device",
      "Registrations · hardware operation unverified",
    ],
    [
      "Fresh Location Reports",
      current?.summary.fresh,
      "signal",
      "Active vehicles with recent reports",
    ],
  ] as const;
  return (
    <>
      <div className="overview-heading">
        <PageHeading
          title="Dashboard"
          description="A clearer picture of your jeepney network."
        />
        <button
          className="button secondary"
          onClick={() => void refresh()}
          disabled={busy}
        >
          <Icon name="refresh" />
          {busy ? "Updating…" : "Refresh overview"}
        </button>
      </div>
      {error && (
        <div className="error" role="alert">
          <strong>Dashboard unavailable.</strong> {error}{" "}
          <button onClick={() => void refresh()} disabled={busy}>
            Retry
          </button>
        </div>
      )}
      {outdated && !error && (
        <p className="notice" role="status">
          Refreshing report freshness. Current counts are unavailable until the
          update completes.
        </p>
      )}
      <section className="stats-grid" aria-label="Summary statistics">
        {cards.map(([label, value, icon, description], i) => (
          <article
            className={"stat-card" + (i === 3 ? " accent" : "")}
            key={label}
          >
            <div className="stat-top">
              <span>{label}</span>
              <span className="stat-icon">
                <Icon name={icon} />
              </span>
            </div>
            <strong
              className={value == null ? "unavailable-value" : "stat-value"}
            >
              {value == null
                ? i === 2
                  ? "Not available"
                  : busy
                    ? "Loading…"
                    : "Unavailable"
                : value.toLocaleString()}
            </strong>
            <p>{description}</p>
          </article>
        ))}
      </section>
      <div className="overview-grid">
        <section className="panel system-panel">
          <div className="panel-heading">
            <div>
              <span className="eyebrow">CONNECTION & FRESHNESS</span>
              <h2>System overview</h2>
            </div>
            <span className={"status-pill " + (error ? "warning" : "")}>
              <span className="tiny-dot" />
              {error
                ? "Connection failed"
                : busy
                  ? "Checking API"
                  : "API connected"}
            </span>
          </div>
          <div className="system-facts">
            <div>
              <span>Last successful update</span>
              <strong>{date(lastSuccess)}</strong>
            </div>
            <div>
              <span>Refresh cycle</span>
              <strong>Every 30 seconds while visible</strong>
            </div>
          </div>
          <div className="report-stats">
            <div>
              <strong>{current?.summary.available ?? "—"}</strong>
              <span>AVAILABLE vehicles</span>
            </div>
            <div>
              <strong>{current?.summary.full ?? "—"}</strong>
              <span>FULL vehicles</span>
            </div>
            <div>
              <strong>{current?.summary.staleOrMissing ?? "—"}</strong>
              <span>Stale / missing vehicles</span>
            </div>
          </div>
          <p className="fine-print">
            FULL / AVAILABLE is manually reported by drivers. It is not measured
            occupancy or a boarding guarantee. Accepted reports do not verify
            physical GPS operation.
          </p>
        </section>
        <aside className="network-note">
          <span className="icon-tile">
            <Icon name="route" />
          </span>
          <span className="eyebrow">BUILT ON CLEAR INFORMATION</span>
          <h2>
            Every journey starts
            <br />
            with a trusted report.
          </h2>
          <p>
            Measurement time and last communication are shown separately. Old
            reports never become current availability.
          </p>
          <div className="note-bottom">
            ETA unavailable <span>·</span> No estimates inferred
          </div>
        </aside>
      </div>
      <section className="panel activity-panel">
        <div className="panel-heading">
          <div>
            <span className="eyebrow">LATEST RECEIVED REPORTS</span>
            <h2>Recent jeepney activity</h2>
          </div>
          <span className="small-label">Up to 20 vehicles</span>
        </div>
        {current?.summary.demoJeepneys ? (
          <p className="demo-notice">
            DEMO / SIMULATED: {current.summary.demoJeepneys} test vehicles in
            the database. Excluded from operational statistics and current
            availability.
          </p>
        ) : null}
        {!current ? (
          <div className="empty-state" role="status">
            <Icon name="signal" />
            <h3>
              {busy ? "Fetching vehicle reports…" : "Reports unavailable"}
            </h3>
            <p>
              {busy
                ? "Reading the latest records from your system."
                : "Refresh to retrieve current information."}
            </p>
          </div>
        ) : current.recent.length === 0 ? (
          <div className="empty-state">
            <Icon name="vehicle" />
            <h3>No registered jeepneys yet</h3>
            <p>
              Activity will appear here when records are available in your
              system.
            </p>
          </div>
        ) : (
          <div
            className="table-scroll"
            role="region"
            aria-label="Recent activity table"
            tabIndex={0}
          >
            <table>
              <thead>
                <tr>
                  <th>Jeepney</th>
                  <th>Assigned route</th>
                  <th>Location measured</th>
                  <th>Last communication</th>
                  <th>Report freshness</th>
                  <th>Driver status</th>
                </tr>
              </thead>
              <tbody>
                {current.recent.map((row) => (
                  <tr key={row.id}>
                    <td>
                      <strong>{row.id}</strong>
                      <small>{row.name}</small>
                      {row.active === false && (
                        <small>Inactive registration</small>
                      )}
                      <span
                        className={
                          row.source === "device"
                            ? "source-label"
                            : "source-label demo"
                        }
                      >
                        {row.source === "device"
                          ? "DEVICE RECORD"
                          : row.source === "demo"
                            ? "DEMO"
                            : "DEMO / SIMULATED"}
                      </span>
                    </td>
                    <td>{row.route ?? "Unassigned"}</td>
                    <td>{date(row.timestamp)}</td>
                    <td>{date(row.lastSeenAt)}</td>
                    <td>
                      <span
                        className={
                          "status-pill " +
                          (row.source !== "device" || row.freshness !== "FRESH"
                            ? "neutral"
                            : "")
                        }
                      >
                        {row.source !== "device" ? "DEMO · " : ""}
                        {row.freshness}
                      </span>
                    </td>
                    <td>
                      <span
                        className={
                          "status-pill " +
                          (row.status === "UNKNOWN" ? "neutral" : "")
                        }
                      >
                        {row.status}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="panel-footnote">
          Manage registered route assignments in Jeepneys. Manage device
          registrations in IoT Devices.
        </div>
      </section>
      <section className="quick-navigation">
        <div>
          <span className="eyebrow">LOOKING AHEAD</span>
          <h2>Your workspace, taking shape.</h2>
        </div>
        <div className="quick-links">
          {(
            [
              "Jeepneys",
              "Routes",
              "IoT Devices",
              "Live Monitoring",
            ] as Section[]
          ).map((item) => (
            <button key={item} onClick={() => navigate(item)}>
              <Icon name={symbols[sections.indexOf(item)]} />
              <span>
                {item}
                <small>
                  {item === "Jeepneys" ||
                  item === "Routes" ||
                  item === "IoT Devices"
                    ? "Manage records"
                    : "View device reports"}
                </small>
              </span>
              <Icon name="arrow" />
            </button>
          ))}
        </div>
      </section>
    </>
  );
}
