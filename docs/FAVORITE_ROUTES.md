# Favorite Routes

Implemented 2026-11-07. Pre-change checkpoint:
`checkpoint/favorites-2026-11-07` at `16953e9`.

## Passenger behavior

Home contains a compact Favorite Routes glass card; the four navigation tabs
remain unchanged. A selected registered route has a heart in the floating map
panel. Outline means unsaved; filled means saved. Save/remove is confirmed by
the server before the icon/list changes. Requests in progress disable duplicate
taps. Home and Map refresh also refresh favorites; the Home card has its own
refresh/retry control. Network errors never substitute local favorites.

Guests can search journeys, open maps and view public transport reports. Tapping
the heart or Access Favorite Routes opens the optional Log In / Create Account /
Not Now sheet. The existing authentication screens return to the same selected
journey after successful login or registration. Nothing is saved automatically.
Not Now and Android Back leave the journey unchanged. Offline DEMO is still
guest-only; neither offline directions nor the local GPS simulator direction can
be saved. No guest favorites are stored or uploaded.

Favorite rows show the ordered municipalities. Opening a favorite re-fetches the
public route catalog, selects the exact route ID and opens the existing map flow.
Reverse directions and multiple records in one direction remain separate IDs.
Inactive/deleted routes show Route unavailable, cannot open, and can still be
removed. A route becoming unavailable since the last list refresh is checked again
on open. If the catalog cannot be reached, opening fails with a retryable error.
No route geometries, vehicle assignments, seat counts or ETA are invented.

## Architecture and security

Flutter's `ApiFavoriteRepository` / `FavoriteController` / reusable favorite widgets
extend the existing repository/controller/UI architecture. Favorites live in
PostgreSQL, with only the current account's list cached in memory. Account changes,
logout and invalid sessions clear that list. Late responses from a previous account
are discarded. Startup uses the existing secure-session restoration, then fetches
favorites. A second device signed into the same account reads the same records;
manual refresh picks up changes made elsewhere. There is no offline write queue.

The auth controller supplies the bearer token inside the repository boundary;
widgets never handle it. Existing origin-scoped secure device storage, expiration,
pending logout and server revocation are preserved. Favorites reject redirects,
use a 10-second timeout, and share authentication's origin validation: HTTPS except
debug-only localhost / 127.0.0.1 / Android emulator 10.0.2.2. Release/profile Android
cleartext restrictions are unchanged. No new environment variables or dependencies
are needed; use the existing DATA_MODE and API_BASE_URL settings.

Express reuses the live passenger-session/role guard. A valid, unexpired,
non-revoked PASSENGER session is required for every favorite operation. Identity
always comes from that session, never a client user ID. Device tokens and future
admin roles cannot use this passenger API. All SQL is parameterized and every
favorite query is account-scoped. Responses inherit Cache-Control: no-store.
Production authentication/favorites require HTTPS; untrusted forwarded headers
do not bypass it. Favorites have a 120-request/minute/IP in-process limiter.
As with existing rate limits, shared counters are needed before multi-instance
deployment; no deployment is part of this change.

## Database and route availability

`004_favorite_routes.sql` adds only:

- `registered_routes`: UUID, origin, destination, active flag, creation time.
  Municipality constraints and distinct endpoints apply. IDs represent directions.
- `passenger_favorite_routes`: passenger FK, stable route key, nullable route FK,
  server-copied municipality labels and save time. The composite primary key
  prevents duplicate saves, including concurrent requests. Deleting an account
  cascades its favorites. Deleting a route nulls its FK while retaining the key and
  labels, so passengers can see and remove the unavailable favorite.

Save locks the active route and inserts in a transaction; duplicate PUTs are
idempotent. Route existence/active state is checked by PostgreSQL. Flutter cannot
register a route by submitting free-text municipality names.

**No operating routes are seeded.** The inspected backend previously had only an
empty/opt-in DEMO catalog, so a minimal stored route catalog is necessary for real
favorite references. GET /api/routes now reads active registered records and keeps
the separately gated simulator fixture. Real route assignments remain empty.
The existing simulator assignment stays explicitly DEMO and is not saveable.

Administrator registration/verification, permissions, route-editing tools and
jeepney-assignment management remain future work. Until authorized operators supply
verified records, the normal app correctly shows No registered routes available
yet. A passenger choosing municipalities never creates such a record. Do not copy
the automated test fixtures into the application database as operating routes.

## API contract

All favorite endpoints require `Authorization: Bearer <passenger-session-token>`.
Do not put real tokens into source files, screenshots or command history.

| Endpoint | Success | Behavior |
| --- | --- | --- |
| GET /api/favorites | 200 `{data: [...]}` | Current passenger only; includes unavailable favorites |
| PUT /api/favorites/:routeId | 204 | Save an active registered UUID; repeated saves have no duplicate effect |
| DELETE /api/favorites/:routeId | 204 | Remove only the current passenger's favorite; idempotent |

A list row contains routeId, origin, destination, available (boolean), savedAt
(ISO timestamp). No request body or query parameters are needed. Extra body fields
and all query parameters are rejected. Invalid UUIDs return 400; unavailable routes
return 409; missing/expired/revoked sessions return 401; wrong role or insecure
production requests return 403; rate limiting returns 429; database failures return
generic 503 without private details. GET /api/routes and /api/jeepneys remain public.

## Local setup and verification

Use the existing PostgreSQL connection in ignored backend/.env. Do not overwrite
it or re-run demo seeds. From the workspace root in PowerShell:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm run migrate
npm run check
npm test
npm run test:postgres
npm start
```

Stop an old backend using Ctrl+C in its terminal before `npm start`, so it loads
the new endpoints. Migration 004 was applied to the local database during this
task. The migration runner is checksum-protected and skips already-applied files.
Other machines must apply it before starting the updated backend.

The PostgreSQL suite applies migrations 001–004 in a random temporary schema.
Registration/login use real Argon2 and sessions, and favorite HTTP requests use
real SQL. Two directional fixtures exist only inside that test schema, which is
removed in finally. It does not seed routes/accounts into the application schema.
The configured development DB role needs CREATE SCHEMA permission for these tests.

Flutter checks from the workspace root:

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

If this Windows machine reports the known Java socket temporary-directory issue,
use the existing build-only workaround before the build:

```powershell
New-Item -ItemType Directory -Force build/jvm-tmp | Out-Null
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:/Users/Administrator/Projects/jeeplink/build/jvm-tmp'
```

## Infinix X6885 physical-phone verification

This checklist has not been performed on the physical phone by the agent.

1. Enable USB debugging, attach the Infinix and accept the computer's RSA prompt.
   Start the migrated backend on 127.0.0.1:3000 using the preceding commands.
2. In another terminal, identify the exact phone, reverse the backend port and run:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink
adb devices
flutter devices
$phoneId = Read-Host 'Enter the Infinix device ID shown above'
adb -s $phoneId reverse tcp:3000 tcp:3000
flutter run -d $phoneId --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

3. Continue as Guest. On Home, tap Access Favorite Routes. Verify all three prompt
   actions. Not Now keeps the journey; login/registration stays optional. Search,
   map and waiting-location controls remain usable without an account.
4. With the current empty registered catalog, verify the honest empty state and
   absence of a saveable DEMO heart. Completing the following save checks requires
   actual verified route records supplied by an authorized operator. No route
   registration screen or fictional manual seed is provided by this phase.
5. Once a verified record exists, choose its origin/destination and Find Jeepneys.
   Tap the map heart as a guest, sign in or register, and verify the same direction
   remains selected and unsaved. Tap again to save. Check the filled heart and
   Home row, reopen it, and remove it. If a separately registered reverse direction
   exists, save both and verify removing one leaves the other intact.
6. Save, close/restart the app and verify restored favorites after secure session
   recovery. Sign out/in and verify persistence; another passenger must see only
   their own favorites. Signing in on another device should show the same list.
7. Stop the backend temporarily. Save/remove/refresh must show an error without
   claiming success. Restart it and retry/refresh. Rapid taps must not duplicate
   records. Logout/expired sessions must clear private favorites.
8. When an operator deactivates a registered route, refresh: its favorite must read
   Route unavailable and refuse opening. Removal must still work. If deactivated
   after the last refresh, opening must recheck and refuse it.
9. Check enlarged Android font size, keyboard/back handling, gesture insets, map
   controls, readable glass surfaces, permission denial, manual waiting points,
   source labels, STALE/UNKNOWN and ETA unavailable. Assess scrolling and frame
   smoothness on the actual phone; automated layout checks cannot establish this.

For Windows desktop, replace the run target with `-d windows` and keep localhost.
For an Android emulator, use its explicit device ID and
`--dart-define=API_BASE_URL=http://10.0.2.2:3000`; that address is not for the phone.

## Observed verification

Fresh results on 2026-11-07:

- Backend syntax check passed; database-free tests: 35 passed, 3 PostgreSQL entry
  points intentionally skipped in that command.
- Actual PostgreSQL suite: 24 passed, including registration/session recovery,
  directional duplicates, account isolation, deletion/inactivation and revocation.
- Flutter analyze: no issues. Full Flutter suite: 76 passed, 1 opt-in integration
  test skipped. After adding Map refresh recovery, all 11 focused favorite tests
  passed, including 320-pixel layout checks at 200% text.
- The separately opted-in Flutter → HTTP → PostgreSQL GPS regression passed
  (1 test), covering route markers, waiting-point privacy and stale recovery.
- Android debug APK built successfully in API mode with localhost port 3000, using
  the documented Java socket workaround. Artifact:
  `build/app/outputs/flutter-apk/app-debug.apk` (generated, not committed).
- Migration 004 applied successfully to the local application database without
  seeding operating routes.

No physical-device, GPS hardware, official-route verification or deployment is
claimed.
