# AbangQue passenger app

A Material 3 Flutter passenger application for Marinduque, Philippines, with an
original emerald/mint/cream Liquid Glass-inspired interface. English is the
current interface language. The existing internal package name remains jeeplink.

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

- Home: responsive hero, vehicle totals, fresh-device-report total, OSM preview,
  source-labeled jeepney cards.
- Map: last-reported markers, glass zoom/reset controls, selected-jeepney panel,
  linked OSM attribution, tile-error notice and retry.
- Jeepneys: shared search and All/Available filters, report cards and empty states.
- Details: manual status, report freshness, measurement and communication times,
  last coordinates, unavailable ETA and a focus-on-map action.
- Guide: English explanations of manual reports, data limitations and connectivity.
- Floating glass navigation, pull-to-refresh, loading, error and retry states.

FULL/AVAILABLE is a **manually selected driver report**, not an automatic count
or boarding guarantee. Numerical seat/occupancy fields and presentation have been
removed. Missing/outdated reports show UNKNOWN or STALE / UNKNOWN. Historical API
DEMO records never become current availability or count as fresh device reports.

**ETA is unavailable in both modes.** No arrival calculation, official routes,
stops, schedules, fares or verified GPS hardware operation are supplied. The
fictional pickup marker has been removed. The preset map center near Boac is
not the passenger's location; the app requests no location permission.

API is the default, using only GET /api/jeepneys. It polls every 30 seconds and
supports manual refresh with a 10-second request timeout. Freshness comes from
the latest backend response. Failures clear API rows and offer retry; the app
never silently substitutes demo records. Offline DEMO uses three fictional
vehicles and explicit manual-status examples; refresh changes example coordinates.
OpenStreetMap tiles still need connectivity in either mode.

## Implementation

Repository/controller/UI boundaries remain intact:

- lib/src/config: compile-time data mode, secure API origin, map configuration.
- lib/src/data: separate API and offline demo repositories.
- lib/src/domain: immutable vehicle/status model and repository contract.
- lib/src/presentation: controller, screens and reusable widgets.
- lib/src/presentation/widgets/glass.dart: glass panels, backdrop, controls,
  short entrance animation and reduced-motion handling.
- lib/src/theme.dart: shared Material 3 typography, colors and controls.
- test: API contract/security, simulator/controller, screen interactions,
  320-pixel layouts up to 2x text, keyboard/insets and reduced-motion checks.

Most glass depth uses static gradients, reflection borders and light shadows.
Only the small navigation surface applies clipped sigma-8 backdrop blur.
Reduced-motion settings disable that blur and the custom entrance animation.
There are no new dependencies, looping effects or full-screen blur filters.
Hero text and artwork use normal layout flow with no fixed-height text overlay.

The pre-redesign working checkpoint is commit 40e22a2, tag pre-abangque-glass.
Backend code/schema, application IDs and API contracts are preserved. Android
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
