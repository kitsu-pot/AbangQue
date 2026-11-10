# Passenger account management and privacy

Implemented 2026-11-10. Pre-change checkpoint: `checkpoint/account-privacy-2026-11-10`
at `5c13e73`. This extends the existing authentication repository/controller and
Profile screen. There is no new account system, admin UI, deployment or database
migration. Existing migrations 001–004 and application data are preserved.

## Passenger experience

Profile now groups Account information, Security, Privacy and Account actions in
reusable emerald/cream glass panels. Name editing remains inline; registered email
is read-only. Names are trimmed and must contain 1–120 characters without control
characters, validated by Flutter and Express. Only a successful API response updates
the displayed profile; an account-ID mismatch cannot replace the current identity.
An account change resets the profile editor so another passenger's name cannot linger.

Change password requires the current password, a different new passphrase and
matching confirmation. All fields have visibility toggles; controllers are disposed
with the form and values cleared after submission. The existing password policy is
reused: 15–128 characters, rejecting blank/repeated-character values and the existing
small weak-password list. Passwords are not trimmed, logged, persisted or returned.

Delete account is a separate destructive action near the bottom of Profile.
Opening the dialog does nothing to the server. The passenger must check a permanent-
deletion acknowledgement, supply their current password and press Permanently delete
account. Cancel has no effect. Controls are disabled during submission; duplicate
in-flight UI submissions are prevented. A confirmed deletion returns Profile to its
guest state with success feedback; public transport remains available.

Guests see Log In and Create Account, with no fabricated profile or authenticated
settings. Privacy & Data is available to guests too. Offline DEMO/browser previews
remain guest-only and cannot submit account actions. Public route, map, waiting-point,
status, ETA-unavailable and offline-cache behaviors are preserved.

## API contract

All account endpoints use the existing `/api/auth` prefix and an opaque passenger
bearer token. Account IDs are derived from the verified session; request bodies
cannot contain a target user ID, email change or role. JSON schemas are strict,
bodies are capped at 4 KiB, SQL values are parameterized, responses are `no-store`,
and redirects carrying credentials are refused by Flutter.

| Endpoint | Body | Confirmed response |
| --- | --- | --- |
| GET /api/auth/me | None | 200: `data.user`, `data.expiresAt` |
| PATCH /api/auth/me | `fullName` | 200: `data.user` |
| POST /api/auth/me/password | `currentPassword`, `newPassword`, `confirmPassword` | 204 |
| DELETE /api/auth/me | `currentPassword` | 204 after transaction commit |
| POST /api/auth/logout | None | 204; current token revoked |

`user` contains only id, fullName, email and PASSENGER role. There is no account-list
endpoint or public administrator registration. Profile edits preserve email, role,
password and all other fields. Existing registration/login/favorites contracts remain.

Sensitive requests return 400 `INVALID_AUTH_INPUT` for malformed bodies, weak/same
passwords or mismatched confirmation. A wrong current password returns 403
`CURRENT_PASSWORD_INCORRECT` and does **not** invalidate the login. Missing, expired,
revoked or concurrently invalidated sessions return 401 `SESSION_INVALID`.
429 `AUTH_RATE_LIMITED` requests should wait before retrying. Database/hash-capacity
failures produce generic 503 errors, never SQL details or request bodies.

## Password change and concurrency

The same node-argon2 implementation verifies the current hash and creates the new
Argon2id hash (64 MiB, three iterations, parallelism one, library-generated salt).
Existing bounded password work rejects excess concurrent operations rather than
queuing expensive work without limit.

A PostgreSQL transaction locks the account, then locks/revalidates the originating
session in a new statement snapshot. It verifies the current password, updates the
hash and revokes **all other sessions for that account** before committing. Failure
rolls back both the hash and revocations. A concurrent sensitive operation from a
revoked session fails its recheck. The initiating session retains its token and
original absolute expiry; this implementation does not rotate that current token
or extend it. Sign out revokes the current token. Previously authorized requests
already in progress may complete; revocation applies to subsequent authorization.

Login now also locks the account and compares the hash it verified with the current
stored hash before inserting a session. A login that verified an old password just
before a password change/deletion cannot mint a new session afterwards. The generic
login failure remains identical for unknown emails and incorrect passwords.

Password changes and deletion share rate limits per IP **and per authenticated
account ID**, across tokens and endpoints. Both use existing `AUTH_RATE_LIMIT`
(default 10 attempts per 15 minutes); invalid and failed attempts count. The existing
120-request/15-minute overall auth cap also applies. No new environment variable
or dependency is required. Counters remain process-local, reset on restart and
require a shared store/edge controls before multi-instance production deployment.

See [OWASP authentication guidance](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
for current-password reauthentication and throttling, and
[PostgreSQL locking documentation](https://www.postgresql.org/docs/current/explicit-locking.html)
for the row-lock behavior used here.

## Deletion, associated data and retention

`DELETE /api/auth/me` rechecks the session and current password under the same
account lock, then deletes the passenger account in one transaction. Existing
foreign keys cascade to passenger_sessions and passenger_favorite_routes. The
account row (including name, email, password hash and timestamps), its session
records and favorites disappear from the active database. There are no other
passenger-owned tables in the inspected schema. No public registered route,
jeepney, device credential, telemetry record or other passenger account is deleted.

A cascade/database failure rolls back the operation; the API does not return 204.
Concurrent duplicate deletions yield one success and subsequent invalid-session
responses. The client cannot submit another passenger's ID. A later request with a
deleted token receives 401; that alone is not proof of deletion. The old email can
be registered again as a new identity with no old favorites.

On confirmed deletion, Flutter clears identity, expiry timer, account-specific
favorites and the waiting point via existing account-change listeners, and removes
the secure token. Public caches remain available. If credential removal fails,
the UI explains the failure; that leftover token is already unusable server-side.
Late private responses cannot repopulate a signed-out/deleted account.

Deletion from the active database is not a promise of deletion from external
backups, database WAL, reverse-proxy logs or third-party infrastructure. No blanket
retention period or legal deletion guarantee is invented. Backup/log retention,
access and restore procedures must be defined before public deployment. The app
has no deployment-independent means of erasing external copies.

## Offline behavior and logout audit

Account edits, password changes and deletion are never queued or automatically
retried. A timeout, failed request or malformed response cannot produce a success
notice. The HTTP request is aborted at its timeout, but cancellation cannot undo
a transaction the server has already committed. The error therefore explains that
the outcome is unconfirmed and may have reached the server. Recheck the profile or
try the intended new password before repeating a sensitive operation. A network
failure alone preserves an already verified in-memory account; a 401 clears it.
Cold startup still requires server verification to restore the account.

Logout normally writes the existing secure pending-logout marker, clears private
UI state and calls server revocation. Offline logout retains only that unusable-for-
restoration marker until revocation can finish, with an explicit notice. If writing
the marker fails, the app still clears private memory and attempts server revocation
and secure credential removal. If both server and storage are unavailable, it reports
that durable sign-out could not be completed rather than claiming success. A new
login cannot silently reuse a pending-logout token. Public transport cache files
are not removed by logout, password change or deletion.

Favorites remain isolated by account/generation; switching accounts, session expiry,
logout and deletion clear private memory. Backend confirmation is required for all
favorite writes. No password, token, profile, favorite or passenger waiting coordinate
is added to the public cache. Existing production HTTPS and debug-only local HTTP
rules remain unchanged, including certificate verification and Android backup rules.

## In-app Privacy & Data explanation

The new screen describes the actual account fields/hashes, account-scoped favorites,
secure device credentials, permission-prompt preference and foreground one-reading
location acquisition. It explains memory-only waiting points, no waiting-point API
upload, and the public cache's 24-hour lifetime and UNKNOWN cached availability.
It also explains that OSM tile requests reveal the viewed area/network information,
including the area around a waiting point when centered there.

Passengers can manage permission through Android Settings → Apps → AbangQue →
Permissions → Location (device wording may differ). Manual selection remains usable.
The explanation is explicitly **not a formal privacy policy**. No legal entity,
contact address, policy URL, verified email ownership or arbitrary retention promise
is fabricated. A deployment-specific privacy notice and operational safeguards still
need an owner before public release. Email changes, email verification, password reset,
MFA and a comprehensive breached-password check remain outside this phase.

## Local setup and validation

Existing setup: **no new migration**, no seed and no database reset. Restart the
backend you own after updating so the new routes are loaded. Preserve `.env`.
For a fresh installation only, follow the existing backend setup and migration
instructions in [AUTHENTICATION.md](AUTHENTICATION.md) (migrations 001–004).

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink\backend
npm run check
npm test
npm run test:postgres
npm start
```

The PostgreSQL test command uses the configured local connection without printing
its secret. It creates randomly named temporary test schemas, applies existing
migrations there and removes only those schemas. It does not modify application
accounts or routes. Use a development/test database with CREATE SCHEMA permission,
never a production database. The integration suite now includes account management,
rollback triggers, password/login races, deletion cascades and existing auth/favorite/
simulator regressions.

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink
flutter analyze
flutter test
New-Item -ItemType Directory -Force build/jvm-tmp | Out-Null
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:/Users/Administrator/Projects/jeeplink/build/jvm-tmp'
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

The Java option is the existing Windows build workaround, not a networking exception.
Test/build logs and generated previews remain ignored.

## Infinix X6885 / Android 16 verification

Start the updated backend as above. Connect the phone, enable USB debugging and
accept the computer prompt. In a second terminal:

```powershell
Set-Location C:\Users\Administrator\Projects\jeeplink
adb devices -l
$phoneId = Read-Host 'Enter the Infinix device ID'
adb -s $phoneId reverse tcp:3000 tcp:3000
flutter run -d $phoneId --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Use disposable test accounts for deletion; it is a real destructive operation.

1. Continue as Guest. Open Profile: Log In, Create Account and Privacy & Data are
   available; edit/password/delete controls are absent. Return to route selection
   and the map without logging in. Read Privacy & Data and check Android permission
   settings; no permission request should come from merely opening Privacy.
2. Create a test passenger account. Open Profile, change the full name and save.
   Check success, registered read-only email and the name after leaving/reopening.
   Try blank/overlong names; nothing should be saved. While the backend is stopped,
   a failed save must leave the last confirmed profile unchanged.
3. Open Change password. Try an incorrect current password, short new password,
   mismatched confirmation and visibility toggles. Errors must leave the account
   signed in. Submit a valid new passphrase: success should say other sessions
   were signed out. This phone remains signed in until its original expiry.
4. For another-session verification, sign into the same disposable account on
   Windows before step 3 (`flutter run -d windows --debug --dart-define=DATA_MODE=api
   --dart-define=API_BASE_URL=http://127.0.0.1:3000`). Afterwards, refresh its Profile
   or favorites: its old session should receive 401. Old-password login fails;
   new-password login succeeds. No credentials belong in shell arguments.
5. If actual registered routes exist, save a favorite. Do not invent operating
   routes just for this check; isolated automated tests cover deletion cascades
   even when the local catalog is empty. Open Delete account and Cancel: the
   account must remain intact. Reopen, acknowledge permanent deletion and try a
   wrong password: it must fail without deleting the account.
6. Stop only your backend process with Ctrl+C and try deletion/password change.
   Expect an unconfirmed-operation error, no success claim and no queued action.
   Restart `npm start`, recheck the account, then retry explicitly. A lost response
   can occur after server commit; follow the unconfirmed-outcome guidance above.
7. Deliberately delete the disposable account with the correct current password.
   Expect guest Profile and a deletion notice. Old credentials and all old sessions
   should fail. Another passenger's account/favorites and public transport records
   must remain. Registering that email again creates a new empty account.
8. Sign out online and offline; verify private favorites disappear, Guest remains
   usable, and pending server logout completes after reconnecting. Sign into a
   different account and ensure the first account's profile/favorites are absent.
9. Test 200% text, the keyboard, scrolling in both dialogs, Android back/cancel,
   gesture insets and repeated taps. Recheck route direction, map interactions,
   waiting-point clearing on account changes and public cache recovery. USB reverse
   can keep the API reachable even in airplane mode; stop the backend for an API
   outage as described in [OFFLINE_HANDLING.md](OFFLINE_HANDLING.md).

No phone was attached during implementation (`adb devices -l` was empty).
Physical keyboard/autofill, secure storage, permission menus, network interruption,
frame rate and battery behavior remain unverified on the Infinix.


## Observed verification (2026-11-10)

- `npm run check`: passed.
- `npm test`: 39 passed; four opt-in PostgreSQL entry points skipped as intended.
- `npm run test:postgres`: 33 passed, no skipped tests, using real HTTP handlers,
  Argon2 and PostgreSQL in temporary schemas. Covers transactional rollback,
  session revocation, concurrent deletion/password changes, profile input and
  cross-account isolation alongside existing authentication/favorites/simulator tests.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 105 passed; one opt-in Flutter/PostgreSQL entry skipped.
  This phase did not rerun that separate Flutter-to-PostgreSQL simulator harness;
  backend PostgreSQL integration and Flutter regressions were run as listed above.
- Account/auth focused tests: 26 passed, including 320-pixel layouts at 100%/200%
  text, keyboard handling, guest navigation, visibility/confirmation, offline
  failures, ambiguous outcomes, logout cleanup and late-response isolation.
- A separate rendered-preview check passed; Profile/password/delete previews with
  test-only account data were visually reviewed. These are not device screenshots.
- Android debug build: passed in API mode with the explicit USB localhost URL;
  generated APK: `build/app/outputs/flutter-apk/app-debug.apk` (not committed).
- `adb devices -l`: no device attached. No phone installation or physical testing
  is claimed. The phone checklist above remains necessary.
