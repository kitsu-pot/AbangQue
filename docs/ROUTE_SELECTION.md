# Journey-first passenger application

Implemented 2026-10-31. Pre-change Git checkpoint: `a2b3d22` (completed glass UI).

## Offline extension (2026-11-09)

Routes and vehicle reports now refresh together with controlled retry/backoff.
Cached registered directions and explicit assignments remain usable during API
failures, with unverified-route and CACHED / UNKNOWN vehicle labels. A failed request
preserves the selected direction; a valid new catalog can remove it. No GPS-based
inference or automatic DEMO fallback is introduced. See
[OFFLINE_HANDLING.md](OFFLINE_HANDLING.md). Older descriptions of failure clearing
and manual-only catalog refresh below record earlier implementation phases.

## Current integration (2026-11-07)

The current API adapter reads GET /api/routes. Migration 004 adds an empty
registered_routes table with stable UUIDs, ordered municipalities and an active
flag. Only its active records are offered as registered routes. The separately
opted-in local GPS simulator still exposes an explicitly DEMO direction and test
assignment; it cannot be saved as a favorite. Offline DEMO has no registered routes.

[Favorite Routes](FAVORITE_ROUTES.md) now lets authenticated passengers save those
stable route IDs, restore them after login and reopen an exact direction after a
fresh catalog check. Guests keep transport access and get an optional login prompt.
No operating routes are seeded, existing demo jeepneys are not reassigned, and
real jeepney assignments/admin registration tools remain future work.

The sections below record the original 2026-10-31 route-selection phase. Their
then-empty backend boundary was subsequently extended by the simulator and favorite
phases described above; their original test counts are historical.

## Functional now

Home starts with From municipality, To municipality, swap and Find Jeepneys.
Choices are Boac, Mogpog, Gasan, Buenavista, Santa Cruz and Torrijos. They are
geographic preferences, not a route/service catalog. Identical endpoints are
rejected. Changing/swapping a journey immediately clears old results and search.
The four tabs and emerald/mint glass components remain.

All/Available global filters and global fleet cards/statistics have been removed.
Map and Jeepneys share the submitted direction and selected registered route.
Map still provides OSM geography, controls, attribution and tile retry. It never
renders unassigned vehicles. Selecting two municipalities does not create a route.

**The current production app has no registered route catalog in either mode.**
It shows “No registered routes available yet.” API mode continues fetching vehicle
reports from the existing backend; those reports remain unassigned and hidden.
Offline DEMO is a labeled selector preview only. The three existing simulated
vehicles are retained in the repository but are not assigned to invented routes.

ETA remains unavailable everywhere. No seat counts, route lines, stops, schedules,
verified GPS claims or inferred operating routes were introduced.

## Backend inspection and boundaries

Inspected backend/src/app.js, backend/src/presenter.js and
backend/migrations/001_initial.sql. Existing endpoints are health, jeepney list,
jeepney detail and protected device ingestion. Tables are jeepneys,
device_credentials and location_status_updates (plus the migration ledger).
There are no route IDs/endpoints/assignment tables in that contract.

No backend implementation, migration, PostgreSQL schema/data, seed, credential,
deployment or admin UI was changed. No request to an imaginary routes endpoint
is made, and no GPS-to-municipality inference is used.

## Flutter integration boundary

lib/src/domain/passenger_route.dart defines:

- Municipality: six stable enum choices and English display labels.
- PassengerRoute: stable route ID and ordered origin/destination. The reverse
  direction is a different record, never an implicit match.
- RouteAssignment: explicit jeepneyId/routeId membership.
- RouteCatalog: immutable route/assignment snapshot with validation of duplicate
  route IDs, distinct endpoints and assignment references.
- RouteRepository.loadCatalog(): future passenger route read boundary.
- UnconfiguredRouteRepository: current empty implementation for both modes.

JeepLinkApp accepts a RouteRepository dependency. JeepneyController joins its
catalog with vehicle snapshots by exact IDs. Before submission, without a matching
registered route, on catalog errors or without assignments, results are empty.
If multiple registered route IDs share a direction, passengers choose one; the app
does not silently combine them. Search is limited to the chosen route.

Manual refresh reloads vehicles and the catalog. Vehicle polling remains at its
existing 30-second interval; automatic route polling is not implemented. Revoked
assignments disappear on the next catalog refresh. Route read failures clear the
catalog/selection and offer retry; late responses cannot overwrite newer results.
Future integration must agree on cache/refresh and assignment validity rules.

When explicit test catalogs are injected, cards show ID, registered direction,
last reported GPS coordinates, report time, source, driver status/freshness and
unavailable ETA. Details retain communication/measurement timestamps and map
focus; open details re-check membership against the current catalog. Historical
DEMO is still unknown, regardless of any old AVAILABLE value. Unknown coordinates
have no marker. These result paths are tested but cannot be populated by today's
route-less backend. Test-only catalogs in test/fakes.dart are never imported by lib.

## Future backend/admin phase — not implemented

Agree on a passenger API contract and add administrator-managed route records
with stable IDs, ordered municipality endpoints, active/verified lifecycle and
explicit jeepney assignments. Define how deactivation, reassignment and multiple
routes per direction work. Add authorized admin registration/assignment workflows,
database migrations, input validation and backend tests in that later phase.

Then implement a RouteRepository HTTP adapter using server-provided records,
validate the payload and inject it at startup. Reuse the existing transport/TLS
safeguards; never put administrator or device secrets in Flutter. A successful
route registration does not verify GPS hardware or supply an ETA algorithm.
No endpoint shape or schema proposed here is an already-working backend feature.

## Verification and launch

Fresh results for this change: Flutter analysis passed with no issues; all 29
tests passed; Android debug APK built successfully using the documented local
Java socket workaround. Rendered phone previews were reviewed. Artifact:
build/app/outputs/flutter-apk/app-debug.apk (API mode, localhost USB workflow).
No phone installation, live database check or hardware verification was performed.

Use the unchanged [API launch instructions](API_MODE.md) for Windows, emulator
or USB-connected Infinix X6885. Existing API fixtures should now remain hidden
until an explicit registered assignment is available. No reseeding is necessary.

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

On this Windows host the project-local Java socket workaround from
[REDESIGN.md](REDESIGN.md) may be needed for Gradle. It changes only the build
process environment and does not relax Android release HTTP restrictions.

Tests cover absent catalogs in both modes, actual API-shaped unassigned records,
direction matching, swaps/reset, same-municipality rejection, multiple route
choices, assignment removal, catalog failure/recovery, late responses, scoped
search, markers/details, status truthfulness, refresh/retry and 320-pixel layouts
up to 2x text. HTTP, map tiles and future registered routes are test doubles.

Still verify on the physical phone: municipality menus (including Santa Cruz and
Buenavista) at enlarged font/display sizes, swap/change-journey navigation,
gesture insets, map tiles, backend-offline retry and scrolling performance.
No live database/phone/GPS behavior is established by widget tests.
