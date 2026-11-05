# Passenger waiting location

Implemented 2026-11-02. Checkpoint `aa6fd70` preserves the preceding GPS-simulator
and jeepney-details phase. No backend code, schema or existing database records
were changed for waiting locations.

## Passenger flow

Choose a municipality direction and Find Jeepneys as before. The optional **Your
waiting location** glass panel appears on Home, Map and Jeepneys. Browsing remains
available without choosing a point or signing in. Empty registered-route catalogs
stay empty: choosing a location never creates a route or assigns a vehicle.

- **Use My Location** opens a preview and requests one foreground device reading.
  Check the blue pin, coordinates, device measurement time and estimated accuracy,
  then press **Confirm Location**. Permission is requested only after this action.
- **Choose on Map** opens the same OpenStreetMap picker without asking permission.
  Tap anywhere on the map to place/reposition the pin; pan and zoom as needed.
  This implementation uses tapping, not dragging the pin. Confirm commits the
  draft; Cancel or Android Back leaves the previous confirmed point unchanged.
- **Change Location** reopens the confirmed point as a draft. Use My Location can
  also replace it after confirmation. **Clear Location** removes it immediately.
- **View waiting point on map** opens Map. Its blue person marker is separate from
  jeepney bus markers. Select a jeepney, then use **Show waiting point and selected
  jeepney** (fit-screen icon) to frame both. Updates continue to frame both until
  a manual map gesture or another centering action. No connecting route is drawn.

The initial Boac map view is only an area reference. A chosen point is **not a
verified stop, terminal, safe boarding place, or promise that a jeepney passes or
stops there**. The interface explains that boarding depends on actual routes and
operating practices. ETA remains unavailable in every mode. No distances, speeds,
seat counts, operating routes or boarding guarantees are generated.

## Architecture and privacy

`lib/src/location/waiting_location.dart` holds validated coordinates, deviceGPS or
manualMap source, selection time, optional device measurement time/accuracy, and
mock-reading disclosure. `isVerifiedBoardingPoint` is always false. The
`WaitingLocationController` is memory-only, owned by the app composition root.
The picker owns an unconfirmed draft. The device-service interface is injectable
for tests; presentation uses the existing glass components and OSM map.

There is **no waiting-location repository, HTTP write, PostgreSQL table, account
field, preference, secure-storage entry, location log or history**. A point lasts
only for this app session, survives tab/route changes, and clears on explicit
clear, process restart, login/account change, logout or session expiry. It is not
restored with a saved account session. Signing in while a picker is open cannot
commit the old account/guest draft.

Viewing OSM still requests tiles for the visible geographic area. The tile
provider can observe that area and the network address; no pin payload, passenger
account or auth token is sent with the requests. This is not a guarantee of an
entirely offline/private map. Manual selection still works on the map surface if
tiles fail, but the passenger must check the coordinates and should retry tiles
before choosing a real-world point.

Future ETA or verified boarding-point features should consume a separately
validated selection plus administrator-managed route geometry and fresh vehicle
reports. A manual/device point alone provides none of those assurances. No ETA
service or admin feature is implemented here.

## Device permission and acquisition behavior

The pinned `geolocator` 14.1.2 dependency supplies native foreground positioning.
Android declares coarse and fine permission, allowing approximate access. It
explicitly excludes background location and foreground-service permissions from
the merged manifest. No location notification/foreground-service configuration
is used. Release cleartext policy and existing debug-only HTTP exceptions remain
unchanged.

After permission, the service uses a short-lived position subscription solely
to allow cancellation: it accepts one reading and immediately cancels. Acquisition
times out after 20 seconds, excluding the user-controlled permission prompt and
initial service/permission checks (each bounded to 5 seconds). Cancel, manual
selection, leaving the foreground or disposing the picker also stops acquisition.
Returning to the app never restarts it automatically. The Android permission
dialog may make the app inactive; actual paused/hidden/detached states cancel it.

Denial, permanent denial, disabled services, timeout and unavailable positioning
have explicit messages. Settings actions are user-initiated; return and tap Retry.
Manual selection works in every failure state. Device fixes older than two minutes
or over 30 seconds in the future are rejected; confirmation rechecks age. The
displayed accuracy is the device estimate, not a guarantee. Values over 100 metres
receive a low-accuracy warning (a UI threshold, not a transport/safety standard).
Unknown accuracy is explicit; mock device readings are labeled DEMO. Moving a
device-derived pin manually changes its source to manual and clears GPS metadata.

Native acquisition is enabled on Android and Windows in this phase. Other targets
retain the manual picker; Apple permission configuration is not added. Windows
position availability depends on the OS location service and hardware and may
not be satellite GPS. Physical platform behavior still requires device testing.
See the [plugin documentation](https://pub.dev/packages/geolocator) and
[Android foreground permission guidance](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime).

## Run and automated checks

From the project root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=DEV_GPS_SIMULATION=true
```

The simulator flag exposes only explicitly labeled local DEMO records when the
backend also enables its existing simulation option. It does not enable hardware
GPS or registered operating routes. Omit it for ordinary API mode. No waiting
location migration, seed, environment variable or credential is needed.

`test/waiting_location_test.dart` covers the native-service boundary with a fake
platform, permission outcomes, one-reading cancellation, timeout/error/old fixes,
mock/accuracy labels, coordinate validation and Android manifest safeguards.
`test/waiting_location_widget_test.dart` covers guest/manual confirmation,
change/cancel/clear, navigation, settings/retry, background cancellation, account
separation and 320-pixel layouts at 1x/2x text. These do not test a phone sensor.

The opt-in real PostgreSQL integration uses the existing isolated simulator harness:

```powershell
Set-Location backend
npm run test:gps:flutter
```

It requires the existing local `.env` database setup and permissions to create/drop
a temporary test schema. It never reads a device secret into Flutter. The test
combines a manually confirmed waiting point with authenticated simulated device
updates, public route reads, moving/stale/recovered markers, show-both camera fit
and reverse-direction filtering. It asserts passenger API requests remain GETs
to existing endpoints without waiting coordinates. The temporary schema is removed
afterwards. The normal Flutter suite skips this test unless the harness supplies
its local URL. See [GPS_SIMULATOR.md](GPS_SIMULATOR.md) for simulator setup.

## Infinix X6885 / Android 16 verification

Fresh verification on 2026-11-02: `flutter analyze` reported no issues;
`flutter test` passed 66 tests with the one opt-in database test skipped;
`npm run test:gps:flutter` separately passed that real PostgreSQL/Flutter test.
Both narrow-screen preview cases also passed with real fonts and were visually
reviewed (test map tiles are blank fixtures, not evidence of real OSM downloads).
The final Android debug APK built successfully. The merged debug manifest contains
coarse/fine foreground permissions and no background or foreground-service location
permission. Build output has a JDK native-access warning; no build errors.
The unchanged release manifest still prohibits cleartext; its release APK was not
built in this phase. No phone sensor, permission dialog or battery behavior was
physically verified.

The built local debug copy is
`build/app/outputs/flutter-apk/abangque-waiting-debug.apk`, configured for the
localhost API and explicit development simulation catalog. The standard
`app-debug.apk` contains the same build.

No physical-phone test is claimed. With the existing backend running locally and
USB debugging authorized, use the actual device ID shown by these commands:

```powershell
adb devices
flutter devices
adb -s <phone-id> reverse tcp:3000 tcp:3000
flutter run -d <phone-id> --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=DEV_GPS_SIMULATION=true
```

For offline DEMO use `flutter run -d <phone-id> --debug --dart-define=DATA_MODE=demo`.
For an Android emulator the host API alias is `http://10.0.2.2:3000`, not the
physical-phone URL. OSM tiles need phone/emulator internet access in either mode.
Production API origins still require HTTPS.

1. Enter as Guest. Verify no location prompt on startup or route browsing.
2. Choose on Map, tap/reposition, confirm, switch tabs, change/cancel, then clear.
   Check navigation/gesture areas and larger Android font/display settings.
3. Use My Location; allow foreground precise access. Check coordinates against
   the actual place, estimated accuracy and blue preview, then confirm. Ensure
   location acquisition stops; it must not restart when navigating tabs.
4. Repeat with approximate access, denial, permanent denial and Location switched
   off. Check settings return, explicit Retry, and manual fallback. Try poor
   reception for timeout/low accuracy; exact accuracy is environment-dependent.
5. Leave the app or press Back during acquisition; return and verify no late pin
   is silently confirmed. Move a GPS preview manually and check the source changes.
6. With the existing labeled simulator enabled, choose its DEMO direction, select
   its jeepney and frame both markers. Pause the simulator until STALE / UNKNOWN;
   the waiting pin must remain and ETA must stay unavailable. Reverse directions
   must not reveal unassigned vehicles. No connecting road path should appear.
7. Confirm a waiting point, restart the app, and verify it is gone even if an
   account session restores. Repeat logout/login and verify the point is cleared.
8. Check positioning stops after confirmation/cancellation/backgrounding, OSM
   tile error/retry, portrait/landscape layout, TalkBack labels and battery behavior.

The local JDK occasionally needs a short writable socket directory for Gradle.
If that known environment issue occurs, create `build/jvm-tmp` and set
`$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:/Users/Administrator/Projects/jeeplink/build/jvm-tmp'`
in the build shell. This is a local tooling workaround, not an app requirement.
