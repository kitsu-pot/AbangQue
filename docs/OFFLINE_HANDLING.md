# Offline and weak internet handling

Implemented 2026-11-09. Checkpoint: `checkpoint/offline-2026-11-09` at
`f2589a7`. This phase changes the passenger app only. No backend endpoint,
PostgreSQL migration, operating route, assignment, firmware or deployment is added.

## What passengers see

The API repositories retain validated public routes, explicit assignments and
vehicle reports. If a request fails, the selected municipalities/direction and
last known markers remain available when a valid snapshot exists. Passengers can
choose other cached directions, search their assigned vehicles and open details.
Uncached directions never receive invented results. A successful new catalog can
remove a route or assignment; a failed request cannot revoke the selection.

Connection labels distinguish:

- Connecting/checking the API, including when a saved snapshot is already visible.
- API reachable with fresh reports, or API reachable with no fresh reports.
- Offline with saved information, or API unreachable with no saved information.

These states come from actual route and vehicle API results, not Wi-Fi/mobile
interface status or an unrelated internet probe. A valid vehicle response does not
hide a failed route request. HTTP errors (including a missing route endpoint),
invalid payloads and timeouts retain the last valid snapshot. Empty successful
responses replace older records normally. No automatic DEMO fallback exists.

Home/list screens show a rounded connection card. The map keeps its existing
viewport/state, controls and draggable sheet, with a small notice in its floating
panel during an interruption. Tap the connection label for complete dataset
receipt times and limitations; use the small retry icon for an immediate check.
The map remains pannable. No blocking offline page is inserted.

Every cached vehicle has **CACHED / UNKNOWN** current availability and an
UNVERIFIED last known location. Stored FULL/AVAILABLE metadata never becomes
current availability offline, including a report cached just seconds ago. Device
communication and GPS measurement times remain unchanged. Retrieval time means
when the app successfully fetched the dataset; it is not a new GPS report.
Connected responses still age according to the backend freshness threshold.
Historical DEMO and SIMULATED provenance remain visible. ETA stays unavailable.

Map tiles are a separate service: this is a public transport-data cache, not an
offline map download. Previously loaded tiles may remain available through the
existing map provider cache, but uncached geography can be blank without internet.
Markers, pan/zoom and the existing tile retry notice remain usable. No bulk tile
downloads or invented paths were introduced.

## Cache architecture and limits

`ApiJeepneyRepository` and `ApiRouteRepository` own validation, a last successful
in-memory snapshot, cache hydration and fallback. `JeepneyController` coordinates
both datasets and retains journey intent. A cached route catalog is shown while
the initial request is still pending. The UI does not perform HTTP or filesystem
work. The repository/controller/UI separation is preserved.

`lib/src/data/public_cache` defines a small cache contract and conditional native
file implementation. Android/Windows use an application cache subdirectory
`abangque-public-v1`; web previews use memory only. `path_provider` 2.1.6 was already
in the dependency graph and is now a direct pinned dependency, without adding a
new storage engine. Its [application cache directory API](https://pub.dev/documentation/path_provider/latest/path_provider/getApplicationCacheDirectory.html)
provides the platform directory. Files are replaced using temporary files and
[Dart file rename](https://api.dart.dev/dart-io/File/rename.html).

Rules:

- Two fixed, versioned JSON files: routes.json and jeepneys.json. Each has an API
  origin/simulation scope, successful retrieval time and an explicit field allowlist.
  Switching API origin or simulator setting cannot read the other scope's files.
  Only the latest scope is retained per dataset; there is no unbounded host history.
- Cache lifetime: 24 hours from successful retrieval. Expired/future-dated data is
  rejected on startup and on subsequent fallback attempts. Active retry checks
  enforce expiry on the next request (at most the current retry delay plus timeout).
  Expired disk entries are deleted when read; the OS may evict cache files earlier.
  There is no promise of exact-time background deletion while the app is closed.
- At most 512 KiB per serialized file and API response; at most 500 routes,
  5,000 assignments and 500 vehicles. Oversized/invalid API responses cannot replace
  a valid snapshot. Normal files total at most 1 MiB; one bounded temporary file
  per dataset can temporarily add another 1 MiB, including after a process crash.
- Disk writes occur at most once per minute per dataset per app session, with
  the first successful response saved immediately. Memory keeps every valid latest
  response. After a restart, the disk receipt time may therefore be older than the
  last response seen before closing. That original receipt time is displayed.
- Malformed, missing, wrong-version, mismatched-scope and expired files are not
  trusted. Disk failures do not discard valid API data or mark it offline; a cache
  warning explains that data may not survive restart. The cache can be rebuilt.
- Serialization uses only route IDs/directions/DEMO flags, assignments, public
  vehicle identity/operator, vehicle coordinates, measurement/receipt times,
  source and manual-status metadata. Arbitrary extra API fields are not written.

The public cache does not contain favorites, passenger IDs/profiles, passwords,
session tokens, device credentials or passenger waiting coordinates. It is separate
from secure session storage. Public data may be reused by guests and different
accounts; private account data cannot enter this cache.

## Recovery and performance

Production composition uses one controller-owned polling timer for the route and
vehicle pair. Normal successful polling is every 30 seconds; the explicitly enabled
local simulator uses 5 seconds. The first scheduled cycle uses that normal interval
after startup begins. Failed cycles then back off to 30, 60 and then 120
seconds, capped there. Delays start after a cycle completes, with a 10-second
request timeout. A healthy cycle restores the normal interval. Manual retry bypasses
the delay but shares any in-flight work. Route startup, refresh and favorite-open
requests also share an in-flight route request.

Native vehicle HTTP requests are abortable on timeout/dispose. Route HTTP clients
are closed after their request, including timeout. There are no overlapping request
pairs or accumulating periodic timers in the application composition. Standalone
vehicle-repository polling remains supported for existing consumers/tests, but is
disabled when the app uses coordinated polling. Automatic polling pauses when
backgrounded and checks immediately on resume; an already-running bounded request
may finish. No connectivity plugin, network-monitoring service or extra GPS loop
was added.

The warning clears only after valid API results for both datasets. Recovery keeps
the route if it still exists, replaces cached rows with server rows and recalculates
freshness. A reachable server returning old device data still shows STALE/UNKNOWN.
If the server supplies a valid catalog without the route, the route is no longer
offered. Polling does not establish continuous GPS communication or field accuracy.

## Accounts and favorites

An already server-verified in-memory account stays present when a temporary session
check fails. Its secure token is unchanged and the expiry timer still applies.
Only actual expiration/revocation or explicit logout clears the identity. After a
cold restart, the stored token still needs server verification before account UI
is restored; network failure keeps the credential for recovery and permits Guest
access. Cached public data never establishes an authenticated session.

Previously loaded favorites can remain visible only in that account's current
memory session, alongside their load error if the favorite service fails. Nothing
private is cached on disk. Logout/account change/expiry still clears favorites and
discards late responses. Save/remove always calls the protected API and changes
local state only after server confirmation. Failure is shown; there is no offline
write queue and guests cannot save. Opening a favorite can use the public cached
direction, clearly unverified, but does not verify that it is still active.

Waiting points remain session-only and are neither cached nor uploaded. Permission
and foreground one-fix behavior are unchanged. Release/profile still requires HTTPS;
local HTTP exceptions remain debug-only. No credentials belong in dart-define.

## Infinix X6885 / Android 16 test steps

No device was attached when `adb devices -l` was checked on 2026-11-09. Physical
performance, real radio interruptions and on-phone storage behavior remain to be
verified. Automated tests do not establish those results.

1. Start the existing local backend in one PowerShell terminal; no migration or
   new seed is required for this phase:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm start
```

2. Enable phone USB debugging, connect it and accept the computer prompt. In a
   second terminal, identify and target the Infinix explicitly:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink
adb devices -l
$phoneId = Read-Host 'Enter the Infinix device ID'
adb -s $phoneId reverse tcp:3000 tcp:3000
flutter run -d $phoneId --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

3. Continue as Guest or sign in. Let both APIs succeed. Choose a registered
   direction and open its map. If the registered catalog is still empty, that is
   the correct state: use the existing opt-in [GPS simulator workflow](GPS_SIMULATOR.md)
   to exercise markers, adding `--dart-define=DEV_GPS_SIMULATION=true` to Flutter.
   Keep its SIMULATED / DEMO labels visible. Do not seed fictional operating routes.
   This cache scope is separate from normal API mode. DEMO favorites stay disabled.
4. Note the measurement time and the route/report receipt times (tap the connection
   label). Leave the map open. Stop **only the backend you started** with Ctrl+C,
   keeping phone Wi-Fi/data on. Tap Refresh API or wait for the next poll. After
   failure/timeout, the direction/markers should remain, with CACHED / UNKNOWN and
   an offline notice. No marker moves should be invented and ETA stays unavailable.
   Try another cached direction and a direction without records.
5. Restart `npm start`. Leave the app open without tapping retry: within the next
   retry delay plus timeout it should recover, preserving an available direction.
   Retry connection gives an immediate attempt. A new current FULL/AVAILABLE needs
   a fresh backend report; simply restarting a server with old records must remain
   STALE/UNKNOWN. If using the simulator, restart/resume it as its guide describes.
6. Repeat a few brief interruptions. Refresh rapidly, background/resume, pan/zoom,
   drag the sheet and open details. Verify the camera does not reset repeatedly,
   the controls remain usable and no repeated location permission prompts appear.
7. To test cold offline startup, first allow a successful cache write, then stop
   the backend, force-stop AbangQue through Android App info and reopen it. Continue
   as Guest if account verification cannot reach the API. Saved public routes should
   appear without needing to wait for the initial request timeout; report timestamps
   must match the saved data. The precise blue waiting pin must not survive restart.
8. To test no cache, force-stop AbangQue and use Android App info → Storage & cache
   → Clear cache, then reopen while the backend remains unavailable. Expect the
   friendly no-saved-information state and no invented vehicles. Clearing app
   **storage** also removes login data. The automated suite covers 24-hour expiry
   without needing to change the phone's system clock.
9. While signed in during a warm session, interrupt the backend and resume the app.
   Verify account identity is retained, loaded favorites stay account-scoped, and
   failed save/remove does not change their state. Reconnect, retry, sign out and
   switch accounts; no other passenger's favorites should be exposed.
10. Test radio loss separately by disabling Wi-Fi/mobile data or using airplane mode.
    **USB `adb reverse` can still reach localhost while phone internet is off.**
    In that case API data may correctly remain reachable while uncached OSM tiles
    fail. For a complete transport outage over USB, stop the backend as above or
    remove its reverse mapping:

```powershell
adb -s $phoneId reverse --remove tcp:3000
# Restore it to test recovery:
adb -s $phoneId reverse tcp:3000 tcp:3000
```

11. Check enlarged font settings (including 200%), gesture-navigation safe areas,
    readable warnings and scrolling smoothness. The automated 320-pixel layouts
    pass, but real phone frame rate and weak-radio behavior need observation.

## Checks

Run `flutter analyze` and `flutter test` from the root, then the debug build:

```powershell
New-Item -ItemType Directory -Force build/jvm-tmp | Out-Null
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:/Users/Administrator/Projects/jeeplink/build/jvm-tmp'
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

The Java option is the existing Windows build workaround, not an Android networking
exception. Generated artifacts/logs remain ignored. Backend source is unchanged;
its optional `npm run test:gps:flutter` verifies the real HTTP/PostgreSQL simulator
path in a temporary schema, without changing the application schema/data.


Observed checks on 2026-11-09: `flutter analyze` reported no issues; the full Flutter
suite passed 89 tests with one opt-in database entry skipped. That separate
`npm run test:gps:flutter` check also passed (one real HTTP/PostgreSQL simulator
regression). The suite includes offline/corrupt/expired cache, timestamps, unknown
availability, timeout cancellation, single-flight/backoff, route recovery, account
privacy, background polling suspension (including the login screen), and 320-pixel
layouts at 200% text. The backend itself is unchanged, so its
standalone syntax/API suites were not rerun for this Flutter-only phase.

The final Android API-mode debug build also passed after the lifecycle fix,
producing `build/app/outputs/flutter-apk/app-debug.apk` (ignored build output).
`adb devices -l` showed no attached device; no physical-phone installation,
radio interruption, frame-rate or battery test is claimed.
