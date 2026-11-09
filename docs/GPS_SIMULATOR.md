# Jeepney details and local GPS simulation

Implemented 2026-11-01. Pre-change Git checkpoint: `16ecf3c`.

## What this demonstrates

The separate Node.js simulator sends changing coordinates and a manually chosen
FULL/AVAILABLE value through the existing authenticated `POST /api/device-updates`
endpoint. PostgreSQL stores the reports. Flutter reads them through the passenger
API, updates the selected jeepney and marker, and expires old status to UNKNOWN /
STALE. ETA stays unavailable. No passenger counts or driver accounts are added.

This is simulated communication testing, not ESP32, GPS, LTE, traffic, or road
accuracy verification. The short synthetic coordinate loop near Boac is not a road
trace or route geometry. The **Boac → Mogpog DEMO test direction** exists only to
exercise the municipality selector and explicit vehicle assignment. It is not an
operating route; the loop does not travel between those municipalities. Reverse
directions are independent, and no reverse test assignment is created.

The enhanced glass details show the identifier, direction, operator information
when supplied (currently unavailable), coordinates, measurement time, last server
receipt, connectivity/freshness, manual status and unavailable ETA. View last
location on map selects and focuses the latest position. The selected map panel
also follows subsequent reports. Coordinates remain last reports, including when
stale; they are not claimed to be a current position.

## Provenance and isolation

Migration `003_simulated_device_source.sql` extends existing source constraints
with `simulated` on jeepneys, device credentials and updates. This small migration
is necessary: the previous schema only allowed historical demo or device sources,
and labeling authenticated simulator packets as device data would misrepresent
them. Existing records, credentials, indexes and identifiers are preserved.

Credentials use the existing random device secret/hash and vehicle binding. The
server derives the update source from the database credential, never the request
body. Validation, rate limits, duplicate protection and revocation still apply.
Simulator credentials cannot submit to another jeepney.

Simulation requires all three server settings:

```dotenv
NODE_ENV=development
HOST=127.0.0.1
ENABLE_GPS_SIMULATOR=true
```

Other combinations fail startup configuration validation. When simulation is off,
simulated updates are rejected and simulated passenger records are hidden, even
if `INCLUDE_DEMO=true`. Production also rejects/hides simulation defensively.
The simulator client accepts only an HTTP `127.0.0.1` origin and refuses redirects.
It verifies the test vehicle and catalog before sending anything.

The public `GET /api/routes` returns an empty catalog normally. In explicitly
enabled local development, once `SIM-GPS-001` exists with source `simulated`, it
returns one `isDemo: true` direction and that vehicle's explicit assignment.
These fixtures live in `backend/src/simulation.js`; no route tables, admin tools,
official routes or inferred assignments are introduced. Historical DEMO vehicles
remain unassigned. Since the offline phase, HTTP 404 and other failed route reads retain a valid
cached catalog as unverified, or show a retryable error when no cache exists.
Only a valid successful catalog response can replace route records.

Flutter additionally requires `DEV_GPS_SIMULATION=true`, an API debug build, and a
local API origin. Release/profile, remote-origin and offline-DEMO configurations
reject this flag. Without it, the adapters discard simulated vehicles and DEMO
route records. Simulated vehicles can only appear under a DEMO direction, and
non-simulated vehicles cannot enter that direction even with a bad assignment.

The app never contains device secrets or simulation movement code. The separate
offline `DATA_MODE=demo` experience remains unchanged. Account login and guest
access remain independent of public route and jeepney reads.

## Local setup

Use Node.js 24 and your existing development PostgreSQL connection. Keep the real
`backend/.env` private; do not overwrite it, print it, or put its values in Flutter.

From the project root:

```powershell
cd backend
npm ci
npm run migrate
$env:NODE_ENV='development'
$env:HOST='127.0.0.1'
$env:ENABLE_GPS_SIMULATOR='true'
# First setup only; omit when this machine already has its simulator secret file:
npm run gps:provision
npm start
```

In this development session migration 003 was applied and `SIM-GPS-001` was
provisioned in the configured local database. Its credential is in the ignored
`backend/.local/gps-simulator.json`; it was not printed or committed. Provisioning
never changes a colliding non-simulated vehicle and never overwrites an existing
secret file. Only hashes are stored in PostgreSQL. The local tool file contains
the bearer credential, so keep it private; Windows file access inherits the
project directory's ACL. It is not a passenger asset or encrypted mobile storage.

Restart an old backend before using this feature. Port 3000 must be available for
the new process. Development flags above apply only to that PowerShell process
and its children; they do not permanently edit `.env`.

In a second terminal, from `backend`:

```powershell
$env:NODE_ENV='development'
$env:HOST='127.0.0.1'
$env:ENABLE_GPS_SIMULATOR='true'
$env:GPS_SIMULATOR_URL='http://127.0.0.1:3000'
$env:GPS_SIMULATOR_INTERVAL_MS='5000'
npm run gps:simulate
```

The interval accepts 1000–3600000 milliseconds. No report is sent before a manual
choice. Type a command and press Enter:

| Command | Effect |
| --- | --- |
| `available` | Manually set AVAILABLE, resume and send a report |
| `full` | Manually set FULL, resume and send a report |
| `pause` | Stop sending; leave the last accepted report to age |
| `resume` | Resume using the last manually selected status |
| `quit` / Ctrl+C | Stop the simulator |

Requests do not overlap. One already in flight may complete after pause/quit.
Failures report an error without inventing a successful update. Status never
cycles automatically with the coordinate path.

The usual stale threshold is 120 seconds. For a shorter local test, set
`$env:STALE_AFTER_SECONDS='15'` in the backend terminal **before** starting it.
Restart to change it. This test setting is not a recommended field policy.

## Launch Flutter and verify on the phone

From the project root, Windows desktop:

```powershell
flutter run -d windows --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=DEV_GPS_SIMULATION=true
```

Physical Infinix X6885 / Android 16, connected with USB debugging:

```powershell
flutter devices
adb -s PHONE_DEVICE_ID reverse tcp:3000 tcp:3000
flutter run -d PHONE_DEVICE_ID --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=DEV_GPS_SIMULATION=true
```

For an optional Android emulator use its actual device ID and
`API_BASE_URL=http://10.0.2.2:3000`. Do not use that alias for the physical phone.
Local HTTP exceptions remain debug-only; production/profile API builds need HTTPS.

1. Sign in or Continue as Guest. Confirm the SIMULATED / DEMO warning.
2. Select From **Boac**, To **Mogpog**, then Find Jeepneys. Only `SIM-GPS-001`
   should appear. This is the test direction, not a service recommendation.
3. Enter `available` in the simulator. Open details, check source/status/timestamps,
   then View last location on map. Watch changing coordinates and the marker.
4. Enter `full`; verify FULL after the next refresh/poll, with no numerical seats
   and ETA unavailable. Operator information should remain unavailable.
5. Enter `pause`; after the configured threshold confirm UNKNOWN / STALE and
   OFFLINE. The last point remains labeled as a last report. Enter `resume` and
   confirm fresh status returns only after an accepted new report.
6. Switch to Mogpog → Boac or another direction: no assigned vehicle or marker
   should appear. Search must remain scoped to the selected direction.
7. Stop the backend: expect an API error/retry, not offline demo substitution.
   Restart it and refresh. Check login, guest navigation, profile and map controls.
8. Check details scrolling, large fonts, keyboard, gesture insets and performance.

Local simulation builds poll every five seconds; normal API builds retain the
30-second interval. Manual refresh remains available. The repository schedules a
single expiry timer using the backend's stale threshold so status also expires
between polls. Freshness depends on the device clock; keep development clocks
synchronized. This is polling, not a continuous GPS stream. Markers move directly
to accepted coordinates; there is no invented interpolation or heavy animation.

## Stop, revoke, and return to ordinary API mode

Stop the simulator with `quit`, then stop its backend with Ctrl+C. Start a normal
backend with `ENABLE_GPS_SIMULATOR=false` (or unset it) and launch Flutter without
`DEV_GPS_SIMULATION`. Stored simulated history remains explicitly marked and hidden.

To revoke the development credential, with the development flags still set:

```powershell
npm run gps:revoke
```

This revokes the simulator credential and removes its local secret file, retaining
labeled history. `npm run gps:provision` can then issue a new credential. No other
vehicle or passenger account is touched. Do not put the credential in command-line
arguments, `dart-define`, documentation, screenshots or source control.

## Automated verification

Observed results in this development session:

| Check | Result |
| --- | --- |
| Backend syntax checks | Passed |
| Database-free backend tests | 31 passed; two database suites intentionally skipped |
| Real PostgreSQL tests | 15 passed, including authentication and GPS ingestion |
| Simulator → HTTP → PostgreSQL → Flutter widget test | Passed separately |
| Flutter analysis | No issues |
| Flutter suite | 47 passed; one opt-in database test skipped here and passed separately |
| Android debug build | Passed with the local simulation flag |
| Manual simulator commands | AVAILABLE, FULL, pause/stale and resume accepted locally |

The local CLI check used a temporary port-3100 backend, a one-second sender interval
and a five-second stale threshold. No persistent configuration was changed. Preview
renders were visually reviewed, and the details panel was checked at 320 pixels
and 2× text scaling, including a wider test font. A long source-badge overflow
found by that test was fixed by allowing its text to wrap beside the close button.

The explicit simulator build is also copied to
`build/app/outputs/flutter-apk/abangque-gps-demo-debug.apk`. It still requires the
opt-in local backend and manual simulator commands; it has no moving-data generator.
No physical-phone testing was performed during this task.

```powershell
# backend
npm run check
npm test
npm run test:postgres
npm run test:gps:flutter
# project root
flutter analyze
flutter test
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=DEV_GPS_SIMULATION=true
```

The database suites create random temporary schemas, apply the real migrations,
and remove only their own schemas afterwards. Use a development database role
with CREATE SCHEMA permission, never a production database. Authentication
regressions are also covered. No existing real accounts are used for tests.

`test:gps:flutter` runs the real simulator client, an ephemeral loopback Express
API, real PostgreSQL and Flutter's actual read adapters/map/details widgets.
Its test-only control wrapper never mounts in the production server, and device
secrets stay in Node. OSM tile images are stubbed to avoid network tile requests.
Stale database timestamps are aged deterministically in this automated harness;
the separate local CLI check verifies actual pause/elapsed-time behavior.

The normal Flutter suite skips that opt-in database/network test and tests local
expiry, provenance, route isolation and existing passenger behavior independently.
An Android build and desktop widget tests do not verify physical phone performance,
native secure storage, real map networking, GPS/LTE hardware or road accuracy.

The temporary CLI verification backend on port 3100 was stopped after testing.
The simulator is not left running. No admin system, driver accounts, deployment,
official route management, operator registry or ETA calculation was implemented.
