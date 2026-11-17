# Running AbangQue against the backend

Phase 7A update (2026-11-17): the [ESP32 firmware foundation](../iot-firmware/README.md)
uses the existing device API. Its [Wi-Fi bench guide](../iot-firmware/docs/WIFI_TESTING.md)
explains explicit LAN binding/firewall configuration for future hardware testing.
The Android USB/loopback workflow below is separate and remains unchanged. Physical
ESP32/GPS/cellular validation is pending; no backend deployment is introduced.

Phase 6 update (2026-11-14): [Admin Live GPS Monitoring](LIVE_MONITORING.md) now provides the protected report map, filters and historical device/vehicle details. Migration 009 adds one receipt lookup index; earlier Live Monitoring deferral notes are historical.

Phase 5 update (2026-11-14): [IoT Device Management](DEVICE_MANAGEMENT.md) adds registrations, assignments, access controls and one-time credentials through migration 008. Earlier device-registry deferral notes are historical.

Phase 4 update (2026-11-14): [Route Management](ROUTE_MANAGEMENT.md) now supports verified directions, operational metadata and reversible route activation. Earlier route-deferral notes below are historical.

For the separate administrator website, follow [admin web setup](ADMIN_WEB.md).
Its browser-cookie authentication and `/api/admin` endpoints are independent of
passenger authentication; the Flutter configuration below remains unchanged.

The old startup always used DemoJeepneyRepository. The default startup now uses
ApiJeepneyRepository and shows an **API** badge on Home. All four screens use the AbangQue glass
design. DATA_MODE=demo explicitly selects the separate offline simulator.

The app now opens passenger sign-in/registration with **Continue as Guest**.
Transport reads still work as a guest. Accounts require the new passenger migration;
see [authentication setup](AUTHENTICATION.md). Offline DEMO has no fake login.

## Start and verify the backend first

From the project root, in PowerShell:

```powershell
cd backend
npm ci
npm start
```

Keep this terminal running. Existing backend/.env must point to your PostgreSQL
database, with HOST=127.0.0.1 and PORT=3000. Set INCLUDE_DEMO=true to expose the two
historical DEMO fixtures, then restart the backend. If the database has not been
set up, follow backend/README.md first; do not rerun seeds merely to make values
look fresh.

In a second terminal:

```powershell
Invoke-RestMethod http://127.0.0.1:3000/health
Invoke-RestMethod http://127.0.0.1:3000/api/jeepneys | ConvertTo-Json -Depth 6
```

Confirm the expected two IDs and their null status, isStale=true, and null eta.
An empty list with INCLUDE_DEMO=false is valid and should remain empty in Flutter.

## Windows desktop API mode

Run from the project root, with the Flutter Windows toolchain installed:

```powershell
flutter pub get
flutter run -d windows --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Windows desktop is available on the inspected machine. The Windows toolchain
requires Visual Studio's Desktop development with C++ workload; use flutter doctor
if compilation reports missing tools.

## Android emulator API mode

Start an Android Virtual Device in Android Studio Device Manager, or:

```powershell
flutter emulators
flutter emulators --launch YOUR_EMULATOR_ID
flutter devices
```

Replace YOUR_EMULATOR_ID with the ID from the first command. Then use the connected
device ID from flutter devices (commonly emulator-5554):

```powershell
flutter run -d emulator-5554 --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

No Android emulator was connected during this change. The emulator's 10.0.2.2
address is an alias to the development host's loopback interface, so the backend
can remain bound to 127.0.0.1. Do not use 127.0.0.1 as the emulator's API URL: that
would address the emulator itself. This URL is not for physical Android phones.
See [Android emulator networking](https://developer.android.com/studio/run/emulator-networking-address).

Use a current emulator (Android API 24 or later) for the domain-scoped debug
network security configuration. If requests fail, first verify the host endpoint
above, then verify emulator networking; do not disable firewalls or TLS checks.

## Physical Infinix X6885 (Android 16) via USB

Start the backend as above. Enable USB debugging, connect the phone, accept its
debugging prompt, and use the exact device ID printed by flutter devices:

```powershell
flutter devices
adb -s YOUR_PHONE_ID reverse tcp:3000 tcp:3000
flutter run -d YOUR_PHONE_ID --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

If adb is not on PATH, use the executable in your Android SDK platform-tools
directory. Repeat port reversal after reconnecting/restarting. Keep the backend
terminal running. 10.0.2.2 is for emulators, not this physical-phone workflow.
For the simulator use the same flutter run command with DATA_MODE=demo and omit
API_BASE_URL. Stop and relaunch when changing compile-time defines.

## Explicit offline demo mode

```powershell
flutter run -d windows --debug --dart-define=DATA_MODE=demo
# Or, after starting the emulator:
flutter run -d emulator-5554 --debug --dart-define=DATA_MODE=demo
```

This mode displays **DEMO UI preview** and **ETA unavailable**, and requires no
backend. Its simulator retains three unassigned vehicles internally; the passenger
UI does not display them as route results or map markers. OSM map tiles still require internet. There is no
automatic fallback from API to simulator. Change modes by stopping and relaunching
with the desired defines; hot reload does not change compile-time configuration.

## Verify in Flutter

1. Home shows API mode, From/To municipality selectors, swap and Find Jeepneys.
   GET /api/routes reads active registered records. Its table starts empty, so
   **No registered routes available yet.** is expected even if GET /api/jeepneys returns
   two historical records. There are no global All/Available filters.
2. Choose two different municipalities and tap Find Jeepneys. Only active vehicles
   explicitly assigned to that registered direction appear. Without registered
   routes/assignments, no fleet cards/markers appear; no routes are invented.
   Swapping or changing the selection clears earlier journey results.
3. Map still renders OpenStreetMap geography and controls, with no unassigned
   vehicle markers. No route lines, terminals or stops are inferred.
4. Tap refresh or pull down. Routes and vehicles poll together every 30 seconds;
   failed cycles back off to 30/60/120 seconds. Manual refresh also checks signed-in favorites.
5. Stop the backend and refresh. After failure/timeout, a compact offline notice
   appears. Valid cached routes and last known markers remain, with CACHED / UNKNOWN
   status. With no cache, a friendly empty/error state appears. Restart the backend
   and wait for automatic recovery or tap retry; no simulator substitutes.
6. Admin Jeepney Management now supplies explicit registered-route assignments.
   After a successful refresh, inactive vehicles are excluded and changed routes
   replace old assignments. Historical DEMO remains STALE / UNKNOWN, ETA remains
   unavailable, and null positions have no marker. See
   [Jeepney Management verification](JEEPNEY_MANAGEMENT.md) for exact API checks.

See [journey-selection architecture](ROUTE_SELECTION.md) for the route-service
boundary and remaining backend/admin work.

The vehicle repository only performs GET /api/jeepneys. It sends no Authorization header and
stores no device credentials. Passenger counts/capacity are absent from the app;
ETA is always unavailable pending an explicitly approved calculation. Even non-stale API demo
records never count as current availability.

Freshness is supplied by the backend on each read, not inferred from historical
FULL/AVAILABLE. Until the next successful poll the UI represents the last
snapshot; it is not a continuous live GPS feed.

## HTTP development isolation

- HTTP is accepted only in debug builds and only for localhost, 127.0.0.1, and
  10.0.2.2. Profile/release API mode requires an explicit HTTPS API_BASE_URL.
- android/app/src/main/AndroidManifest.xml explicitly disables cleartext.
- Only src/debug adds a domain-scoped network security XML allowing the three
  local hosts; other domains still require HTTPS. No release/profile overlay
  grants local HTTP and no certificate validation is bypassed.
- API redirects are refused, including HTTPS-to-HTTP downgrades.
- Invalid URL or mode configuration produces a configuration error screen.
- API_BASE_URL is an origin only: credentials, paths, queries and fragments are
  rejected. Never add device secrets to dart-define.

An eventual release uses an actual HTTPS backend URL; none is provisioned or
deployed here. Do not replace it with an invented host. The existing Android
release signing remains starter-project configuration and needs separate setup.

Reference: [Android network security configuration](https://developer.android.com/privacy-and-security/security-config).

## Checks and scope

```powershell
flutter analyze
flutter test
```

Tests cover platform URL selection, release HTTP rejection, API parsing,
historical/null status, nullable positions, absence of credentials, HTTP errors,
malformed responses, timeout, refresh/retry, and the redesigned demo UI.
HTTP clients and map tiles are mocked: no credentials or database are needed.

The owner previously verified the Windows API with PostgreSQL and launched the
app on the Infinix phone. Those are owner-reported results. The redesign tests use
mock API responses/map tiles and do not repeat physical API or PostgreSQL checks.
Backend implementation and database contents are unchanged by this redesign.

Local GPS movement testing is separately opt-in; see [GPS_SIMULATOR.md](GPS_SIMULATOR.md).
The passenger route adapter now reads GET /api/routes (empty normally), and the
vehicle adapter expires stale status between polls using backend freshness metadata.
Neither adapter sends device credentials or device updates.

## Favorite Routes

Apply migration 004 and restart the backend before using the new Home favorites
card and selected-route heart. Favorites require passenger login and reference
registered route UUIDs; no DEMO or guest favorites are persisted. See
[FAVORITE_ROUTES.md](FAVORITE_ROUTES.md) for endpoints, unavailable routes and the
physical-phone acceptance checklist. No operating routes are seeded.

## Offline recovery (2026-11-09)

Public data is cached separately from accounts for a 24-hour lifetime, with bounded
size and writes. Both datasets must return valid API responses to clear the offline
warning; a Wi-Fi connection is not evidence of backend reachability. See
[OFFLINE_HANDLING.md](OFFLINE_HANDLING.md) for storage limits, timestamps, retry
policy, privacy and exact USB-phone/API-outage versus internet-outage tests.
