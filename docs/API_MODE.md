# Running JeepLink against the backend

The old startup always used DemoJeepneyRepository. The default startup now uses
ApiJeepneyRepository and shows an **API** badge. The layout and navigation are
preserved. DATA_MODE=demo explicitly selects the original offline simulator.

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

## Explicit offline demo mode

```powershell
flutter run -d windows --debug --dart-define=DATA_MODE=demo
# Or, after starting the emulator:
flutter run -d emulator-5554 --debug --dart-define=DATA_MODE=demo
```

This mode displays **DEMO**, has three simulated vehicles and illustrative ETAs,
and requires no backend. OSM map tiles still require internet. There is no
automatic fallback from API to simulator. Change modes by stopping and relaunching
with the desired defines; hot reload does not change compile-time configuration.

## Verify in Flutter

1. API mode must show the API badge and **2 API jeepneys** on the Jeepneys tab
   when the endpoint returns those two records. DEMO-03 must not appear.
2. Each fixture shows **API · Historical DEMO**, **STALE / UNKNOWN**, **Seat count
   unknown**, and ETA **Unavailable**. The Available filter count is zero.
3. Details show last reported coordinates, measurement/last-seen UTC timestamps,
   and unavailable ETA. Historical lastReportedStatus is never substituted for
   current status. API mode does not invent a sample pickup marker.
4. Tap refresh or pull down; reads are also polled every 30 seconds. Open details
   follow the latest snapshot. Initial loading and manual refresh have progress
   indicators.
5. Stop the backend and refresh. After at most the 10-second request timeout,
   an error and Try again appear. Old API rows are cleared; no simulator vehicles
   or cached availability are substituted. Restart the backend and retry.
6. A successful empty response shows an empty state. Null positions remain in
   the list but have no map marker or enabled View location action.

API mode only performs GET /api/jeepneys. It sends no Authorization header and
stores no device credentials. The backend currently provides no passenger count,
capacity, or ETA contract, so these remain unknown/null. Even non-stale API demo
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
malformed responses, timeout, refresh/retry, and the original demo UI.
HTTP clients and map tiles are mocked: no credentials or database are needed.

The local API was unreachable during this implementation, even outside the
sandbox. Therefore the two-record behavior was verified with an exact-shape API
fixture, not a live PostgreSQL response. Android device execution remains to be
verified after starting an emulator. No backend or database contents were changed.

