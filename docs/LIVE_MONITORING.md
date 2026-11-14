# Admin Live GPS Monitoring — Phase 6

Implemented locally on 2026-11-14. Checkpoint before changes:
`checkpoint/live-monitoring-2026-11-14` at `fb94883`.

Live Monitoring is an authenticated, read-only view of accepted PostgreSQL reports.
It does not establish continuous tracking, connectivity, actual movement, GPS fix
accuracy or physical hardware operation. No firmware, device protocol, passenger
UI, ETA calculation, admin driver-status control or deployment was added.

## Run locally in Windows PowerShell

Use Node.js 24 and the existing PostgreSQL configuration. Stop an older API in its
own terminal with Ctrl+C before restarting it. Do not start a second server on the
same port. Keep the existing ignored `backend/.env`; do not copy credentials into
the browser or any VITE variable.

Terminal 1:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm ci
npm run migrate
npm start
```

Terminal 2:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\admin-web
npm ci
npm run dev
```

Open <http://127.0.0.1:5173/#/monitoring> and sign in with your existing administrator.
Use 127.0.0.1 consistently. Vite proxies `/api/admin` to port 3000. If no administrator
exists, follow the secure first-admin workflow in [ADMIN_WEB.md](ADMIN_WEB.md).
No default owner password or new owner account is created by this phase.

Optional polling setting in ignored `admin-web/.env.local`:

```dotenv
VITE_MONITORING_POLL_SECONDS=30
```

Allowed range: 10–300 seconds; invalid values fall back to 30. Restart Vite after
changing environment settings. This is dashboard polling, not device transmission.

## API and data flow

`GET /api/admin/monitoring` is new. It is mounted after the existing admin session,
ADMIN role, origin and production HTTPS checks. Guest, passenger and device tokens
cannot authorize it. It uses parameterized SQL, no-store responses and the existing
sanitized database-error handler. It does not expose secrets, credential hashes,
admin account fields or private administrative notes.

| Query | Values / default |
| --- | --- |
| `search` | Literal identifier/plate substring, at most 120 characters; empty |
| `routeId` | Registered UUID, `all`, `unassigned`; `all` |
| `reporting` | `all`, `fresh`, `stale`, `missing`; `all` |
| `status` | Administrative `all`, `active`, `inactive`; `all` |
| `device` | `all`, `enabled`, `disabled`, `revoked`, `unprovisioned`, `unassigned`; `all` |
| `page` | Integer 1–100000; 1; clamped to the last available page |
| `selectedId` | Optional valid jeepney identifier, independently retrieved even outside the filters/page |

Unknown query keys and simulation overrides are rejected with 400. Each page has
at most 100 vehicles; the map explicitly shows that page plus the selected vehicle
when outside it. This avoids silently presenting a truncated whole-fleet map.

Response: `{data:{items,selected,total,page,pageSize,counts,updatedAt,staleAfterSeconds}}`.
Each item contains vehicle ID/name/plate/activation/source, actual directional route,
current assigned device summaries, historical report-device identity/current assignment,
coordinates or null, coordinate validity, measurement/receipt timestamps, reporting
freshness, current conservative driver status, historical driver status and `eta:null`.

Existing endpoints are reused:

- `GET /api/admin/route-options`: real active and inactive directional routes.
- Existing Jeepney and IoT Device Management detail endpoints: opened through their
  existing components. Editing stays in those modules. Returning from management
  starts a new monitoring view; polling refreshes within monitoring preserve its view.
- Existing `/api/device-updates`: unchanged request/authentication contract.

No new unauthenticated monitoring route exists. Source `demo` and `simulated` records
are excluded from monitoring items and all real-operation counts. A separate excluded
test-vehicle count is labeled DEMO / SIMULATED. There is no simulator opt-in in this
module; existing development-only simulator tools and read-only management labels
remain available. Production simulator restrictions are unchanged.

## Historical ownership and freshness

The latest GPS measurement is selected by original `jeepney_id`, then `recorded_at`
descending and row ID descending. Its credential points to the original reporting
device. A device reassignment never moves this report to the new jeepney. Current
assigned devices are returned separately; multiple disabled registrations can still
refer to one jeepney, so this is an array, not an arbitrary single-device choice.

Timestamp meanings:

- `timestamp`: original GPS and manual driver-status measurement time.
- `reportReceivedAt`: backend receipt of that exact measurement.
- `lastSeenAt`: latest accepted communication for the original jeepney, independently
  selected even when measurements arrive out of order.
- Device summary timestamps: latest measurement and communication across that device's
  credential versions and historical assignments. The details panel discloses this.
- `updatedAt`: server time at the start of the monitoring read, never a replacement
  measurement time. It is shown separately as the last successful dashboard refresh.

FRESH requires both measurement and latest receipt no later than server time and
strictly younger than `STALE_AFTER_SECONDS` (existing default 120). Equality is STALE.
No measurement is MISSING. Future/unreliable reports cannot establish current status.
Coordinates must be finite and inside latitude/longitude bounds; invalid coordinates
are distinguished from absent reports and never get a marker. This does not assert
GPS hardware accuracy, speed, altitude or heading.

Current FULL/AVAILABLE additionally requires a valid coordinate, active real-source
vehicle, enabled original reporting device still assigned to that vehicle and an
unrevoked credential for that report. Old reports from rotated/revoked credentials
remain historical until a valid new report is accepted. Historical status remains
labeled with its original timestamp; current status becomes UNKNOWN. Route activation,
vehicle activation, device enablement, reporting freshness and availability stay separate.
The existing passenger presenter is unchanged and may apply a different conservative
access policy; monitoring does not rewrite passenger records or GPS history.

Summary counts cover the entire real-source registry, not the filtered page. Device
reporting counts include unassigned and disabled devices, and can overlap the count
of disabled/revoked devices. Device report history can belong to an old assignment.
These are registration/report counts, never a count of verified physical units or seats.

## Polling, map and performance

React Leaflet 5.0.0 and Leaflet 1.9.4 match the current React 19 frontend. The map
module is lazy-loaded only when monitoring opens. Type definitions are development-only.
The map starts over Marinduque without fabricated markers. Leaflet retains the map
instance and keyed markers across refreshes. Marker position arrays, icons and event
handlers are reused; camera movement happens only on explicit selection, without
animation. Users can pan/zoom freely; polling never recenters the camera. No fictional
road paths or inferred motion are drawn.

The scheduler runs a single request, waits for completion, then schedules the next.
Manual refresh cannot overlap it. Filter/selection changes abort obsolete requests;
generation cleanup prevents late results from replacing the current view. All requests
retain the existing 10-second timeout. Failures use exponential retry intervals, capped
at five minutes. Polling pauses while hidden, resumes on visibility and cleans up on
unmount. A 401 expires the admin session. Route options are cached in component memory
for five minutes, refreshed while visible, with an explicit retry if loading fails.
Route details in actual monitoring records update on every successful poll.

Reports age between polls using server time plus conservatively measured elapsed time,
including request latency and browser sleep. Fresh summary counts become unavailable
when their earliest validity deadline passes. Failed refreshes preserve the previous
map, show a connection warning, mark reports unverified and force UNKNOWN availability.
There is no simulation fallback or browser storage of monitoring data.

Database reads use a repeatable-read, read-only transaction so totals, page, selected
record and counts agree. Lateral top-one queries use vehicle indexes and the existing
credential/measurement index. Migration **009_monitoring_receipts.sql** adds only
`updates_credential_received(credential_id,received_at DESC)` for bounded latest-receipt
lookups across credential versions. It was applied locally. No tables, operational
records, credentials, timestamps or source classifications are changed by migration 009.
Registry/credential work scales with registrations/credential versions; no full GPS
history is fetched. Very large fleets still need measured load testing before deployment.
The standard index build can briefly block writes; coordinate a maintenance window
before applying to a large future production database.

Map tiles use HTTPS, browser caching and visible OpenStreetMap attribution. Only the
viewed area is loaded; no bulk/offline download is implemented. Tile failures have a
separate retry and do not invalidate successful backend reports. OSM receives the
browser IP/referrer and viewed area; no admin credential or device identifier is sent.
The public tile service is best-effort. See the
[React Leaflet installation guide](https://react-leaflet.js.org/docs/start-installation/)
and [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/).

## Browser acceptance with existing records

1. Restart the updated API, open Live Monitoring and confirm last successful refresh
   is separate from original GPS times. Empty records are a legitimate result.
2. Search an existing identifier/plate, choose an actual registered direction and
   compare with Jeepney Management. Reverse directions must stay separate.
3. Select a vehicle from the list. If it has a valid report, its marker focuses once.
   Without a report, details open with no fabricated marker and UNKNOWN status.
4. Pan/zoom, keep a selection and press Refresh. Zoom/selection stay in place, while
   GPS timestamps remain unchanged unless an accepted report actually changed.
5. Inspect stale/disabled/revoked records already present. Check the original device,
   current assignment and historical status. Do not rotate keys merely for UI testing.
6. At a mobile width, expand filters and select a row. Details open in a dismissible
   native dialog styled as a bottom sheet; map attribution remains outside overlays.
7. Stop the API in its own terminal briefly. After refresh/timeout, the previous view
   must say unverified and UNKNOWN. Restart it: automatic retry or Refresh recovers.
8. Open the existing management details from the panel; no editing is performed by
   monitoring itself. No manual GPS simulator test is required.

## Verification and troubleshooting

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm run check
npm test
npm run test:postgres
Set-Location C:\Users\Administrator\Projects\jeeplink\admin-web
npm run lint
npm run build
npm test
```

Observed results this phase: backend syntax check passed; `npm test` passed 57 tests
with nine database suites intentionally skipped. The full PostgreSQL runner passed
68 tests. A subsequently added out-of-order receipt regression passed with the entire
monitoring PostgreSQL suite (eight tests); the full runner was not repeated after this
test-only addition. Frontend lint, TypeScript/production build and all 36 tests across
six files passed. No dependency vulnerabilities were reported during installation.

PostgreSQL
tests use disposable schemas, cover ownership/reassignment, stale boundaries, original
timestamps, out-of-order receipt, route direction, source exclusion, paging and secret
exclusion. Frontend tests cover actual Leaflet marker/viewport preservation, single-flight
polling, visibility, cleanup, backoff/recovery, expiration, mobile dialog and management
navigation. Existing management/passenger/device regressions are retained. No Flutter
files changed, so Flutter tests were not rerun. No physical GPS/LTE/phone test was performed.

Browser review uses an isolated disposable test administrator and one clearly labeled
no-GPS vehicle, with no GPS inserts or owner-data edits. Desktop 1440px and mobile 390px
layouts, the empty map, bottom sheet and management navigation were checked there.
No horizontal overflow was observed at 390px. The QA server/schema were removed.
Actual local records were also read through the repository without exposing private data;
this is database verification, not physical hardware or owner-login acceptance.

- **401:** sign in again; passenger/device credentials cannot enter admin monitoring.
- **404:** restart the API; an older process may still own port 3000.
- **503:** check PostgreSQL reachability and run pending migrations. Do not reseed data.
- **No marker:** inspect source, filters, page, missing/invalid coordinates and original
  vehicle ownership. Device enablement/provisioning does not create a GPS report.
- **Blank/failed tiles:** check internet access; backend data can still be valid. Use
  Retry tiles and keep attribution visible. No offline tiles are promised.
- **Route option not yet updated:** actual row assignments update on refresh; choices
  refresh within five minutes or when the module is reopened.
- **Port in use:** stop the existing development process in its own terminal instead
  of launching duplicates or changing trusted origins casually.

## Files and next phase

New frontend files: `LiveMonitoring.tsx`, `MonitoringMap.tsx`, `monitoring.ts`,
`useMonitoring.ts`, `monitoring.css`, `LiveMonitoring.test.tsx`, `monitoring-fixture.ts`
(test-only fixture). Existing `App.tsx`, `api.ts`, `DeviceManagement.tsx` and related
tests integrate navigation, cancellation and device detail opening. Package files and
`.env.example` document the new map dependencies/poll interval.

New backend files: `admin-monitoring.js`, `admin-monitoring-repository.js`, migration
009 and monitoring unit/PostgreSQL tests. `server.js`, `app.js`, `admin-auth.js` and
the PostgreSQL test runner wire them into existing protected infrastructure.

Recommended next phase: admin operational alerts and report-health review, reusing
these timestamps and device audit events. Define alert thresholds/acknowledgement first;
do not infer offline connectivity or automatically change driver status. Physical IoT
integration remains a separately authorized phase after exact hardware selection.

Complete changed-file inventory for this phase:

- `admin-web/src/LiveMonitoring.tsx`, `MonitoringMap.tsx`, `monitoring.ts`,
  `useMonitoring.ts`, `monitoring.css`, `monitoring-fixture.ts`, `LiveMonitoring.test.tsx`.
- `admin-web/src/App.tsx`, `App.test.tsx`, `api.ts`, `DeviceManagement.tsx`,
  `DeviceManagement.test.tsx`.
- `admin-web/package.json`, `admin-web/package-lock.json`, `admin-web/.env.example`.
- `backend/src/admin-monitoring.js`, `admin-monitoring-repository.js`, `admin-auth.js`,
  `app.js`, `server.js`.
- `backend/migrations/009_monitoring_receipts.sql`, `backend/scripts/pg-integration.js`,
  `backend/test/monitoring.test.js`, `backend/test/monitoring-postgres.test.js`.
- `README.md`, `backend/README.md`, `docs/ADMIN_WEB.md`, `docs/API_MODE.md`,
  `docs/DEVICE_MANAGEMENT.md`, `docs/PROJECT_BRIEF.md`, `docs/LIVE_MONITORING.md`.

Owner thesis/ERD edits, local screenshots, dependencies, build output and all private
configuration are excluded from this commit.
