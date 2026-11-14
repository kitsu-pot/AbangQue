# AbangQue backend

Phase 5 update (2026-11-14): [IoT Device Management](../docs/DEVICE_MANAGEMENT.md) adds registrations, assignments, access controls and one-time credentials through migration 008. Earlier device-registry deferral notes are historical.

Node.js 24, Express 5, JavaScript ES modules, PostgreSQL. Flutter now has a separate
passenger API adapter with selectable offline demo mode. Nothing is deployed. No ESP32, GPS, official route, or real
ETA integration is claimed by this scaffold.

## Check without a database

From PowerShell in the project root:

```powershell
cd backend
node --version  # must be v24.x
npm ci
npm run check
npm test
```

Tests inject a repository double and clock into the real Express app. They test
HTTP behavior without PostgreSQL. SQL adapter tests use a mock client: they do
**not** prove that migrations, constraints, transactions, or queries work against
a real PostgreSQL server. That verification remains a required next step.
The server and all scripts use Node's built-in environment-file loading.

## Exact local database setup (Windows, PostgreSQL 18)

1. Install Node.js 24 if needed. Install PostgreSQL 18 using the installer linked
   by [PostgreSQL's Windows download page](https://www.postgresql.org/download/windows/).
   Select Server and Command Line Tools. Keep local port 5432, choose your own
   administrator password, and start its Windows service. No installer has been
   run by this task.
2. Open PowerShell and check/start the service (starting may require an elevated
   terminal). Adjust the service name only if your installation chose another:

```powershell
Get-Service *postgres*
Start-Service postgresql-x64-18
& 'C:\Program Files\PostgreSQL\18\bin\pg_isready.exe' -h 127.0.0.1 -p 5432
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h 127.0.0.1 -U postgres -d postgres
```

3. In that psql session run the following. The password command prompts securely;
   choose a new password rather than using an example secret:

```sql
CREATE ROLE jeeplink_app LOGIN;
\password jeeplink_app
CREATE DATABASE jeeplink OWNER jeeplink_app;
\q
```

4. From the backend directory create local configuration:

```powershell
Copy-Item .env.example .env
notepad .env
```

Set DATABASE_URL with the password you chose. URL-encode special characters in
the username/password. Leave HOST=127.0.0.1 and INCLUDE_DEMO=false initially.
.env is ignored by Git; .env.example contains no working secrets. The local
database owner is convenient for development. Use separate migration and
least-privilege runtime roles before any deployment.

5. Apply the schema and start the API:

```powershell
npm run migrate
npm run migrate  # should be a no-op on the second run
npm start
```

Migrations run in one transaction, with an advisory lock and checksum ledger.
Do not edit applied migrations: add a numbered SQL file for changes. There is
no destructive automatic down-migration.

6. In another PowerShell terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:3000/health
Invoke-RestMethod http://127.0.0.1:3000/api/jeepneys
```

Expect health 200 with database reachable, and initially an empty data array.
Health 503 means the database query failed; it never asserts GPS functionality.
A reachable database does not prove migrations have been applied.

## Optional historical DEMO data

```powershell
npm run seed:demo
```

Set INCLUDE_DEMO=true in .env and restart the server to see DEMO-01 and DEMO-02.
The fixed historical fixtures are intentionally stale and idempotently seeded.
They have source=demo, isDemo=true, connectionStatus=DEMO, and cannot receive
authenticated device updates. No device credentials are seeded. status is null
when stale; lastReportedStatus preserves the historical FULL/AVAILABLE sample.

Demo rows are excluded by default from both list and detail endpoints. A caller
cannot enable them with a query parameter. No routes, stops, fares, or ETAs are
seeded.

## Register a lab device (manual setup after migrations)

Use psql connected to the jeeplink database as jeeplink_app:

```sql
INSERT INTO jeepneys(id, name, source)
VALUES ('LAB-001', 'Synthetic lab vehicle - not verified GPS', 'device');
```

LAB-001 is a deliberately fictional test ID, not an official registration.
Then, from backend:

```powershell
npm run device:create -- LAB-001
```

This generates a random 256-bit secret, stores only its SHA-256 hash, and prints
the bearer token ONCE for provisioning. Do not redirect this command into shared
logs. Provision it on that device only. Never include it in passenger Flutter
code, assets, dart-define, source control, screenshots, or client configuration.
The token format is credential UUID + dot + random secret. It is **not** a
passenger login credential.

To test from a separate terminal without putting the token into command history:

```powershell
$deviceToken = Read-Host 'Paste the lab device token' -MaskInput
$update = @{
  jeepneyId = 'LAB-001'
  latitude = 13.4490
  longitude = 121.8374
  status = 'AVAILABLE'
  timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:3000/api/device-updates -ContentType 'application/json' -Headers @{ Authorization = "Bearer $deviceToken" } -Body $update
Remove-Variable deviceToken
Invoke-RestMethod http://127.0.0.1:3000/api/jeepneys/LAB-001
```

Read-Host -MaskInput requires PowerShell 7.1+. Use a secure API client instead on
Windows PowerShell 5.1. This is simulated test telemetry over localhost, not proof
of live GPS tracking. Reuse the same timestamp to verify HTTP 409. After 120
seconds without a fresh accepted sample, reads report OFFLINE with status=null.

Revoke a credential with this SQL, replacing the UUID:

```sql
UPDATE device_credentials SET revoked_at = now()
WHERE id = 'REPLACE_WITH_CREDENTIAL_UUID';
```

Generate a new credential to rotate it and revoke the old one. Authentication is
checked on every request and again under a transaction lock before insertion.
The schema binds credentials to device-source vehicles and updates to the
credential's assigned jeepney.

## API contract

All responses are JSON. Passenger GET requests need no device credentials.

| Method / path | Behavior |
| --- | --- |
| GET /health | 200 database reachable; 503 unreachable; gpsTrackingVerified=false |
| GET /api/jeepneys | data array and meta; sorted by ID; demo hidden by default |
| GET /api/jeepneys/:id | data object; 400 invalid ID; 404 missing/hidden |
| POST /api/device-updates | Bearer device token + application/json; 201 accepted |

POST accepts exactly these fields:

```json
{
  "jeepneyId": "LAB-001",
  "latitude": 13.449,
  "longitude": 121.8374,
  "status": "AVAILABLE",
  "timestamp": "2026-10-31T00:00:00.000Z"
}
```

Replace the example timestamp with current device UTC time. Coordinates must
be JSON numbers in valid geographic ranges. Status is exactly FULL or AVAILABLE.
Timestamps require an ISO 8601 timezone; invalid dates, unexpected fields,
missing values, timestamps older than MAX_UPDATE_AGE_SECONDS (24 hours) or
more than MAX_FUTURE_SKEW_SECONDS (30 seconds) ahead are rejected.

Responses: 400 invalid payload/time/JSON; 401 missing/invalid/revoked token;
403 wrong jeepney; 409 duplicate credential+measurement timestamp; 413 body over
8 KB; 415 wrong content type; 429 rate limited; 503 database/internal failure.
Do not retry 4xx without correcting the request, except 429 with backoff.
Duplicate retries do not update last-seen. There is no sequence-number protocol
yet; devices must synchronize time and use distinct timestamps per sample.

Passenger data fields:
- id, name, source (device/demo), isDemo.
- position: latitude/longitude or null before the first update.
- timestamp: latest measurement time, not receipt time.
- lastSeenAt: latest accepted server receipt time, never the caller's clock.
- connectionStatus: ONLINE/OFFLINE/DEMO; ONLINE means fresh accepted telemetry,
  not verified hardware, service availability, or authenticity of GPS readings.
- isStale: either measurement or receipt is at least STALE_AFTER_SECONDS old,
  or no sample exists.
- status: current FULL/AVAILABLE, or null when stale.
- lastReportedStatus: historical status even when offline.
- eta: always null. No arrival calculation or official route fields.

Late but valid updates are retained as history. The latest vehicle position is
selected by measurement timestamp, so an old packet cannot replace a newer
position. Fresh receipt of an old measurement alone cannot make it ONLINE.
Offline status is calculated on every read; no timer or cron job is needed.
Clients must poll/refetch to see changes. Lists currently return the small full
fleet; add pagination/history retention before larger deployments.

## Structure and Flutter integration

The passenger API adapter is now implemented separately in Flutter. See
[API mode instructions](../docs/API_MODE.md). The integration notes below explain
why the adapter preserves unknown counts, stale status, and null ETA.

src/app.js is the injectable Express composition; server.js owns the HTTP server
and database pool. repository.js contains parameterized PostgreSQL queries.
validation.js, security.js, and presenter.js separate input validation,
credential hashing, and freshness/presentation. migrations/ contains schema;
seeds/ contains only optional demo fixtures; scripts/ contains local admin tools.

The Flutter model has no numerical seat or occupancy fields. Its API adapter
supports nullable positions,
unknown/stale status, source labels and null ETA. Historical DEMO fixtures are
explicitly labeled and never counted as current availability.

No browser CORS origins are enabled yet; native Android is not subject to browser
CORS. Configure an explicit allowlist if a web passenger client is added.
The default loopback listener is not reachable from a physical phone. Android
emulator debug networking and HTTPS release requirements are documented in
the linked API mode instructions.
Before remotely connecting ESP32 devices, use HTTPS and validated certificates;
do not expose bearer tokens over plain HTTP. Local HTTP here is for loopback
development only. The rate limiter is per IP in memory; it resets on restart.
Keep trust proxy disabled until the actual proxy topology is configured; use a
shared store and device-specific quotas if deploying multiple instances.

## Database and hardware verification

`npm run test:postgres` runs real PostgreSQL authentication, simulated-device and
favorite-route HTTP tests in isolated temporary schemas. It requires the configured
local development database and removes only its generated test schemas. Ordinary
`npm test` remains database-free; its skipped integration cases run through that
explicit command. `npm run test:gps:flutter` separately checks the Flutter/HTTP/SQL
simulator path. Neither command verifies physical GPS hardware, road operation or
phone performance. No deployment or real ETA calculation is implemented.

References: [Express error handling](https://expressjs.com/en/5x/guide/error-handling/),
[node-postgres parameterized queries](https://node-postgres.com/features/queries).


## Passenger accounts (2026-11-01)

Migration 002_passenger_auth.sql adds passenger-only accounts and expiring,
revocable sessions. Run npm ci and npm run migrate, then restart the backend.
New auth settings and all endpoints are documented in
[AUTHENTICATION.md](../docs/AUTHENTICATION.md). Public jeepney GETs stay unauthenticated.
The real PostgreSQL suite is npm run test:postgres (isolated temporary schema).
Default npm test stays database-free and skips that explicit integration suite.
No account credentials are seeded. No admin login or password reset is implemented.

## Development GPS simulator

Migration 003 adds an explicit simulated source to vehicles, credentials and updates.
The existing authenticated device endpoint is reused. `GET /api/routes` returns an
active registered catalog (initially empty), plus an explicitly DEMO test direction
only when local simulation is enabled and the reserved test vehicle is provisioned.
Migration 004 supplies route storage; admin management is not implemented. Read [GPS_SIMULATOR.md](../docs/GPS_SIMULATOR.md)
for the exact opt-in guards, setup, commands, revocation and database/Flutter tests.


## Favorite Routes (2026-11-07)

Migration 004_favorite_routes.sql adds an empty registered_routes catalog and
passenger_favorite_routes with stable UUID references, per-passenger uniqueness,
account deletion cascade and unavailable-route retention. No operating directions
are seeded; no real jeepney assignments are created. GET /api/routes reads active
registered records alongside the separately gated simulator catalog.

Authenticated PASSENGER only: GET /api/favorites, PUT /api/favorites/:routeId,
DELETE /api/favorites/:routeId. Identity always comes from the live session;
client-supplied user IDs are rejected. PUT/DELETE are idempotent, production requires
HTTPS, and public transport reads remain guest-accessible. No new environment
variables are needed. Run npm run migrate and restart npm start.

See [Favorite Routes](../docs/FAVORITE_ROUTES.md) for contracts and the Infinix
checklist. npm run test:postgres now includes real registration/login/favorites
HTTP tests in isolated PostgreSQL schemas, alongside existing auth/GPS regressions.
Earlier database-free verification limitations above describe those checks only;
physical GPS/device operation and deployment remain unverified.


## Passenger account management (2026-11-10)

The existing `/api/auth/me` profile endpoint is extended with authenticated
`POST /api/auth/me/password` and `DELETE /api/auth/me`. Sensitive operations require
current-password verification and share IP/account limits. Password change revokes
other sessions; deletion transactionally cascades only to the passenger's sessions
and favorites. Login is synchronized with those changes to reject stale credentials.
No new migration, dependency, environment variable, route seed or schema reset is
needed for an existing setup. Restart the backend after updating.

See [Account Management & Privacy](../docs/ACCOUNT_MANAGEMENT.md) for request bodies,
errors, session behavior, privacy/retention boundaries and the phone checklist.
`npm run test:postgres` includes the new isolated account-management SQL/API suite,
with forced rollback, concurrent requests and account-isolation regressions.

## Administrator web and Jeepney Management

The React admin frontend uses this same API and database. Run `npm run migrate`
through migration 006 and restart the API. If no admin exists, provision the first
account with `npm run admin:provision` in local development.
See [ADMIN_WEB.md](../docs/ADMIN_WEB.md) for exact PowerShell
commands, cookie/CSRF configuration, endpoints, testing and future HTTPS hosting.
See [JEEPNEY_MANAGEMENT.md](../docs/JEEPNEY_MANAGEMENT.md) for the admin management
endpoints, optional route assignments, reversible activation, preserved device
ingestion, passenger filtering and PostgreSQL verification. No seeds are required.
