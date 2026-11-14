# AbangQue — Project brief

Current phase update (2026-11-14): the owner explicitly authorized the separate
admin web, Jeepney/Route Management and Phase 5 IoT Device Management. See sections 22–23,
[ADMIN_WEB.md](ADMIN_WEB.md) and [JEEPNEY_MANAGEMENT.md](JEEPNEY_MANAGEMENT.md).
See [ROUTE_MANAGEMENT.md](ROUTE_MANAGEMENT.md) for current route behavior and checks.
See [DEVICE_MANAGEMENT.md](DEVICE_MANAGEMENT.md) for device administration and security.
Earlier deferral notes are historical. Firmware, physical integration, Live Monitoring
and deployment remain outside this phase.

GitHub repository: https://github.com/kitsu-pot/AbangQue

Owner preference recorded 2026-11-06: commit and push completed project changes
after relevant checks in each development task. AGENTS.md carries the standing
sync instructions. This does not install a background file watcher or publish
local secrets, database contents, dependencies or generated build artifacts.

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

- Start with From/To municipality selection. Display only jeepneys explicitly
  assigned to the selected administrator-registered route direction; never the
  whole fleet by default. Clearly distinguish fresh from offline/stale reports.
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

## 14. Journey-first passenger flow (2026-10-31)

The passenger app now starts with From/To municipality selection, swap and Find
Jeepneys. The six municipality names are choices, not evidence of operating
routes. Reverse directions are independent. Global All/Available filters and
global fleet cards/statistics are removed.

Inspected backend routes, presenter and initial migration contain no registered
route records or jeepney-route assignments. The Flutter RouteRepository boundary
therefore returns an empty catalog in API and DEMO modes. It does not call an
invented endpoint or assign existing demo records. API connectivity remains via
the existing vehicle GET endpoint; all unassigned vehicles stay out of results
and markers. No schema, seed, database contents or backend code was changed.

Future injected catalogs support route IDs, municipality endpoints and explicit
vehicle assignments, selection among multiple routes in one direction, scoped
search, cards/details and map markers. Test-only records exercise those paths.
No such routes are shipped in the passenger app. Backend/admin registration,
persistence, validation, route reads and assignment management remain future work.
See [ROUTE_SELECTION.md](ROUTE_SELECTION.md) for implementation and verification.

## 15. Passenger authentication (2026-11-01)

The authorized passenger-account phase adds Argon2id password hashes, email/name
registration, login, PASSENGER-only authorization, expiring opaque sessions,
server-side logout and profile name editing. Additive migration 002 was applied
to local PostgreSQL. The real API/database tests run in isolated temporary schemas.
Transport endpoints stay public; Continue as Guest preserves route/map access.
No routes, GPS claims, ETA, admin permissions or device credentials are introduced.

Flutter uses origin-scoped secure device storage, server-verified session recovery,
an explicit pending-logout marker for offline revocation, and the existing glass
components. Offline DEMO is guest-only. Email changes, verification and password
reset are not implemented. Physical phone/keychain behavior still needs device
verification. See [AUTHENTICATION.md](AUTHENTICATION.md) for architecture, migration,
environment settings, security limits and exact launch/verification steps.

## 16. Enhanced details and local simulated GPS (2026-11-01)

Checkpoint `16ecf3c` preserves passenger authentication. Details now include vehicle
identity, explicit direction, operator-unavailable fallback, coordinates, measurement
and receipt times, connectivity, manual status and unavailable ETA. Selection follows
new positions; a local expiry timer ages status between polls.

Migration 003 adds source=simulated to vehicles, credentials and updates to prevent
hardware mislabeling. It was applied to local PostgreSQL. SIM-GPS-001 was provisioned
with a private, ignored local tool credential. The Node simulator uses the existing
protected device update endpoint, requires local development opt-in, waits for a
manual FULL/AVAILABLE choice, and supports pause/resume. No hardware is claimed.

The new public route catalog is normally empty. Opt-in local testing exposes one
explicit DEMO Boac-to-Mogpog direction assigned only to SIM-GPS-001. Its synthetic
coordinate loop near Boac is not route geometry or a real trip. Existing demo rows
are not reassigned. There are still no administrator-managed operating routes,
operator registry, route tables or admin dashboard. This supersedes earlier notes
that no route endpoint exists; that endpoint is now an empty/DEMO catalog boundary.

Flutter requires a local debug-only DEV_GPS_SIMULATION flag to show the test catalog
and vehicles; otherwise simulated records remain hidden. Simulation mode polls at
five seconds; ordinary API mode remains thirty seconds. All test data is labeled,
ETA remains unavailable, and guest/authentication/offline DEMO features are retained.
See [GPS_SIMULATOR.md](GPS_SIMULATOR.md) for setup, test evidence and phone checks.

## 17. Passenger waiting location (2026-11-02)

Checkpoint `aa6fd70` preserves the preceding simulated-GPS/details implementation.
The optional passenger waiting-location feature adds a cancellable foreground
device reading, manual OSM tap selection, confirmation/cancel/change/clear, a
distinct blue marker and a show-both camera action with a selected jeepney.
Guests retain full access. Route filtering, status freshness and unavailable ETA
remain independent of the waiting point. No fictional paths or boarding points
are created. Permission is requested only on Use My Location.

Selection is memory-only for this session, clears on account change/logout/restart,
and is neither uploaded nor linked to an account. No backend/schema change or new
migration is required. OSM tile requests still reveal the viewed area to the tile
provider. Foreground-only geolocator acquisition stops after one fix, timeout,
cancel or app backgrounding; mock and low-accuracy readings are disclosed.
See [WAITING_LOCATION.md](WAITING_LOCATION.md) for architecture, privacy, checks
and exact Infinix verification instructions. Physical-phone validation is pending.


## 18. Full-screen route map (2026-11-06)

Checkpoint tag `checkpoint/map-redesign-2026-11-06` preserves commit `84ba388`.
Find Jeepneys now opens the full-size map and performs a foreground permission
check followed by one reading. This explicitly supersedes the earlier rule that
only Use My Location initiates acquisition. Dropdown changes do not initiate it.
Existing manual waiting points are preserved. Denial is non-blocking and a secure
boolean remembers prompt attempts across launches, preventing repeated dialogs.
No coordinates are stored or uploaded; account-change and background cancellation
remain enforced. Manual tap/confirm/change/clear is available in the location menu.

Map uses the existing OSM component with floating route editing, My Location,
source labels, visible attribution and a collapsed/partial/expanded jeepney sheet.
The sheet keeps collapse controls reachable; selected vehicle reports follow the
existing controller and stale semantics. The list tab remains available. No backend,
schema, admin, firmware, ETA or operating-route data is added. See
[FULLSCREEN_MAP.md](FULLSCREEN_MAP.md). Phone performance remains unverified.


## 19. Passenger Favorite Routes (2026-11-07)

Checkpoint `checkpoint/favorites-2026-11-07` preserves `16953e9`. Authenticated
passengers can save/remove registered route IDs with the map heart, see them on
Home, reopen an exact direction after rechecking the catalog, and restore them
through the same PostgreSQL account after session recovery or a new login. Guest
prompts offer Log In, Create Account and Not Now; returning from authentication
keeps the journey and requires an explicit save. No guest favorites are stored.

Migration 004 adds the minimal empty registered_routes catalog and account-scoped
passenger_favorite_routes table. This supersedes earlier statements that there is
no route table. It was applied locally; no operating routes were seeded. The public
catalog reads active stored routes and preserves the separately gated simulator.
DEMO directions cannot be saved. Real jeepney assignments, administrator route
verification/management and the admin dashboard remain future work.

Favorites reuse live passenger sessions, backend role checks, secure device token
storage and production HTTPS. Unavailable/deleted routes retain removable labels;
opening rechecks availability. Duplicate saves are idempotent, account changes
clear private state and late responses cannot restore it. No coordinates, waiting
locations, device credentials, seat counts or ETA are added to favorites. See
[FAVORITE_ROUTES.md](FAVORITE_ROUTES.md) for contracts, observed tests and the exact
physical-phone checklist. Phone performance/interaction remains unverified.


## 20. Offline and weak internet handling (2026-11-09)

Checkpoint `checkpoint/offline-2026-11-09` preserves `f2589a7`. API mode now stores
bounded, origin/simulation-scoped public route and vehicle snapshots in the
application cache directory. GPS measurement, server receipt and application
retrieval timestamps remain separate. A 24-hour fallback lifetime, file/record
limits and at-most-once-per-minute disk writes are documented in
[OFFLINE_HANDLING.md](OFFLINE_HANDLING.md). This supersedes older statements that
all API rows/route selection are cleared after failed requests.

Cached routes/assignments and last known markers remain available during an
interruption, with current availability always CACHED / UNKNOWN and ETA unavailable.
A compact map notice and receipt details use actual API results. Valid recovery
replaces snapshots and retains an available selected route; HTTP/validation errors
cannot invent route removal. Both datasets refresh with one app-owned timer,
controlled backoff, single-flight reads and foreground lifecycle handling.

The cache contains no precise passenger waiting point, account information,
favorites or secrets. Already verified in-memory identity survives temporary
session-check failure; cold login recovery still requires server verification.
Favorites remain account-scoped memory only, with server-confirmed writes and no
queue. No backend/schema change, operating routes, assignments, firmware or
administration feature is introduced. The existing path_provider dependency is now
explicitly imported for the public cache directory. Android physical verification
is pending: adb reported no attached device during this task.


## 21. Passenger account management and privacy (2026-11-10)

Checkpoint `checkpoint/account-privacy-2026-11-10` preserves `5c13e73`. The existing
Profile now groups name editing, read-only registered email, password change,
guest-accessible Privacy & Data, logout and deliberate permanent account deletion.
Guests retain transport access and separate Log In/Create Account choices. UI
forms reuse the glass components, shared validation and existing auth controller.

POST /api/auth/me/password verifies the current password, writes an Argon2id hash
and revokes other sessions in one transaction; the current session retains its
original token/expiry. DELETE /api/auth/me verifies the current password and
transactionally removes the account plus existing cascading sessions/favorites.
Account locks and session rechecks serialize sensitive actions with login; a login
verified against an old hash cannot create a session after password change/deletion.
Authenticated identity, strict validation and IP/account rate limits protect both
operations. No migration, new dependency or new environment setting is required.

Account changes require server confirmation and are not queued. Timeout outcomes
are disclosed as unconfirmed because the server may already have committed. Logout
also clears private memory and attempts revocation if its secure marker write fails.
Account changes cannot populate the public cache or share private favorites. No
public route/device/telemetry records or other passenger accounts are deleted.

The in-app privacy explanation describes actual account/session data, favorites,
foreground location use, memory-only waiting points, OSM tile disclosure and the
bounded public offline cache. It is explicitly not a formal privacy policy; no legal
entity/contact/retention period is invented. External backup/log retention and
public-deployment safeguards remain unresolved. See
[ACCOUNT_MANAGEMENT.md](ACCOUNT_MANAGEMENT.md) for architecture, current checks,
security limits and the Infinix verification steps. No phone was attached during
this implementation, so physical acceptance is still pending.

## 22. Admin web dashboard foundation (2026-11-12)

Checkpoint `checkpoint/admin-foundation-2026-11-12` preserves `db859dc`. The owner
explicitly requested React/TypeScript/Vite/Tailwind administrator authentication,
an overview and responsive navigation. `admin-web/` is separate from Flutter and
uses the same Express API/PostgreSQL database. Migration 005 adds dedicated admin
accounts and hash-only sessions, preserving PASSENGER-only authentication.
It was applied locally; no owner administrator, operating data or seeds were added.

Admin authentication uses shared Argon2id policy, HttpOnly cookies, absolute expiry,
server logout, exact-origin/custom-header CSRF protection and IP/email throttling.
The first-admin command is development/loopback-only, accepts masked PowerShell
input over stdin, locks out duplicate provisioning and has no HTTP equivalent.

Dashboard summaries use actual stored vehicles/routes and fresh measurements plus
receipt timestamps. DEMO/SIMULATED vehicles remain labeled and excluded from
operational counts. Physical-device counts and route assignments are unavailable
because those registries/relations do not exist. No credential counts masquerade
as physical devices. Stale availability becomes UNKNOWN; ETA remains unavailable.

Jeepneys, Routes, IoT Devices and Live Monitoring are Coming soon placeholders.
Settings shows identity/session information and logout. No CRUD, driver accounts,
hardware, passenger UI changes or deployment is introduced. Backend/real PostgreSQL
and frontend checks passed; browser checks covered login desktop/mobile and outage
layouts. Owner login and authenticated dashboard manual visual acceptance remain
pending. See [ADMIN_WEB.md](ADMIN_WEB.md) for exact setup, security and test scope.

## 23. Admin Jeepney Management (2026-11-13)

Checkpoint `checkpoint/jeepney-management-2026-11-13` preserves `4d7be55`. The owner
requested working registration, editing, route assignment, activation, details,
search/filter/pagination and compatibility tests. Jeepneys is now functional in
the existing admin web. Route/IoT CRUD, driver accounts, deployment and physical
hardware remain excluded.

Migration 006 adds administrative metadata, active state, optional single current
registered-route assignment and version conflict protection to existing jeepneys.
Identifiers stay immutable; telemetry, credentials and provenance are preserved.
No operating routes, vehicles, GPS reports or owner credentials are seeded.
Plate metadata is optional and not uniquely constrained pending verified policy.

Admin-only APIs reuse existing cookie/role/CSRF checks and parameterized queries.
Route UUID/direction and active eligibility are checked transactionally. Inactive
assigned routes can be retained during unrelated edits but cannot be newly assigned.
Deactivation removes current passenger API visibility/assignments without deleting
history or stopping authenticated device ingestion. Reactivation cannot refresh old
GPS or write AVAILABLE. Public route responses retain the existing Flutter contract;
no Dart change was needed. Offline cached records only learn changes after refresh.

Dashboard real-registration counts include inactive records; operational freshness
and driver-status counts include only active real vehicles. Details label historical
status and separate measurement/communication times. No seats, counts of passengers,
admin driver-status controls or ETA estimates were added.

Real PostgreSQL and frontend/backend suites exercise the management flows and
passenger/device regressions. Actual browser QA used a temporary isolated schema
and labeled test vehicle/admin at desktop/mobile widths, then removed that schema.
It does not establish owner login, phone acceptance or physical GPS/LTE operation.
See [JEEPNEY_MANAGEMENT.md](JEEPNEY_MANAGEMENT.md) for changed files, exact commands,
test scope, migration/application status and remaining decisions.

## 24. Route Management (2026-11-14)

Migration 007 adds optional operational metadata, explicit verification, unique ordered
municipality pairs, immutable route identity and edit versions. Admin route APIs and
responsive cards support registration, editing, activation, filtering and assigned
vehicles. Passenger catalogs expose only verified operations; Flutter displays them
while online. Inactive directions remain unavailable favorites, preserving IDs and
assignments. Migration applied locally; no operating records or credentials seeded.
See ROUTE_MANAGEMENT.md for commands, checks and remaining manual acceptance.

## 25. IoT Device Management (2026-11-14)

Migration 008 adds stable device registrations linked to existing credential versions,
one-enabled-device assignment constraints and secret-free admin audit events. Existing
vehicle-bound credentials are grouped into labeled legacy registrations without
changing hashes, bindings, sources or history. This is not physical hardware proof.
The existing simulator is retained, labeled and read-only in admin management.

Admin APIs/UI implement registration, metadata, assignment/unassignment, enable/disable,
one-time provisioning/rotation and revocation. Ingestion rechecks device state under
lock before credential checks; reassignment revokes keys and preserves original GPS
references. Rotation/revocation/audit are transactional; only hashes persist. No
passenger-code changes, fake reports, driver accounts, firmware or deployment.
Migration applied locally. Backend, PostgreSQL and frontend tests passed; physical
IoT and manual browser acceptance remain unverified. See DEVICE_MANAGEMENT.md.
