# JeepLink passenger app

Phase 2 backend setup and API documentation: [backend/README.md](backend/README.md).
Flutter now defaults to the API repository. See [API mode launch and verification](docs/API_MODE.md)
for Windows and Android commands, stale/unknown status behavior, and local HTTP isolation.
Use `--dart-define=DATA_MODE=demo` to select the original offline simulator.

The remaining Phase 1 notes below describe that offline simulator, not API mode.

A first Flutter / Material 3 passenger application for Marinduque, Philippines.

**DEMO ONLY:** every jeepney, vehicle coordinate, capacity, occupancy, pickup
point, and ETA is simulated. No GPS device or backend is connected. The app
does not supply official jeepney routes, stops, schedules, fares, bookings, or
navigation instructions. The underlying OpenStreetMap geography is real;
vehicle markers and the sample pickup point are fictional.

## Run

Developed with Flutter 3.47.5 and Dart 3.13.4. Install dependencies, then select
an emulator, connected phone, or browser:

```sh
flutter pub get
flutter run --dart-define=DATA_MODE=demo
# Optional browser preview:
flutter run -d chrome --dart-define=DATA_MODE=demo
```

```sh
flutter analyze
flutter test
flutter build web
```

Android release and macOS debug/release configurations allow internet access
for map tiles. No location permission is requested. The initial viewport is a
preset area near Boac, not the passenger's location. Android/iOS distribution
signing and production application identifiers are still project setup work.

## What works

- **Home:** fleet summary, earliest available demo ETA, OSM preview, fleet cards.
- **Map:** pan/zoom/reset, selectable jeepney markers, FULL/AVAILABLE status,
  sample pickup marker, visible linked attribution, tile-error notice and retry.
- **Jeepneys:** ID/name search, all/available filter, empty state, details sheet.
- **Details:** demo ETA to the sample pickup point, occupancy, available seats,
  simulated coordinates, route disclaimer, and focus-on-map action.
- **Guide:** passenger explanations and expandable demo/privacy/map FAQs.
- **Navigation:** Material 3 bottom navigation, responsive page widths and
  scrollable layouts, refresh button and pull-to-refresh.

Refresh changes between two deterministic demo snapshots. There are no
background movement timers or fabricated live-connection indicators. FULL
vehicles can still have a sample arrival estimate; that does not promise a seat.
Fleet search/filter state is shared by Map and Jeepneys; opening a vehicle on
the map resets filters so that vehicle is visible.

## Code organization

```text
lib/
  main.dart                         # Select the repository at startup
  src/
    app.dart                        # Dependency injection, lifecycle, navigation
    theme.dart                      # Material 3 colors and component styles
    config/map_config.dart          # Tile URL, attribution, client identity
    domain/
      jeepney.dart                  # Immutable transport-independent model
      jeepney_repository.dart       # Snapshot stream / refresh / disposal contract
    data/
      demo_jeepney_repository.dart   # Simulator and explicitly fictional scenario
    presentation/
      jeepney_controller.dart       # Stream subscription, filtering, loading/errors
      screens/                      # Home, map/fleet, passenger guide
      widgets/                      # Map, details, cards, badges, vector artwork
test/
  data_and_controller_test.dart
  widget_test.dart
  fakes.dart                        # In-memory map tiles; tests do not call OSM
```

`JeepLinkApp` owns and disposes its injected repository. `JeepneyController`
cancels its own stream subscription. Map widgets own map controllers and let
`TileLayer` dispose tile providers. A `TileProviderFactory` lets tests exercise
the actual map widgets without HTTP or platform cache plugins.

## Connecting the real system later

1. Implement `JeepneyRepository` in `src/data/` for your backend protocol.
   `watchJeepneys()` should emit complete immutable snapshots, `refresh()`
   should request updated data, and `dispose()` should close connections.
2. Keep hardware credentials and device ingestion on the backend. Map validated
   backend records into `Jeepney`: stable vehicle ID, latitude/longitude,
   measurement timestamp, occupancy, capacity, optional ETA, and data source.
   Validate ranges and payloads at the boundary; constructor assertions are
   development checks, not runtime validation of untrusted telemetry.
3. GPS alone does not establish occupancy. Define the sensor/operator source
   for seats and how missing or stale measurements become **unknown**. Extend
   the status model before displaying real fleet data; never default missing
   measurements to AVAILABLE.
4. Compute actual ETAs using verified route geometry, a defined destination,
   and measured progress. Use `eta: null` when no estimate exists. The current
   ETA values are constants, not a routing algorithm.
5. Replace `DemoScenario` map/reference metadata with verified configuration.
   Add approved routes and stops only when supplied and verified by the team.
6. Inject the adapter in `main.dart`. Introduce a separately tested real-data
   mode with freshness thresholds, last-update display, reconnection behavior,
   and accurate source labels before enabling it. This UI intentionally remains
   DEMO throughout; swapping a repository alone is not a production rollout.
7. If passenger positioning is needed, add explicit permission handling and
   distinguish the user's location from the configured pickup point.

Repository stream errors and refresh failures already surface a retry state.
An error preserves the last snapshot under the error notice; a production
adapter/UI must additionally mark stale telemetry and stop presenting it as
current. Empty results and unavailable estimates are supported.

## Map provider

The default uses `flutter_map` 8.3.2 with HTTPS OpenStreetMap standard tiles,
an app-specific user agent on native platforms, visible copyright attribution,
and `panBuffer: 0`. The default network tile provider uses its built-in native
HTTP-aware cache; browsers handle web caching. There is no tile download or
offline-map feature. Fleet data and detail screens do not require the map.

Use `MapConfig` to replace the tile source and its attribution together.
Public OSM tile service is best-effort and suitable only when your usage complies
with its policy; choose a suitable provider before a larger deployment.
See the [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/)
and [flutter_map documentation](https://docs.fleaflet.dev/layers/raster-tile-layer).

The tests cover demo data integrity, refresh, filtering, stream/refresh errors,
source closure, dashboard navigation, marker interactions, vehicle details,
guide behavior, and phone layouts at normal and enlarged text sizes.
