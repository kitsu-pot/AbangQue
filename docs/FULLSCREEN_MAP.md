# Full-screen passenger map

Implemented 2026-11-06. Before-change checkpoint:
`checkpoint/map-redesign-2026-11-06` → `84ba388`.

## What passengers do

1. Choose From and To, then **Find Jeepneys**. The app opens Map even when no
   registered routes exist. Only assigned vehicles for the chosen direction appear.
2. The app checks foreground permission and, if appropriate, asks once. Granting
   permission obtains one device reading and displays the blue passenger pin.
   There is no extra confirmation page in this normal flow. Denial/failure shows
   a small message; passengers can still browse routes, reports and the map.
3. Tap the floating direction or its arrow to edit the journey in place. Only
   Find Jeepneys initiates detection; changing dropdowns does not. A deliberately
   selected manual waiting point is retained when finding another journey.
4. Drag the jeepney sheet between collapsed, partial and expanded positions. Its
   header provides accessible expand/full-list/collapse buttons. Scroll the list
   inside the sheet. Collapse controls remain fixed while the list scrolls.
5. Tap a bus marker or compact jeepney card to select it, focus its last reported
   coordinates and show a summary. **View report details** opens existing full
   details. Missing GPS, historical DEMO and STALE / UNKNOWN remain explicit.
6. Use **My Location** for another one-time reading. This does not follow movement.
   The fit-screen control appears when a passenger point and selected jeepney both
   have coordinates. Camera padding accounts for the sheet and top controls.
7. Open **Waiting location options** in the three-dot menu for source, time,
   accuracy, settings, manual selection, change and clear. Manual tap selection
   retains confirmation/cancel. Home and Jeepneys have a small link to this menu.

ETA stays unavailable. FULL/AVAILABLE is a driver report, never a seat count or a
boarding guarantee. The blue pin is a reference, not a verified stop/terminal or
proof that the selected jeepney travels past it. No fictional path is drawn.

## Implementation and privacy

- `RouteMapScreen` owns viewport layout, route-edit overlay and sheet extent.
  `FleetScreen` now handles the list tab only; its old embedded map is removed.
- `JeepneyController` retains route filtering/search and selected vehicle identity;
  summary/markers read the latest vehicle object, including stale transitions.
- The existing `JeepneyMap` handles OSM, markers, tile errors/retry and attribution.
  Full-screen mode uses minimal controls; the manual picker keeps zoom controls.
- `WaitingLocationController` owns session-only reference and acquisition state.
  It rejects late results after cancellation/clear/account changes. Backgrounding,
  switching away from Map, manual editing and disposal cancel automatic acquisition.
- `ForegroundDeviceLocationService` checks granted access first. When denied, it
  prompts only if no attempt was recorded. The existing secure-storage dependency
  stores one boolean, `abangque.location.permission-requested.v1`. No account ID,
  coordinates or location history accompany it. Storage errors do not cause a
  permission prompt. After denial, use Android settings and explicitly retry.
- Position acquisition stops after the first fix or a 20-second acquisition
  timeout. Old fixes are rejected; low accuracy and mock locations are disclosed.
  No background permission, location notification or ongoing passenger tracking.
- OSM requests reveal the viewed tile area and network address to the tile provider;
  passenger coordinates are never sent as an API payload or account property.
- No dependencies, backend code, database migrations, credentials or release HTTP
  exceptions were added. Existing development-only localhost HTTP rules remain.
- Glass panels use gradients/borders; only the existing navigation bar blurs.
  Sheet button animations respect reduced motion. No full-map backdrop blur.

## Automated verification

Fresh results on 2026-11-06: `flutter analyze` reported no issues; `flutter test`
passed 66 tests with the opt-in database test skipped. That PostgreSQL/Flutter
integration passed separately, including an assertion that the selected marker
stays above the expanded sheet. Final narrow-screen render checks at 1x/2x text
also passed and were visually reviewed using fixture tiles. Android debug build
passed; its output includes a JDK native-access warning, with no build errors.
These checks do not establish physical-phone performance or real GPS accuracy.

From the project root:

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=DEV_GPS_SIMULATION=true
```

The normal suite uses fake native positioning and map tiles. It verifies Find
navigation, automatic location, permission denial persistence across service
restoration, manual fallback/change/clear, account separation, cancellation, route
filtering, sheet/map gestures, large text and existing app behavior. Native system
permission dialogs and actual phone sensor accuracy are not exercised by it.

The existing isolated PostgreSQL integration is run separately:

```powershell
Set-Location backend
npm run test:gps:flutter
```

This verifies simulated device updates → PostgreSQL → API → Flutter, including
moving/stale/recovered markers, the waiting reference, sheet-aware camera framing
and reverse-direction filtering. It requires existing local database configuration
and creates/removes only a temporary test schema. No real hardware is claimed.

## Infinix X6885 / Android 16 checks

Start the existing backend and, optionally, its explicitly labeled local simulator
as documented in [GPS_SIMULATOR.md](GPS_SIMULATOR.md). Connect the phone with USB
debugging enabled and use its device ID:

```powershell
adb devices
adb -s <phone-id> reverse tcp:3000 tcp:3000
flutter run -d <phone-id> --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=DEV_GPS_SIMULATION=true
```

Omit the simulation flag for ordinary API mode. Offline DEMO remains selectable
with `--dart-define=DATA_MODE=demo`; unassigned demo vehicles are still hidden.
Emulators use `http://10.0.2.2:3000`; the physical USB phone uses the command above.
The APK copy is `build/app/outputs/flutter-apk/abangque-fullmap-debug.apk`.

- Enter as Guest; change dropdowns and verify no prompt yet. Find Jeepneys should
  open Map and show the system foreground prompt if permission was never requested.
- Grant precise or approximate access. Check the blue point and estimated accuracy
  in the menu; acquisition must stop after one reading. Verify My Location retries.
- Deny permission. Map/jeepney results must remain usable. Repeat Find and restart:
  no repeat dialog. Open app settings from the menu, grant foreground permission,
  return and tap My Location. A fresh installation/app-data reset is needed to
  repeat the first-prompt scenario; clearing data also removes saved login sessions.
- Disable Location or try poor reception. Check non-blocking errors, settings links,
  timeout and manual fallback. No fabricated position may appear on failure.
- Choose/change a manual point; cancel must retain the previous one. Change journey
  and verify the manual reference remains. Clear and verify marker removal.
- Drag/pinch the map; drag/scroll all three sheet states. Select a jeepney and check
  the marker remains above the sheet. Test large fonts, status/gesture bars,
  keyboard and TalkBack, especially expand/collapse and route editing.
- With the simulator, check movement, driver-selected FULL/AVAILABLE and pause until
  STALE / UNKNOWN. All DEMO labels and unavailable ETA must remain accurate.
- Leave the app during acquisition; returning must not restart it. Restart/logout
  must clear the waiting point. Check smoothness and battery use on the real phone.

No physical-phone verification is claimed by this implementation.
