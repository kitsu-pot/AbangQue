# Admin IoT Device Management — Phase 5 (2026-11-14)

Phase 6 update (2026-11-14): [Admin Live GPS Monitoring](LIVE_MONITORING.md) now provides the protected report map, filters and historical device/vehicle details. Migration 009 adds one receipt lookup index; earlier Live Monitoring deferral notes are historical.

IoT Devices now supports registration, metadata, vehicle assignment, enable/disable,
one-time credential provisioning/rotation, revocation, reporting snapshots, filters
and pagination. It reuses Express, PostgreSQL, administrator sessions and the
existing device-update protocol. There are no driver accounts or admin driver-status
controls. No firmware, operating GPS reports, heartbeat, ETA or deployment was added.
Checkpoint: `checkpoint/device-management-2026-11-14`.

## Architecture and migration

Migration `008_device_management.sql` was applied locally. Existing tables held
credential versions bound to jeepneys, not stable physical-device identities.
`iot_devices` therefore supplies stable registrations, with credentials continuing
in `device_credentials` and reports in `location_status_updates`. It stores ID,
optional label/model/description/private notes, source, legacy flag, enabled state,
nullable assignment, version and creation/update times. IDs are immutable in the API.

Each old vehicle's credentials are linked to one `LEGACY-<jeepney ID>` registration.
This represents the old vehicle-bound identity, **not verified individual hardware**.
Multiple old keys remain linked to that registration, with their original UUIDs,
hashes, creation/revocation times, source and GPS references unchanged. Nothing is
rehashed, automatically rotated or transferred. If old keys actually belong to
multiple physical units, the owner must identify them and deliberately replace them
with individually registered devices. A registration count is not hardware proof.

Existing simulator credentials and SIM-GPS-001 remain simulated and unchanged.
Their legacy registration is labeled DEMO / SIMULATED and read-only in the admin
UI/API. Production rejects simulator ingestion under existing safeguards.

A partial unique index permits at most one **enabled** assigned device per jeepney.
Disabled registrations may retain assignments. Enabling or assigning a conflicting
device returns 409; no implicit replacement occurs. Explicitly disable or unassign
the incumbent first. New assignments/provisioning require an active `source=device`
jeepney. Unassigned registration is allowed and has no report or credential.

`device_credentials.device_id` links immutable credential versions to the registry.
Credential ID, hash, source and historical vehicle binding cannot be edited. A
compatibility trigger attaches old CLI-created credentials to a legacy registration;
it does not overwrite an existing registration or bypass enabled/assignment checks.
Old CLI provisioning conflicts with an enabled separately registered device on the
same vehicle. Use the admin provisioning flow for new hardware. Simulator CLI tools
continue to use their existing ignored credential file; no file was overwritten.

Reassignment/unassignment revokes all old keys in the same transaction. A newly
assigned vehicle receives no historical coordinates. Provision a new key after
reassignment. The device details retain original report vehicle IDs so historical
activity cannot be mistaken for the new assignment. Jeepney routes are unchanged.

## Register and manage a device

1. Open **IoT Devices → Add Device**. Choose a unique ID (1–96 uppercase letters,
   digits, underscore/hyphen; start with letter/digit). `LEGACY-`, `SIM-`, `DEMO-`
   prefixes are reserved. Enter optional owner-recorded metadata only.
2. Select Enabled/Disabled and optionally an eligible jeepney. Unknown model or
   assignment may remain blank. Registration creates no keys or reports.
3. Open **View [ID] → Manage device** for metadata, assignment and access actions.
   Assignment changes, disabling, revoking and credential generation have explicit
   confirmation steps. Conflicting assignments cannot replace another device silently.
4. Metadata limits: label/model 120, description 500, administrative notes 2,000
   characters. Both UI and server validate; text is trimmed, nullable and rejects
   control characters/line breaks. Plate numbers come from Jeepney Management.

Enabled is administrative permission, not online status. Disabled rejects new
updates but retains stored keys/history. Enabling can restore an existing valid key.
Revocation invalidates every current key; enabling alone cannot undo revocation.
Provisioning after revocation creates a new key. No hard-delete workflow exists.
Vehicle deactivation continues the earlier policy: hide passenger service while
retaining authenticated ingestion. Disable the **device** to stop its reports.
Already accepted passenger reports still age under the existing freshness rules;
disabling/revoking a key does not rewrite a previous driver report. Deactivate the
jeepney separately when it should be removed from passenger service listings.

## Credential security and recovery

Use **Provision credentials → Generate one-time credential** for an enabled device
assigned to an active real jeepney. If a valid credential already exists, use
**Rotate credentials**. Rotation generates cryptographically random material using
the existing `issueCredential()` function: a credential UUID plus 32 random bytes,
serialized as `credential-uuid.secret-hex`. PostgreSQL stores only its SHA-256 secret
hash. This high-entropy random-secret design is distinct from password hashing.

The generated token appears only in the successful provisioning/rotation response
and a dedicated one-time dialog. List/details/audit responses contain neither token
nor verification hash. The UI stores it only in component memory, never localStorage,
sessionStorage, URL, clipboard automation or persisted frontend storage. Close the
dialog or leave the module and it disappears; JavaScript memory cannot promise
immediate physical erasure. Transfer it securely to the intended hardware locally.
Never paste it into chat, screenshots, source, analytics or terminal/log recordings.

Credential creation, old-key revocation, version increment and audit event commit
atomically. A database/generation failure rolls back and keeps the old valid key.
After a successful rotation the old key stops working immediately; the hardware
must receive the replacement. If the HTTP response is lost **after commit**, the new
key may already be active but unrecoverable. The UI says the outcome is unconfirmed:
reload the device, then intentionally rotate again. No plaintext recovery endpoint
or persisted idempotency secret is provided. Do not blindly retry a timed-out write.

Existing device keys have no automatic expiry field; they remain usable until
revoked, rotated, disabled or unassigned. Administrator sessions retain their existing
absolute expiry. Time-based key expiration is a future explicit policy decision.

## Authentication and reporting contract

The existing `POST /api/device-updates` contract is unchanged:

| Part | Required value |
| --- | --- |
| Authorization | `Bearer <credential-uuid>.<secret-hex>` |
| Content-Type | `application/json` |
| jeepneyId | Exact current assigned jeepney identifier |
| latitude / longitude | Numeric actual GPS coordinates within validated ranges |
| status | Driver-selected `FULL` or `AVAILABLE` |
| timestamp | Actual GPS measurement time with timezone |

Do not submit sample coordinates as physical reports. Source comes from the database,
never from a payload. Existing timestamp-window validation, duplicate timestamp 409,
rate limits and out-of-order measurement behavior remain. Accepted response 201
records server receipt time; it does not prove physical GPS accuracy or cellular
operation. Missing/invalid/revoked/disabled credentials return 401, wrong vehicle
403, simulation-disabled 403, invalid input 400 and safe service failure 503.

Ingestion locks the device registration before the credential, then rechecks enabled
state, current assignment and revocation before inserting. Admin changes use the
same lock order. Requests authenticated just before disabling/reassignment cannot
skip the transactional recheck. Historical records remain linked to their original
credential and jeepney forever.

Freshness uses the existing `STALE_AFTER_SECONDS` (default 120): both measurement and
last accepted receipt must be present, not in the future and younger than the limit.
The device snapshot uses its latest measurement and latest communication across
credential versions/assignments. Details identify the historical report vehicle.
No reports means **No reports**, never Online. Freshness and access are separate:
a recently disabled device can still have a recent historical report. Its current
driver status is UNKNOWN. Revoked/unassigned, mismatched historical assignment,
inactive jeepney and simulated current availability are also UNKNOWN.

The list polls every 30 seconds while visible and no dialog is open. Row freshness
ages between reads using server-relative elapsed time; current summary reporting
counts are hidden after the earliest expiry until refreshed. Detail snapshots have
an explicit refresh button and timestamp. This is accepted-report activity, not
continuous tracking, hardware health, heartbeat or independently verified GPS.

Dashboard Registered Devices now counts real registry entries, including disabled
and legacy registrations, excluding simulated records. Device-page reporting counts
are independent of access state. No credential count is labeled a physical unit.

## Protected admin API and audit

All paths use `/api/admin`. Existing ADMIN cookie/session/role validation applies;
passenger/device tokens cannot authorize these endpoints. Writes require exact
allowed Origin, `X-AbangQue-Admin: 1`, JSON and strict body validation. Sensitive
writes share a 20-per-minute per-admin limiter (single-process memory, as in earlier
phases). Reads are no-store. HTTPS remains mandatory for production admin access.

| Method/path | Input/result |
| --- | --- |
| GET `/devices` | search, reporting=all/fresh/stale/missing, assignment=all/assigned/unassigned, state=all/enabled/disabled, page, pageSize (default 20, max 100) |
| GET `/devices/:id` | Selected safe record/report fields, latest 20 audit events, snapshot time and stale threshold |
| GET `/device-jeepney-options` | Real vehicle IDs, plates, names and active flags; inactive options disabled |
| POST `/devices` | id, label, model, description, administrativeNotes, enabled, jeepneyId |
| PUT `/devices/:id` | label, model, description, administrativeNotes, expectedVersion |
| POST `/devices/:id/assignment` | jeepneyId (nullable), expectedVersion |
| POST `/devices/:id/state` | enabled, expectedVersion |
| POST `/devices/:id/provision` | expectedVersion; returns one-time token/jeepneyId |
| POST `/devices/:id/rotate` | expectedVersion; replaces all current keys and returns one-time token/jeepneyId |
| POST `/devices/:id/revoke` | expectedVersion; revokes all current keys |

List/counts use a consistent read transaction. Metadata, assignment, state and key
operations use row locks plus optimistic versions; stale/concurrent writes return
409 and retain form input. Input 400, auth 401/403, missing device 404, conflicts 409,
wrong type 415, large body 413, throttling 429 and sanitized database failures 503
follow existing conventions. Secrets are not included in errors or logs.

`admin_device_events` records successful REGISTER, EDIT, ASSIGN, ENABLE, DISABLE,
PROVISION, ROTATE and REVOKE with actor ID, device ID, version, prior/new assignment
and server time. It never stores tokens, hashes, payloads or coordinates. Mutation
and audit commit together. Legacy CLI events have no invented admin actor/event;
they are not retroactively attributed. Audit retention and operational security
monitoring are future deployment work.

## Exact Windows PowerShell setup and checks

Stop an older API in its own terminal before starting the updated code. Existing
ignored `backend/.env` remains the source of database configuration.

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm ci
npm run migrate
npm start
```

Second terminal:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\admin-web
npm ci
npm run dev
```

Open http://127.0.0.1:5173 and sign in with the existing admin. No owner account,
default password, public provisioning endpoint or seed command is introduced.
Migration 008 was applied locally; the checksum ledger makes repeats safe.

Verification commands (disposable test schemas, no operating test reports):

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm run check
npm test
npm run test:postgres
Set-Location ..\admin-web
npm run lint
npm run build
npm test
```

Observed: backend syntax check and 54 database-free tests passed (eight SQL suites
skipped in the ordinary run); all 61 PostgreSQL tests passed. Frontend lint,
TypeScript/production build and 28 tests passed. SQL tests cover preserved legacy
credentials, authenticated updates, simulator isolation, assignment conflicts,
concurrent edits, disable rechecks, failed/successful rotation, revocation,
reassignment history, missing/stale reports, read secrecy and dashboard counts.
UI tests cover duplicate forms, confirmation cancellation, conflict retention,
single-flight one-time token display, no browser-storage writes, expiry, outages
and truthful freshness. Existing Jeepney/Route/passenger suites passed.

Flutter code was unchanged, so Flutter tests were not rerun. No physical IoT hardware
or manual browser visual acceptance was performed. Responsive layouts reuse tested
admin cards/dialogs but still need owner browser acceptance at desktop/mobile widths.
No simulator was run outside automated compatibility tests.

## Future ESP32 preparation and remaining work

After selecting and verifying actual ESP32/GPS/LTE models, provision each hardware
unit with its exact jeepney ID, API HTTPS URL and individual token through a secure
local process. Keep credentials off passenger apps and logs. Firmware must use
certificate validation, valid actual GPS measurements/timestamps, manual driver
input and bounded retries. Coordinate reboot/time synchronization, duplicate 409,
401 reprovisioning and connectivity recovery in the hardware phase. Exact storage,
TLS, power, wiring and modem behavior depend on selected parts; no firmware or
wiring specification is claimed here. Never connect vehicle 12V directly to ESP32.

Recommended next phase: select/verify hardware and establish a secure bench
provisioning/reporting acceptance plan. Live Monitoring remains separately scoped.
No deployment, new driver accounts, seat counting, ETA or remote availability toggle.

Changed implementation files: migration 008; new `admin-devices.js` and
`admin-device-repository.js`; auth/app/server wiring, ingestion repository and
dashboard repository; device unit/SQL suites and SQL runner/fixture migrations;
`DeviceManagement.tsx`, component tests and `devices.css`; admin navigation/dashboard
and placeholder tests. Documentation adds this guide and updates overview/setup
references. No new dependencies. Unrelated thesis edits remain outside this phase.
