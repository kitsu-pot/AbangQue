# AbangQue passenger app

A Material 3 Flutter passenger application for Marinduque, Philippines, with an
original emerald/mint/cream Liquid Glass-inspired interface. English is the
current interface language. The existing internal package name remains jeeplink.

Passenger login, registration, persistent secure sessions, profile editing and
server-revoked logout are implemented. **Continue as Guest** keeps transportation
information public. Offline DEMO remains guest-only. See
[authentication setup and security](docs/AUTHENTICATION.md) before running accounts.

Signed-in passengers can save registered directions with the map heart and reopen
them from Home. Guests receive an optional sign-in prompt; no guest or DEMO
favorites are saved. Setup, API contracts and exact Infinix checks are in
[Favorite Routes](docs/FAVORITE_ROUTES.md). Apply migration 004 and restart the backend.

Find Jeepneys opens a full-screen OpenStreetMap experience with floating route
controls and a draggable jeepney sheet. It requests one foreground location reading;
denial never blocks results. Guests can also choose a waiting point manually. The blue pin is session-only,
can be changed/cleared, and is never uploaded to the backend or saved to an account.
It is a reference, not a verified boarding point. See
[waiting locations and phone verification](docs/WAITING_LOCATION.md).

Current map interaction and Infinix checks: [full-screen map](docs/FULLSCREEN_MAP.md).

API mode now retains bounded public route/vehicle snapshots during weak connections.
Cached markers are last known locations, with **CACHED / UNKNOWN** availability,
original report times, visible received times and automatic API recovery. Favorites
stay private and memory-only; the passenger waiting pin is never cached. See
[offline architecture and Infinix interruption tests](docs/OFFLINE_HANDLING.md).

## Run and verify

Developed with Flutter 3.47.5 / Dart 3.13.4. From this project directory:

```powershell
flutter pub get
flutter run -d windows --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
# Explicit offline simulator (no backend needed):
flutter run -d windows --debug --dart-define=DATA_MODE=demo
flutter analyze
flutter test
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

The APK is written to build/app/outputs/flutter-apk/app-debug.apk. Its localhost
API URL requires USB port reversal on a physical phone. See
[API mode and phone setup](docs/API_MODE.md) for Windows, Android emulator and
Infinix X6885 commands. Backend/database setup is in [backend/README.md](backend/README.md).
No device/database credentials belong in Flutter or dart-define.

## Passenger experience

- Home: municipality From/To selection, swap and Find Jeepneys as the main action.
- Map and Jeepneys: shared journey selection; results require an explicit registered
  route and assignments. Global All/Available filters are removed.
- The registered-route table starts empty: **No registered routes available yet.**
  No operating directions are seeded. Offline DEMO stays empty; the explicitly
  enabled GPS simulator has its own labeled, unsaveable test direction.
- Favorites: account-scoped save/remove, exact-direction reopening, refresh/retry
  and unavailable-route states; no extra navigation tab.
- Future assigned results: route-scoped ID/name search, report cards, details,
  source/status labels, timestamps and last coordinates.
- Guide: English explanations of direction-specific routes and manual reports.
- Floating glass navigation, OpenStreetMap controls/attribution, pull-to-refresh,
  loading, errors, retry, accessible layouts and reduced motion are preserved.

Municipality choices are journey preferences, not operating routes. DEMO is a
clearly labeled selector preview with no fictional assignments. See
[route-selection architecture and current limits](docs/ROUTE_SELECTION.md).

FULL/AVAILABLE is a **manually selected driver report**, not an automatic count
or boarding guarantee. Numerical seat/occupancy fields and presentation have been
removed. Missing/outdated reports show UNKNOWN or STALE / UNKNOWN. Historical API
DEMO records never become current availability or count as fresh device reports.

**ETA is unavailable in both modes.** No arrival calculation, official routes,
stops, schedules, fares or verified GPS hardware operation are supplied. The
fictional pickup marker has been removed. The preset map center near Boac is
not the passenger's location. Find Jeepneys checks foreground permission and requests it once if needed.
My Location requests a new reading; manual selection remains permission-free.

API is the default, reading GET /api/jeepneys and the route catalog at
GET /api/routes. Ordinary API mode polls routes and vehicles every 30 seconds and
supports manual refresh with a 10-second request timeout. Freshness comes from
the latest backend response and local expiry between polls. Failures retain valid
public snapshots for a 24-hour cache lifetime, mark availability unknown and retry
with bounded backoff. The app never silently substitutes demo records. Offline DEMO retains three fictional
vehicles internally, but none are assigned to routes or exposed as passenger
results. Refresh changes the underlying examples without inventing assignments.
OpenStreetMap tiles still need connectivity in either mode.

## Implementation

Repository/controller/UI boundaries remain intact:

- lib/src/config: compile-time data mode, secure API origin, map configuration.
- lib/src/data: separate API and offline demo repositories; bounded, scoped public cache.
- lib/src/domain: immutable vehicle/status and route/assignment models, repository contracts.
- lib/src/favorites: authenticated API repository, account-scoped state and glass UI.
- lib/src/location: session-only waiting state, cancellable foreground acquisition,
  permission/error handling and reusable picker/panel.
- lib/src/presentation: controller, screens and reusable widgets.
- lib/src/presentation/widgets/glass.dart: glass panels, backdrop, controls,
  short entrance animation and reduced-motion handling.
- lib/src/theme.dart: shared Material 3 typography, colors and controls.
- test: API contract/security, simulator/controller, screen interactions,
  320-pixel layouts up to 2x text, keyboard/insets and reduced-motion checks.

Most glass depth uses static gradients, reflection borders and light shadows.
Only the small navigation surface applies clipped sigma-8 backdrop blur.
Reduced-motion settings disable that blur and the custom entrance animation.
There are no looping effects or full-screen blur filters. Foreground device
positioning uses the pinned geolocator plugin; no background tracking is enabled.
Hero text and artwork use normal layout flow with no fixed-height text overlay.

The pre-route-selection checkpoint is a2b3d22; the earlier pre-redesign checkpoint
is 40e22a2, tag pre-abangque-glass.
Existing vehicle/device APIs and application IDs are preserved. Account and
favorite migrations are additive. Android
debug-only local HTTP exceptions remain isolated; release/profile requires HTTPS.

## Visual review and physical acceptance

See [redesign verification](docs/REDESIGN.md) for checks and phone acceptance.
Optional rendered test previews (mock tiles; not real map/GPS evidence):

```powershell
flutter test test/glass_accessibility_test.dart --dart-define=CAPTURE_DESIGN=true
```

Images are written under build/design-preview. Unit/widget tests do not establish
physical-phone performance, network operation, GPS accuracy or database health.

## Map provider

The existing flutter_map integration uses HTTPS OpenStreetMap standard tiles,
a native application user agent, visible linked attribution and panBuffer: 0.
MapConfig keeps provider URL and attribution configurable. There is no offline
tile-download feature. Fleet reports remain usable if tiles fail to load.
Review the provider's usage requirements before a larger deployment:
[OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/).

## Local GPS communication testing

The passenger app supports explicitly labeled, opt-in local SIMULATED GPS updates.
See [GPS simulator and enhanced details](docs/GPS_SIMULATOR.md) for migration 003,
provisioning, manual status commands, phone launch flags, isolation and test scope.
No official operating routes or ETA calculation are introduced.
