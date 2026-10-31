# AbangQue — Project brief

Updated: 2026-10-31  
Official title: **AbangQue: An IoT-Based Real-Time Jeepney Tracking and Passenger Assistance System**  
Location: **Marinduque, Philippines**  
Context: college capstone; an IoT and networking system, not only a mobile app.

## 1. Purpose and scope

Help passengers understand where participating jeepneys last reported their
positions, whether the driver reported FULL or AVAILABLE, and eventually when a
jeepney may arrive. Location and status can be delayed or unavailable. Arrival
estimates must never be presented as guarantees.

The complete system comprises a passenger Android app, a physical device in each
participating jeepney, an internet-connected backend and database, and a future
administrator dashboard. Real GPS integration remains a future milestone;
simulation and database records do not demonstrate real hardware tracking.

The current priority is finishing and improving the Android passenger application:
AbangQue branding, removing numerical seat-count features, a consistent Liquid
Glass-inspired design, mobile layout quality, preserved API connectivity, and
passenger usability. Do not start the admin dashboard or IoT implementation until
explicitly requested. Do not deploy or introduce paid services without approval.

This document consolidates the owner's supplied project description with source
inspection. It records requirements and discrepancies; it does not assert that
all requirements have already been implemented.

## 2. Architecture and modules

Planned device-to-passenger data flow:

```text
GPS module -> ESP32 -> separate 4G/LTE module -> Internet
  -> Node.js / Express backend -> PostgreSQL
  -> Flutter passenger app / future admin web dashboard

Driver FULL/AVAILABLE toggle -> ESP32 -> same authenticated update flow
```

The ESP32 collects and transmits information. It is not the backend server.
The backend must distinguish valid communication, stale reports, lost
communication, and unavailable information.

| Module | Responsibilities | Status / boundary |
| --- | --- | --- |
| Passenger Android app | Home, Map, Jeepneys, Guide; OSM; search/filter; details; status and timestamps; loading/error/empty/retry/refresh | Implemented foundation and API adapter; current improvement priority |
| IoT device | Read GPS and driver toggle, associate with registered jeepney, authenticate updates over LTE, handle interruptions | Planned; exact parts and electrical requirements unconfirmed |
| Backend and database | Validate/authenticate updates, store history, serve passenger data, protect device credentials, identify stale reports | Implemented Node.js 24 / Express / PostgreSQL foundation; preserve |
| Admin web dashboard | Secure cooperative administrator login, monitor last positions/status/device activity, view last communication, manage jeepneys/devices | Future; use existing backend/database; do not implement yet |
| Communication and monitoring | Device-to-backend communication and honest display of freshness/availability | REST and app polling exist; physical LTE/GPS communication unverified |

## 3. Passenger requirements

Retain Home, Map, Jeepneys, and Guide navigation. The passenger app should:

- Show registered jeepneys and clearly distinguish those currently reporting
  from offline/stale records.
- Display last reported OSM positions and their age; do not imply an old marker
  is a current GPS fix.
- Show manually reported FULL or AVAILABLE only when valid and sufficiently
  recent; otherwise show UNKNOWN or STALE.
- Show basic jeepney details and when the device last communicated.
- Support search/filter, refresh, loading, connection errors, retry and empty
  states. Do not silently substitute demo vehicles when API requests fail.
- Show **ETA unavailable in API and offline DEMO modes** until an appropriate
  calculation is explicitly approved and implemented.
- Show verified route information only when supplied. No invented routes, stops,
  schedules, fares, cooperative records, or operating practices.
- Explain manual reporting, freshness, GPS limitations, DEMO data and estimates
  in the Guide.

Research includes terminal-based operations around Boac and Mogpog. Do not design
all journeys around roadside pickup or assume uniform operating practices.
Existing fictional pickup points are not evidence of verified terminal/stop data.

### Non-negotiable information limits

**No automatic passenger counting.** Do not implement or display numerical
available seats, passenger occupancy, estimated empty seats, seat-count statistics,
or automatic seat availability detection. This restriction applies to the app,
including offline demo presentations; DEMO labeling is not an exemption.

FULL/AVAILABLE is selected manually by the driver using a toggle button. Neither
status provides a numerical occupancy measurement or guarantees boarding.
Numerical counts of vehicles are conceptually different from seat counts; label
them explicitly as vehicles and do not infer passenger counts.

Historical AVAILABLE must never be reused as current availability. Missing,
outdated or unreliable information must remain unknown. GPS accuracy depends on
signal, hardware, network delays and communications availability. Accepted
credentials establish authorization to submit, not proof that a coordinate is a
valid GPS fix or that hardware has been field-verified.

All simulated or seeded records must clearly indicate DEMO. Keep offline
simulation separate from API-backed records, including API-returned historical
DEMO fixtures.

## 4. Hardware plan — not a finalized wiring design

Planned components:

- ESP32 microcontroller, separate GPS module, separate 4G/LTE module and SIM.
- GPS/LTE antennas as required by the selected modules.
- Power ON/OFF control, FULL/AVAILABLE toggle and LED indicators.
- DC-DC buck converter, inline fuse, suitable wiring and protective enclosure.

Use the jeepney's existing 12V battery through properly rated power regulation.
**Never connect 12V directly to the ESP32.** No separate backup battery is currently
planned. Prefer budget-friendly separate components; do not require an expensive
integrated ESP32/LTE board without a justified, approved change.

Confirm exact module models, voltage/current requirements, interfaces and power
requirements before firmware, pin assignments, component ratings or wiring
decisions. No parts have been selected or electrically verified by this document.

Future device behavior: acquire a GPS position, associate it with its registered
jeepney, read the manual toggle, connect via LTE, send an authenticated update,
repeat at an agreed interval, and recover safely from communication loss.
Boot-time toggle state, invalid GPS fixes, retries and buffering remain future
design decisions.

## 5. Existing backend contract and safeguards

Authoritative implementation: [app.js](../backend/src/app.js),
[presenter.js](../backend/src/presenter.js), and
[initial migration](../backend/migrations/001_initial.sql).

| Endpoint | Existing behavior |
| --- | --- |
| GET /health | Database reachability; does not claim GPS is verified |
| GET /api/jeepneys | Passenger list; historical demos included only when server configuration permits |
| GET /api/jeepneys/:id | Passenger details for an allowed record |
| POST /api/device-updates | Protected device submission with jeepneyId, latitude, longitude, FULL/AVAILABLE status, timezone-bearing timestamp |

Tables: jeepneys, device_credentials, location_status_updates, and the
schema_migrations ledger created by the migration runner. Preserve existing
migrations, relationships, credentials and data. Never rename resources just to
match the product branding.

Existing safeguards include credential binding to one jeepney, random device
secrets stored as hashes, revocation checks, validation, parameterized queries,
transactional ingestion, duplicate timestamp handling, request limits, and
server-side separation of demo and device data.

Passenger responses include source, isDemo, connectionStatus, isStale, position,
timestamp, lastSeenAt, status, lastReportedStatus and eta. Measurement time and
server receipt time are distinct. Out-of-order packets do not replace the newest
measurement. Historical lastReportedStatus must not become current status.

Current defaults from configuration/source:

- Stale threshold: 120 seconds, configurable. Stale when measurement or receipt
  age reaches the threshold, or an update is missing.
- Maximum incoming measurement age: 24 hours; future skew allowance: 30 seconds.
- Device ingestion rate limit: 120 requests per minute per IP.
- Historical demo inclusion: false unless explicitly enabled.
- ETA: always null; no backend ETA algorithm.
- No passenger seat counts are provided by the API.

These are current implementation defaults, not approved field measurements or
final operating policy. The backend calculates freshness on reads; ONLINE means
a fresh accepted report, not proven real-world GPS tracking.

Never place database passwords or device credentials in Flutter, assets,
dart-define, committed files, logs or documentation. Do not read or reproduce real
.env contents merely to document configuration; use .env.example.

## 6. Existing Flutter implementation

Relevant source boundaries:

| Path | Purpose |
| --- | --- |
| lib/main.dart | Selects repository at startup |
| lib/src/config/data_config.dart | DATA_MODE, API_BASE_URL, local-debug HTTP checks and mode scope |
| lib/src/domain/ | Jeepney model and repository interface |
| lib/src/data/api_jeepney_repository.dart | Passenger GET adapter, validation, timeout, polling; no credentials |
| lib/src/data/demo_jeepney_repository.dart | Separate offline simulator |
| lib/src/presentation/jeepney_controller.dart | Snapshot state, search/filter, loading and errors |
| lib/src/presentation/screens/ | Home, map/fleet and Guide |
| lib/src/presentation/widgets/ | Reusable cards, badges, details, map and original vector artwork |
| lib/src/theme.dart | Existing Material 3 theme |
| test/ | Domain, controller, API and widget tests |

API mode is the default. Offline simulation is selected explicitly with
DATA_MODE=demo. API mode polls every 30 seconds, uses a 10-second timeout,
supports refresh/retry and never falls back to the simulator. Failures clear
API rows instead of leaving old availability visible. Open details follow the
current controller snapshot.

API demo records never count as current availability, even if their returned
status says AVAILABLE. Unknown positions do not create map markers. The current
passenger model has no numerical seat fields and keeps ETA unavailable in both
modes. Future non-null ETA support needs an
explicit agreed API contract; it is not implemented by the existing adapter.

Freshness is updated on successful fetches, not continuously between polls.
Do not describe this as a continuous live GPS stream.

## 7. Visual direction and mobile quality

Create an original AbangQue Liquid Glass-inspired visual identity:

- Deep emerald green with mint/sage accents, white and soft cream backgrounds.
- Subtle gradients, translucent cards, frosted floating panels, rounded corners.
- Thin translucent borders, restrained highlights/shadows, readable typography.
- Gentle transitions and micro-animations that respect reduced-motion settings.

Apply consistently to all four screens, details, map controls, search/filter,
bottom navigation, loading, errors and empty states. Prefer reusable Flutter
components. Preserve practical map interaction and information hierarchy.

Readability, accessibility and performance take precedence over blur. Avoid
stacking many BackdropFilter operations or unnecessary heavy dependencies.
Respect SafeArea, Android gesture navigation, larger text, small widths and
smooth scrolling. Do not copy Apple's assets or branding.

Development laptop: 8GB RAM. Primary physical test phone: **Infinix X6885,
Android 16**, as reported by the owner. Android is the product target; Windows
desktop remains useful for development. An emulator is optional, not required.
Existing small-screen/text-scale tests are useful but not proof of physical-phone
performance or of the proposed glass design.

## 8. Development identity and connectivity

Workspace: C:\Users\Administrator\Projects\jeeplink  
Environment: Windows 11, VS Code/Codex, Flutter/Dart, Node.js 24 and PostgreSQL.

**AbangQue** is the official user-facing product name. The folder, Dart package,
internal class identifiers, Android application ID, database names, service
identifiers and API paths may retain jeeplink-compatible names. Avoid breaking
changes or unnecessary renaming.

The local backend normally listens at http://127.0.0.1:3000. For the physical
Android phone over USB, the owner's workflow is:

```powershell
adb devices
adb reverse tcp:3000 tcp:3000
flutter devices
flutter run -d PHONE_DEVICE_ID --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Replace PHONE_DEVICE_ID with the connected phone ID. If multiple ADB devices are
connected, target the intended phone explicitly with adb -s PHONE_DEVICE_ID
reverse tcp:3000 tcp:3000. Re-establish reverse forwarding when necessary after
reconnection. Keep the backend running. These are recorded workflow instructions,
not commands executed during this documentation task.

Windows API mode uses http://127.0.0.1:3000. Android emulators can use
http://10.0.2.2:3000; the current Android default still assumes an emulator, so the
physical-phone command must explicitly override API_BASE_URL.

Offline demo: pass --dart-define=DATA_MODE=demo. Switching compile-time settings
requires relaunching, not only hot reload. OSM tiles still require network access.

The main Android manifest disables cleartext traffic. A debug-only XML permits
local hosts; Dart configuration rejects HTTP for profile/release API mode.
Release traffic requires HTTPS, and no certificate bypass is permitted.
Do not broaden release permissions to solve local connectivity problems.
Existing setup references: [API_MODE.md](API_MODE.md) and
[backend README](../backend/README.md); see documentation gaps below.

## 9. Progress and evidence

### Owner-reported progress from the current brief

- Phase 1: working Flutter screens, navigation, OSM markers and simulator.
- Phase 2: migrations completed successfully; backend tests passed; health and
  jeepney GET endpoints were tested against PostgreSQL.
- Phase 3: Windows app verified with two historical DEMO records supplied by
  PostgreSQL through the API; stale/unknown status and unavailable ETA shown.
- Physical Infinix Android phone: application launched. Continue actual API
  testing on Android when necessary; launch alone is not API verification.

These newer owner reports supersede older documentation describing those steps
as unverified. They were not independently rerun in this documentation task.

### Source and earlier automated-check evidence

Repository inspection confirms both Flutter repositories, explicit mode selection,
the backend endpoints/schema, freshness logic, and development HTTP isolation.
The previous development run reported clean Flutter analysis with 18 tests
passing, and the backend implementation run reported 25 tests passing.
These are prior results, not fresh results from this task. API/unit tests use
doubles/mocks and do not establish physical-device or real-database operation.

### Not yet established

Real GPS/LTE device ingestion, electrical validation, field accuracy, verified
routes/terminals, real ETA calculation, admin dashboard, deployment, Liquid Glass
performance, and full Android API acceptance on the physical phone.

## 10. Passenger redesign implementation (2026-10-31)

The authorized redesign replaces the earlier discrepancies:
- AbangQue branding on passenger screens and platform display labels; compatible
  package identifiers and backend contracts are retained.
- Numerical seat/occupancy fields, arithmetic and all presentation removed.
  Simulator statuses are explicit manual-report examples.
- English interface; ETA unavailable in both API and offline DEMO modes.
- Home counts vehicles and fresh device reports, excluding historical/demo data.
- Reusable emerald/mint/cream glass surfaces, floating navigation, map controls,
  selected-jeepney panels and scrollable report details.
- Responsive hero keeps text/artwork in normal flow. Large text and reduced
  motion are supported; bounded blur is limited to navigation.
- The fictional pickup marker is removed. No verified routes/stops invented.
- README/API setup docs now describe current behavior and USB phone testing.
- Repository/polling/freshness/error semantics and separate DEMO mode preserved.

Checkpoint: 40e22a2 (pre-abangque-glass). See [REDESIGN.md](REDESIGN.md) for
verification scope and remaining physical-phone acceptance. Backend/schema and
device hardware are outside this change.

## 11. Next passenger-app acceptance criteria

Implementation and physical acceptance criteria:

1. User-facing identity consistently reads AbangQue; established internal
   identifiers and backend contracts keep working.
2. No numerical seat or passenger occupancy displays remain, including demo
   details and accessibility text. FULL/AVAILABLE is explicitly a manual report.
3. API data remains truthful: historical demos, stale/unknown values, missing
   positions and null ETA are handled; no synthetic fallback on network errors.
4. Reusable glass-inspired components are consistent across screens and states,
   readable at enlarged text sizes, and performant on the Infinix phone.
5. USB-phone API behavior, refresh/retry, scrolling, keyboard/search, map
   controls, bottom sheets and gesture-navigation insets are checked.
6. Relevant Flutter/backend checks pass; report which runtime tests were
   actually performed and which were not.

These criteria do not authorize new modules or deployment.

## 12. Clarifications to resolve at the relevant phase

- Confirmed: English now; Filipino localization may be added later.
- Confirmed: ETA unavailable in both modes until a suitable calculation is implemented.
- Future ETA destination: verified terminal, stop or another destination model?
  Obtain approved route/terminal data before algorithm or journey-flow design.
- Field communication policy: desired device update interval and approved stale
  threshold, considering LTE reliability/data use; current defaults are provisional.
- Hardware phase: exact GPS/LTE/ESP32 module models, electrical specifications,
  toggle boot behavior and GPS-fix validity rules before firmware/wiring.

The branding, ban on numerical seat counts, manual status semantics, physical
phone workflow and current passenger-app priority are already clear. They do not
need to be reconfirmed.

## 13. Scope history

The initial project-context task created only this brief and AGENTS.md.
The subsequent authorized passenger redesign updates Flutter UI/model/demo code,
tests, platform display labels and relevant documentation. Backend/database schema,
hardware firmware, admin dashboard and deployment remain outside scope.
