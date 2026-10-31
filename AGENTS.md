# AbangQue development rules

Read [docs/PROJECT_BRIEF.md](docs/PROJECT_BRIEF.md) before substantive work. It
records requirements, source findings, owner-reported progress and unresolved
decisions. Current user instructions take precedence; do not treat a roadmap as
permission to implement every module.

## Scope and continuity

- Official user-facing name: **AbangQue**. Project location: Marinduque,
  Philippines. Preserve the existing jeeplink workspace, package/internal
  identifiers, API paths and database resources unless a change is necessary.
- Inspect the current source and applicable instructions before editing.
  Preserve working features; extend existing components instead of rebuilding.
- Immediate priority: Android passenger app branding, removal of numerical
  seat features, Liquid Glass-inspired UI, mobile layouts and API reliability.
- Do not implement the admin dashboard or physical IoT integration until
  explicitly requested. Do not deploy or introduce paid services without approval.
- Work one phase at a time. Document discrepancies instead of silently changing
  functioning code outside the requested scope. Explain options before major
  architectural changes. Documentation-only requests must not mutate code,
  dependencies, services, schemas or database contents.

## Information truthfulness

- **No numerical seat counts, passenger occupancy, estimated empty seats,
  occupancy bars or automatic counting**, including offline demos.
- FULL/AVAILABLE is manually selected by the driver. It is not measured
  occupancy or a boarding guarantee. Use UNKNOWN/STALE for missing, unreliable
  or outdated reports. Never promote historical AVAILABLE to current status.
- Vehicle counts may count vehicles only; label them accordingly, never as seats.
- Distinguish last reported coordinates, measurement time, last communication,
  stale reports and connection failures. Do not claim continuous tracking from
  polling or successful hardware operation from accepted database records.
- API eta=null means **ETA unavailable**. Do not invent API ETAs. A future
  calculation requires an agreed, documented, testable method.
- Label all simulations/seeded data DEMO. Keep API and offline simulator modes
  separately selectable; never silently substitute simulation after API errors.
- Do not invent official routes, stops, schedules, fares, drivers or cooperative
  records. Do not assume all passengers wait roadside; terminal-based operations
  around Boac/Mogpog need verified information.

## Architecture and security

- Preserve the Flutter repository/controller/UI separation and existing Node.js
  24, Express and PostgreSQL backend. Prefer simple maintainable JavaScript for
  backend work. Reuse existing contracts, validation and migration tooling.
- Protect device-bound authentication, hash-only credential storage, revocation,
  input validation, duplicate handling and stale-status logic.
- Never put database passwords/device credentials in Flutter, assets,
  dart-define, logs or committed files. Use .env.example for documentation;
  do not expose real .env values.
- Restrict local HTTP to development. Keep release/profile API traffic HTTPS;
  never disable certificate verification or broaden release cleartext access.
- Primary Android test device: owner-reported Infinix X6885, Android 16.
  USB workflow: adb reverse tcp:3000 tcp:3000, with API_BASE_URL set explicitly
  to http://127.0.0.1:3000. Target a device explicitly if multiple are connected.
  Emulators are optional; 10.0.2.2 is the emulator host alias, not the phone URL.
- Hardware is planned, not selected: ESP32 + separate GPS + separate LTE.
  Never connect vehicle 12V directly to ESP32. Verify exact models and electrical
  requirements before wiring/firmware. No backup battery is currently planned.

## UI, checks and reporting

- Preserve Home, Map, Jeepneys and Guide navigation. Use reusable original
  emerald/mint/sage/cream glass-inspired components; no Apple assets/branding.
- Prioritize readable text, accessibility, SafeArea/gesture navigation, larger
  text sizes and smooth phone performance. Respect reduced motion; avoid
  excessive blur, animations and heavy dependencies. Development laptop: 8GB RAM.
- Retain loading, empty, error, retry and refresh states, usable map controls,
  source labels and report timestamps.
- For Flutter changes run flutter analyze and flutter test. For backend changes
  run npm run check and npm test in backend. Add meaningful tests for changed
  behavior; replace outdated seat-count assertions when removing those features.
- Database-free tests do not verify PostgreSQL or physical hardware. Do not
  assume database/device availability or rerun migrations/seeds without task need.
  Documentation-only edits need document/link review, not application test runs.
- Explain changes, validation and remaining limits in simple English. Separate
  observed results from owner-reported progress and planned work. Do not
  misreport old test runs as new verification.

