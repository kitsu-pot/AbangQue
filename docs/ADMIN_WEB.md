# AbangQue admin web foundation

Phase 6 update (2026-11-14): [Admin Live GPS Monitoring](LIVE_MONITORING.md) now provides the protected report map, filters and historical device/vehicle details. Migration 009 adds one receipt lookup index; earlier Live Monitoring deferral notes are historical.

Phase 5 update (2026-11-14): [IoT Device Management](DEVICE_MANAGEMENT.md) adds registrations, assignments, access controls and one-time credentials through migration 008. Earlier device-registry deferral notes are historical.

Phase 4 update (2026-11-14): [Route Management](ROUTE_MANAGEMENT.md) now supports verified directions, operational metadata and reversible route activation. Earlier route-deferral notes below are historical.

Foundation implemented 2026-11-12; Jeepney Management added 2026-11-13. The admin
web includes authentication, overview, navigation, account/session Settings and
vehicle registration/editing/route assignment/activation. See
[JEEPNEY_MANAGEMENT.md](JEEPNEY_MANAGEMENT.md) for Phase 3. Routes, IoT Devices and
Live Monitoring remain **Coming soon**. No driver accounts, hardware integration,
ETA calculation or deployment is included.

Checkpoint: `checkpoint/admin-foundation-2026-11-12` at `db859dc`.

## Local Windows PowerShell setup

Use Node.js 24, the existing PostgreSQL database and two terminals. No Docker,
paid service or second database is needed. Use **127.0.0.1 consistently**, including
in the browser. Mixing localhost and 127.0.0.1 changes the cookie/origin context.

Terminal 1:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm ci
npm run migrate
npm start
```

The existing ignored `backend/.env` must already contain the correct DATABASE_URL,
HOST=127.0.0.1 and NODE_ENV=development. The provisioning command also requires the
database hostname to be localhost, 127.0.0.1 or ::1. Do not replace the existing
database configuration. Never paste its credentials into chats or tracked files.

If the old backend is running on port 3000, stop it with Ctrl+C in its terminal
before `npm start`. Its already-loaded code will not gain admin endpoints just
because files or migrations changed. A 404 on `/api/admin/session` usually means
the older server is still running; the updated server returns 401 before login.

Terminal 2:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\admin-web
npm ci
npm run dev
```

Open <http://127.0.0.1:5173/>. Vite proxies only `/api/admin` to the existing API
at `http://127.0.0.1:3000`; it keeps the browser Origin header intact. Ports are
strict so Vite cannot silently move to an untrusted origin. No CORS wildcard is used.

### First administrator

If no administrator exists, `npm run admin:provision` invokes the tracked PowerShell wrapper. It prompts for
email, masked password and masked confirmation. Use a unique password of 15–128
characters; repeated-character and a few known weak values are rejected. There
is no default password, account or public registration page.

The wrapper sends JSON to the Node CLI over stdin. Passwords are never supplied
as command arguments, environment variables, files or printed output. The
temporary plaintext exists only in process memory; unmanaged buffers are zeroed
and managed references released after use. As with other JavaScript/.NET password
handling, garbage-collected memory is not guaranteed to be immediately erased.
Avoid terminal recording or diagnostics that capture process input.

Only the **first** admin can be created with this command. A table lock serializes
concurrent attempts and rejects any second administrator, even with a different
email. It never overwrites or elevates passengers. Additional admin provisioning,
password changes/recovery and account administration require a separate phase.
Do not delete accounts or edit hashes to bypass these safeguards.

No owner administrator was created during implementation. Run the command yourself
to choose the credentials. Test accounts existed only in disposable integration
schemas and were removed at the end of tests.

## Migration and architecture

`005_admin_auth.sql` adds `admin_accounts` and `admin_sessions` with role constraints,
foreign keys, expiry checks and indexes. No passenger table or existing data is
modified. The existing checksum/advisory-lock migration runner applies it once.
Migration 005 was applied to local PostgreSQL during this task; `npm run migrate`
is safe to repeat because the runner checks its ledger. No seeds were run.

Dedicated tables preserve the existing PASSENGER-only identity contract. Admin
authentication reuses Argon2id parameters (64 MiB, three iterations, parallelism 1)
and the existing shared limit of four concurrent password operations. Admin
sessions use 32 random bytes with a distinct `aqa_` prefix. Only a SHA-256 token
hash is stored in PostgreSQL. No token is returned in JSON or stored in browser
localStorage/sessionStorage. The admin session is an HttpOnly host-only cookie.

| Location | Responsibility |
| --- | --- |
| `admin-web/src/App.tsx` | Login, verified-session gate, navigation, overview, placeholders and Settings |
| `admin-web/src/api.ts` | Typed API boundary, cookie requests, timeout, sanitized errors |
| `admin-web/src/style.css` | Original emerald/mint/cream styling and responsive layouts |
| `admin-web/vite.config.ts` | Tailwind integration and local API proxy |
| `backend/src/admin-auth.js` | Origin/CSRF/CORS rules, login throttling, cookies and server authorization |
| `backend/src/admin-repository.js` | Parameterized admin persistence and consistent read-only dashboard snapshots |
| `backend/src/admin-provision.js` | Local development and credential policy guards |
| `backend/scripts/admin-provision.*` | PowerShell secure prompts and Node stdin entry point |
| `backend/test/admin*.test.js` | Authorization/unit and real PostgreSQL tests |
| `admin-web/src/*.test.*` | Component/navigation and API boundary tests |

Passenger endpoints remain separate. A passenger bearer token, device token,
client role field or passenger cookie cannot authorize any admin read. The sole
passenger-auth code change exports its existing password-work limiter for reuse.

## API contract

Responses follow the existing `{ data: ... }` / `{ error: ... }` conventions.
All responses are `Cache-Control: no-store`; database errors and secrets are not
exposed. No device credentials or password hashes enter dashboard responses.

| Method and path | Result |
| --- | --- |
| POST `/api/admin/login` | Validated email/password; sets cookie; returns public admin identity and absolute expiry |
| GET `/api/admin/session` | Server-verified identity and expiry, or 401 |
| POST `/api/admin/logout` | Revokes cookie token server-side and clears cookie; idempotent, 204 |
| GET `/api/admin/dashboard` | Summary and latest 20 vehicle records from one consistent database snapshot; requires admin |

POST requests require JSON for login, an exact allowed Origin, and
`X-AbangQue-Admin: 1`. The custom header forces cross-origin preflight; strict
Origin checks also reject simple form posts, missing/null Origin and disallowed
preflights. CORS allows credentials only for explicitly configured origins and
never reflects arbitrary origins. This applies to login as well as logout.
Unknown email and incorrect password share the same 401 error; unknown accounts
still incur Argon2 verification. Login attempts are limited independently by IP
and normalized email for 15 minutes. Role fields are rejected in login input.

Sessions expire absolutely (eight hours by default), with no sliding renewal.
The database and every protected request check expiry/revocation/ADMIN identity.
The UI returns to login on expiry or 401. Logout failures remain visibly unconfirmed
and offer retry; the UI never claims server revocation succeeded while offline.
Logging in again rotates the browser session and revokes the previous cookie.
Expired/revoked rows are retained; operational retention cleanup is future work.

The in-memory rate-limit store is suitable for this single-process local setup;
restarting resets limits. Shared limits and abuse monitoring are required before
multi-instance deployment. HTTPS is mandatory in production, including auth reads.
Production cookies use `__Host-abangque_admin`, Secure, HttpOnly and Path=/ with
no Domain. Local development uses `abangque_admin` without Secure for loopback HTTP.

## Truthful dashboard semantics

- Registered Jeepneys counts only `source=device` vehicle records. This is a
  registration count, not proof of working physical hardware.
- Registered Routes counts the real `registered_routes` table, including inactive
  records. The opt-in simulator catalog is not an operating route or included count.
- Registered Devices counts real registrations in `iot_devices`, including disabled
  and labeled legacy registrations, excluding SIMULATED. This is not proof of
  physical hardware; see DEVICE_MANAGEMENT.md for legacy credential grouping.
- Route assignment is managed in Jeepneys through migration 006's optional route
  foreign key; unassigned vehicles are labeled Unassigned.
- Fresh reports require both latest measurement time and latest communication time
  to be present, no later than the server clock, and younger than STALE_AFTER_SECONDS.
  Equality with the threshold is stale. Missing, old and future reports are not fresh.
- Registration totals include active/inactive real vehicles. Fresh, stale/missing,
  FULL and AVAILABLE counts include active real vehicles only. Inactive registrations
  remain labeled in recent activity with UNKNOWN driver status.
- FULL and AVAILABLE count only vehicles with fresh `source=device` reports. Old,
  missing, DEMO and SIMULATED availability is UNKNOWN. No seat or occupancy counts.
- DEMO/SIMULATED records remain visible with clear source labels and a separate
  test-vehicle count. They never increase operational availability/fresh counts.
- Recent activity is ordered by last communication and bounded to 20 vehicles.
  Measurement and receipt timestamps remain separate. ETA is unavailable.
- The UI polls every 30 seconds while visible. It hides current counts at the first
  freshness deadline (server-relative, conservative request elapsed time, monotonic
  local clock), and refreshes. Failed refreshes clear report values; last successful
  update time remains for context. This is polling, not continuous live tracking.

## Environment settings

Backend (`backend/.env`, examples only in `.env.example`):

| Variable | Default / rule |
| --- | --- |
| ADMIN_WEB_ORIGINS | `http://127.0.0.1:5173`; exact comma-separated origins, no trailing slash, credentials, path, wildcard or whitespace |
| ADMIN_COOKIE_SAME_SITE | `strict`; `lax` or production-only `none` supported for a deliberately chosen future architecture |
| ADMIN_SESSION_TTL_SECONDS | `28800`; allowed 300–86400 seconds |
| ADMIN_AUTH_RATE_LIMIT | `10`; per IP and normalized email per 15 minutes |
| STALE_AFTER_SECONDS | Existing freshness threshold, unchanged |
| TRUST_PROXY | Existing `false` or `loopback`; only enable behind an actual trusted loopback HTTPS proxy |

Frontend (`admin-web/.env`, optional):

| Variable | Purpose |
| --- | --- |
| ADMIN_API_PROXY_TARGET | Vite server-only development proxy; defaults to `http://127.0.0.1:3000` |
| VITE_ADMIN_API_ORIGIN | Empty for same-origin requests; optional exact HTTPS API origin for a future static deployment |

All `VITE_` variables are public build inputs. Never put passwords, session tokens,
database URLs or device secrets there. `.env*`, dependencies, output and local
private files are ignored; `.env.example` and package-lock.json are tracked.

## Checks and acceptance

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm run check
npm test
npm run test:postgres
Set-Location ..\admin-web
npm run typecheck
npm run lint
npm test
npm run build
```

PostgreSQL integration tests use random isolated schemas in the configured database
and drop those test schemas afterwards. The database role needs CREATE SCHEMA.
They never seed production/public operating data or provision an owner admin.
The normal backend suite intentionally skips real database suites; use
`test:postgres` to execute them. Phase 3 adds ESLint alongside TypeScript, Vitest
and the production build; current results are recorded in JEEPNEY_MANAGEMENT.md.

Historical Phase 2 results: backend check passed, 45 database-free tests passed (five
database suites skipped); all 42 PostgreSQL tests passed. Frontend TypeScript and
production build passed; all 10 frontend tests passed (two test files).
Manual browser inspection covered desktop (1440px) and mobile (390px) login layouts,
mobile horizontal-overflow measurement, and API-unavailable/retry presentation.
Authenticated UI navigation and logout were component-tested; owner-account login,
authenticated dashboard visual inspection and physical tablet acceptance were not
manually performed. No hardware operation is implied by these results.

After provisioning, verify:

1. Opening `/#/settings` while signed out shows login. Wrong credentials produce a
   generic error. Passenger credentials do not grant access.
2. Sign in with the CLI-provisioned admin. Refresh the page to verify cookie session
   recovery. Check real counts, source labels, separate timestamps and empty states.
3. Collapse the desktop sidebar; at phone width use the navigation drawer, Tab and
   Escape. Check 200% text zoom and keyboard focus. Planned sections say Coming soon.
4. Stop the API and refresh the overview: an error and Retry appear, report counts
   become unavailable and the last successful update remains. Restart and Retry.
5. Open Settings or the profile menu and sign out. Refresh and revisit protected
   hashes: login must be shown. Check expiration with a short configured TTL.

## Future hosting, not deployed

The Vite build produces static `admin-web/dist/`. Hash navigation avoids requiring
server rewrite rules for nested dashboard links. The planned `abangque.dpdns.org`
domain has not been configured or deployed. Static frontend hosting does not run
this Express API or PostgreSQL database: they still need reachable secure hosting.

Prefer same-origin HTTPS with `/api/admin` routed to the existing API. For separate
frontend/API origins configure the exact HTTPS origins, credentialed CORS and host-only
cookies deliberately. SameSite Strict supports same-site subdomains; truly cross-site
hosting may require SameSite=None and can still be blocked by browser third-party
cookie restrictions. Keep TLS termination and proxy trust explicit. Review static
host security headers/CSP, backups, retention, distributed throttling and operational
account recovery before public deployment. Do not publish a loopback API URL.

Implementation references: [Vite guide](https://vite.dev/guide/),
[Tailwind Vite integration](https://tailwindcss.com/docs/installation/using-vite),
[OWASP CSRF prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html).
