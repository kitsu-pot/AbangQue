# Admin Jeepney Management — Phase 3

Phase 5 update: [IoT Device Management](DEVICE_MANAGEMENT.md) now supplies device administration. Earlier device-module deferral notes below are historical.

Phase 4 update (2026-11-14): [Route Management](ROUTE_MANAGEMENT.md) now supports verified directions, operational metadata and reversible route activation. Earlier route-deferral notes below are historical.

Implemented 2026-11-13 in the existing React admin web and Express/PostgreSQL
backend. Checkpoint `checkpoint/jeepney-management-2026-11-13` preserves `4d7be55`.
This phase makes **Jeepneys** functional; Route Management, IoT Device Management,
Live Monitoring, driver accounts and deployment remain outside this phase.

## Run or update locally (Windows PowerShell)

Use Node.js 24 and the existing local PostgreSQL configuration in ignored
`backend/.env`. Do not replace database credentials, reset the database or run
seeds. Stop an older API with Ctrl+C in its terminal before restarting it.

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

Open [the local admin web](http://127.0.0.1:5173/). Use 127.0.0.1 consistently for
the browser and API. Sign in with the existing administrator. Only if no admin
exists, run `npm run admin:provision` from `backend` and follow its secure prompts;
see [ADMIN_WEB.md](ADMIN_WEB.md). There is no default password or public signup.
No owner administrator or device credential was created by this phase.

## Register, edit and activate

1. Open **Jeepneys → Add Jeepney**. Supply the verified identifier, display name
   and Active/Inactive state. Optional fields may remain blank; **Unassigned** is
   valid when no eligible verified route exists.
2. Click **Register Jeepney** and wait for server confirmation. Registration
   creates a real vehicle record with `source=device`; it creates neither a GPS
   report nor an IoT credential. “Device record” does not prove working hardware.
3. Use **Edit**, change metadata/route, then **Save Changes**. The identifier is
   immutable because existing credentials and GPS history reference it.
4. Use **Deactivate → Confirm deactivation**, or **Activate → Confirm activation**.
   These change registration eligibility only, never the driver's FULL/AVAILABLE
   report. There is no hard-delete action.
5. **Details** shows administrative metadata, source, separate measurement and
   communication timestamps, last reported position and historical driver status.
   Details are a labeled snapshot; **Refresh details** retrieves a newer snapshot.

List search matches identifier, display name or plate literally, ignoring case.
Status/route filters and 20-record pages are server-backed. The list refreshes
every 30 seconds while visible. Phone widths use cards and scrollable dialogs.
DEMO/SIMULATED records are labeled, excluded from registration counts and read-only
here; existing simulator tooling remains responsible for those records.

| Field | Rule |
| --- | --- |
| Identifier | Required, 1–64 uppercase letters/digits/underscore/hyphen; starts with letter/digit; unique and immutable |
| Display name | Required, 1–120 characters; preserves the existing required `name` field |
| Active | Required boolean at creation; changes use the separate confirmation flow |
| Plate | Optional; uppercase, 2–20 letters/digits/spaces/hyphens, starts with letter/digit |
| Description | Optional plain text, maximum 500 characters |
| Administrative notes | Optional private admin text, maximum 2,000 characters; absent from passenger responses |
| Route | Optional existing active registered-route UUID; never a typed municipality pair |

Text fields reject control characters/line breaks. There is **no unique plate
constraint** because no verified business rule was supplied. Duplicate IDs return
409. Plates remain metadata until the owner establishes the registration policy.
No operator/cooperative data is invented.

## Schema, routes and telemetry

Migration [006_jeepney_management.sql](../backend/migrations/006_jeepney_management.sql)
adds `active`, `plate_number`, `description`, `administrative_notes`, nullable
`route_id`, optimistic-lock `version` and `updated_at` to the existing `jeepneys`
table. Existing vehicles default to active, preserving prior eligibility. They
remain unassigned; no pre-existing real route relation existed. The initial
`updated_at` for existing records is the migration time, not a claimed past edit.
There are no seed rows or new vehicle tables. The checksum/advisory-lock migration
runner applies this transactionally once. Repeating `npm run migrate` is safe.
Migration 006 was applied successfully to the local database during this task.
No seed commands were run.

A vehicle has zero or one current registered direction. The foreign key restricts
route deletion while assigned. Only `source=device` records may have this real
route assignment. UUID identity, origin and destination are preserved: Boac →
Gasan and Gasan → Boac are different directions if separately registered. Those
examples are not claims that either route is an approved operating service.

Inactive routes are shown as inactive and disabled for new assignments. An existing
inactive assignment can be retained during unrelated metadata edits or cleared.
The server rechecks route eligibility inside the write transaction and holds a
shared route lock. No routes are automatically created, enabled or changed.

Deactivation retains the vehicle, credential bindings and all GPS history.
Authenticated device ingestion still accepts updates for an inactive vehicle:
administrative eligibility is separate from credential revocation. Existing
validation, duplicate handling, hashes, revocation and source checks are unchanged.
Reactivation changes no measurement timestamp and never writes AVAILABLE.

GPS freshness requires recent measurement **and** receipt, with neither in the
future. Missing/expired reports and inactive or DEMO/SIMULATED records have UNKNOWN
current driver availability. Historical FULL/AVAILABLE is explicitly labeled
“last reported … not current availability.” No coordinates, seat counts or ETA
estimates are generated. ETA remains unavailable.

Dashboard registration totals include active and inactive real vehicles. Fresh,
FULL, AVAILABLE and stale/missing operational counts include active real vehicles
only. Recent activity may show inactive registrations, labeled accordingly; its
driver status is UNKNOWN. A fresh accepted report is not hardware verification.

## Admin API

All paths below are under `/api/admin`. They require the existing server-verified
ADMIN cookie; passenger bearer tokens and guests cannot authorize them. POST/PUT
also require exact allowed `Origin`, `X-AbangQue-Admin: 1` and JSON. Authorization
and CSRF middleware run before management handlers. Writes are limited to 60 per
minute per administrator, with the existing single-process limiter limitation.
Responses use `{ data: ... }` or `{ error: code, fields?: [...] }`, with no-store.

| Method/path | Input/result |
| --- | --- |
| GET `/route-options` | Array `{id,origin,destination,active}`; includes inactive choices for truthful existing assignments |
| GET `/jeepneys` | `search`, `status=all\|active\|inactive`, `routeId=all\|unassigned\|UUID`, `page` (1–100000), `pageSize` (1–100, default 20) |
| GET `/jeepneys/:id` | `{record,updatedAt,staleAfterSeconds}`; snapshot time is distinct from record metadata time |
| POST `/jeepneys` | `{id,name,active,plateNumber,description,administrativeNotes,routeId}` → 201 record |
| PUT `/jeepneys/:id` | `{name,plateNumber,description,administrativeNotes,routeId,expectedVersion}` → updated record |
| POST `/jeepneys/:id/activation` | `{active,expectedVersion}` → updated record |

List data is `{items,total,registeredTotal,page,pageSize,updatedAt,staleAfterSeconds}`.
`total` matches filters and may include labeled test rows; `registeredTotal` is
the unfiltered real-registration count. Optional plate/route values use `null`;
optional text uses empty strings. The UI supplies all declared fields. Unknown
body/query fields are rejected, including source, GPS, driver status and credentials.

Records expose only selected metadata/report fields. They never return credential
secrets, hashes or admin password/session storage. Queries are parameterized;
pagination/counts use one repeatable-read snapshot. Updates lock the vehicle and
compare `expectedVersion`; successful writes increment it. Two concurrent saves
cannot silently overwrite each other. Relevant responses:

- 400: invalid input/identifier; field errors when applicable.
- 401/403: missing or expired admin session, or rejected origin/CSRF request.
- 404: missing vehicle.
- 409: `JEEPNEY_ID_EXISTS`, `RECORD_CHANGED`, `ROUTE_INELIGIBLE` or
  `TEST_RECORD_READ_ONLY`.
- 413/415/429: excessive body, wrong content type or write throttling.
- 500/503 or network timeout: safe failure; no database internals returned.

The UI prevents duplicate in-flight saves and retains entries after failed writes
while the session remains valid. A timeout/server error can follow a committed
write, so the UI explicitly says the outcome is unconfirmed. Check the list before
retrying. Version conflicts require reopening the latest record and reviewing the
changes. Session expiry returns to the protected sign-in flow; unsaved fields are
not persisted to browser storage.

## Passenger compatibility and verification

No Dart files changed. `/api/jeepneys` excludes inactive records, and
`/api/jeepneys/:id` returns 404 for an inactive vehicle. `/api/routes` keeps the
existing `{routes,assignments}` contract and now returns assignments for active
real vehicles on active registered routes. Unassigned vehicles appear in no route
assignment. Changed assignments replace the old direction after successful refresh.

The public vehicle list may still contain active unassigned records; the existing
Flutter controller requires a matching explicit route assignment before showing
journey results. Vehicles with no GPS can have a card but no invented map marker.
Offline caches cannot learn an activation/route change until a successful refresh;
cached availability remains UNKNOWN under the existing passenger rules.

With the API running, read public results in PowerShell:

```powershell
$catalog = (Invoke-RestMethod http://127.0.0.1:3000/api/routes).data
$catalog.routes | Format-Table id, origin, destination
$catalog.assignments | Format-Table routeId, jeepneyId
(Invoke-RestMethod http://127.0.0.1:3000/api/jeepneys).data |
    Select-Object id, status, position, timestamp, lastSeenAt, isStale
```

Use actual owner-verified records when performing local administration. With an
eligible route, assign a vehicle and refresh passenger data; confirm the UUID in
`assignments`. Change direction and confirm the old assignment is absent. Deactivate
and confirm absence from both public lists and 404 for its details. Reactivate and
confirm that stale measurements remain stale. Do not create fictional routes just
to demonstrate this: the integration suite covers these cases in disposable schemas.

For physical Android testing, retain the existing USB/API workflow in
[API_MODE.md](API_MODE.md). No new physical-phone or hardware verification is claimed.

## Automated checks and observed browser scope

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm run check
npm test
npm run test:postgres
Set-Location ..\admin-web
npm run lint
npm run typecheck
npm test
npm run build
```

The PostgreSQL runner uses random isolated schemas and removes them afterward;
it needs CREATE SCHEMA on the existing local test database connection. It verifies
migration preservation, real admin/passenger authentication, registration, strict
validation, duplicates, route direction/eligibility, concurrency, search/pagination,
deactivation/history, continued device ingestion and dashboard counts. The ordinary
backend run intentionally skips PostgreSQL suites; run `test:postgres` separately.

Browser checks were actually performed against an isolated temporary PostgreSQL
schema and temporary test administrator, with a visible DEMO QA banner: empty list,
create, edit, details, deactivate and reactivate, desktop 1440px and mobile 390px
layouts/cards/dialogs, and no horizontal document overflow at the mobile width.
No browser console errors were observed. QA records/schema were removed afterward;
they were never operating/public-schema records. Route choices and error/race cases
were automated tests, not manual real-route or hardware tests.

Observed final results on 2026-11-13: backend syntax check passed; 49 database-free
tests passed (six PostgreSQL suites intentionally skipped in that command); all
51 PostgreSQL tests passed; frontend lint, TypeScript and production build passed;
all 19 frontend tests passed across three files. `npm audit` reported zero known
vulnerabilities. No Flutter tests were rerun because no Dart files changed.

ESLint/typescript-eslint were added as development dependencies, without a runtime
UI dependency. The transitive `minimatch` override pins 11.0.1 to fix
[GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249).
Reassess the override when upstream lint dependencies adopt the fix.

## Changed implementation files and remaining scope

| Area | Files |
| --- | --- |
| Management UI | `admin-web/src/JeepneyManagement.tsx`, `jeepneys.ts`, `jeepneys.css`, component tests |
| Existing admin integration | `admin-web/src/App.tsx`, `api.ts`, navigation tests, ESLint config, package/lock files |
| Admin API/persistence | `backend/src/admin-jeepneys.js`, `admin-jeepney-repository.js`, `admin-auth.js`, `app.js`, `server.js` |
| Public compatibility/dashboard | `backend/src/repository.js`, `favorite-repository.js`, `admin-repository.js` |
| Schema/tests | migration 006, management unit/PostgreSQL suites, shared test migration helper, existing PostgreSQL suite migration loading, PostgreSQL runner |
| Documentation | this guide, ADMIN_WEB, PROJECT_BRIEF, API_MODE, route/favorites guides and root/backend READMEs |

Next phases still need verified route records/Route CRUD, a physical-device
registry/provisioning UI, real hardware acceptance and any approved deployment.
No route/IoT CRUD, driver account, passenger counting, seat calculation, admin
availability toggle, ETA algorithm or online deployment was added. Administrative
metadata has optimistic versions but no new audit-history subsystem. Plate
uniqueness policy and owner/phone acceptance remain decisions/checks for the owner.
