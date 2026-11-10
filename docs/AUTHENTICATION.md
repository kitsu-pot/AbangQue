# Passenger authentication

Implemented 2026-11-01. Pre-change checkpoint: `acbba76`.
Extended 2026-11-10 with [Account Management & Privacy](ACCOUNT_MANAGEMENT.md):
password change, transactional deletion, stronger concurrent-session handling and
Profile privacy information. The linked guide contains current verification results.

## Scope and user experience

API mode offers email/password sign-in, registration, Continue as Guest, profile
view/edit and sign-out. Registration collects only full name, email, password and
confirmation. The confirmation is checked locally and not sent/stored. Profiles
allow editing the full name; email remains the sign-in identifier and is read-only.
No password reset, email verification, email-change flow or admin account is
implemented. The later [Favorite Routes phase](FAVORITE_ROUTES.md) adds the first
account-scoped saved-journey feature using these same passenger sessions.

All transportation information remains public. Continue as Guest opens the same
Home, Map, Jeepneys and Guide destinations. Use the account icon in the app bar to
open a profile or return to sign-in. Offline DEMO remains guest-only, never a fake
authentication service. Browser previews are also guest-only; mobile credential
storage is not replaced by browser local storage.

Route migration 004 now provides an empty registered-route catalog for favorites.
No operating routes are seeded or real jeepney assignments supplied. Authentication
does not fabricate routes, GPS positions or ETA.

## Architecture

The Node.js/Express server uses the existing PostgreSQL connection pool. Migration
002_passenger_auth.sql adds passenger_accounts and passenger_sessions; existing
jeepney/device tables and credentials are unchanged.

Passwords use the node-argon2 library with Argon2id, 64 MiB memory, three iterations
and parallelism one. Each hash gets a random library-generated salt. Only the
encoded hash is stored. Password work is bounded to four concurrent operations,
with a generic busy response when full. Policy: 15–128 characters, including
spaces; reject empty/repeated-character and a small set of obvious weak values.
This is not a comprehensive breached-password lookup. A long unique passphrase
is recommended. Passwords are never trimmed, logged or returned.

Email is trimmed/lowercased and has a database unique constraint, including during
concurrent registration. Strict backend schemas reject extra fields such as role
or account ID. Public registration always creates PASSENGER; the database also
constrains that role. Profile access checks a live passenger session and backend
role. Future administrator authentication must have its own permissions and
authorization; passenger tokens are not device credentials or admin tokens.

Sessions use random 256-bit opaque bearer tokens, prefixed aqp_. Only SHA-256
token hashes are stored on the server. Expiry is absolute (default seven days),
checked by PostgreSQL on every protected request, with no sliding extension or
refresh token. Login creates a new independent session. Sign-out revokes the
current session server-side; other devices remain signed in. Password change revokes
all other sessions while retaining the current token and its original expiry.
Account deletion removes every session for that account. Expired/revoked
rows may be pruned later by an operator according to a retention policy.

Unknown email and incorrect password both return the same 401 INVALID_LOGIN;
unknown-email requests perform an Argon2 verification against a random dummy
hash. Registration duplicates return a generic 409 registration-unavailable
response. This registration status can still indicate an email conflict; no email
ownership/verification claim is made.

Authentication attempts are limited per IP (registration/login combined) and
per normalized login email, with a 15-minute window. All auth endpoints also have
a 120-request/window limit. These counters use the Express limiter's in-process
store: a multi-instance production rollout needs a shared limiter store and
edge-level abuse controls. Counters reset on process restart. No deployment was
performed in this phase.

Flutter uses ApiPassengerAuthRepository, AuthController and SessionStore,
separate from public vehicle and route repositories. flutter_secure_storage stores
only the session token, expiry and pending-logout flag; passwords and profile data
are not persisted. Storage keys are scoped to the API origin, preventing tokens
from being reused after changing hosts. Android backup/device-transfer exclusions
prevent copying the credential data to another device. Storage failures never
fall back to plain preferences or a fabricated signed-in state.

On launch/resume the stored token is checked with GET /api/auth/me. A stored token
alone does not establish login. Invalid/expired sessions are cleared. A temporary
network failure preserves an already server-verified in-memory identity and its
expiry timer. A cold restart still requires server verification before restoring
account UI; network failure retains the secure token and permits Guest access.
Session recovery can be retried. Protected actions always require server confirmation. A local expiry timer removes authenticated UI access;
the backend remains authoritative for all protected operations.

Sign-out first writes an encrypted pending-logout marker, then calls the server.
If offline, the app signs out locally and explicitly reports that server logout
is pending. Startup/recovery retries revocation; that marked token cannot restore
an identity. A new login first completes any pending revocation. Online sign-out
removes the local credential after server confirmation. Server-side expiry still
limits the session if the phone never reconnects. If storage cannot write the
marker, logout clears private memory and attempts server revocation/credential
removal. If durable cleanup still fails, it reports that limitation explicitly;
see the account-management guide for the fallback behavior.

## API contract

| Endpoint | Request | Result |
| --- | --- | --- |
| POST /api/auth/register | JSON fullName, email, password | 201 data: user, token, expiresAt |
| POST /api/auth/login | JSON email, password | 200 data: user, token, expiresAt |
| GET /api/auth/me | Passenger bearer token | 200 data: user, expiresAt |
| PATCH /api/auth/me | Passenger bearer token; JSON fullName | 200 data: user |
| POST /api/auth/me/password | Passenger bearer token; JSON currentPassword, newPassword, confirmPassword | 204; other sessions revoked |
| DELETE /api/auth/me | Passenger bearer token; JSON currentPassword | 204 after account/session/favorite deletion commits |
| POST /api/auth/logout | Passenger bearer token | 204; idempotent for expired/revoked tokens |

User contains id, fullName, email and role=PASSENGER. No password hash, session
hash, device credential or database credential is returned. Typical errors are
400 INVALID_AUTH_INPUT, 401 INVALID_LOGIN / SESSION_INVALID, 403 PASSENGER_REQUIRED
/ HTTPS_REQUIRED, 409 REGISTRATION_UNAVAILABLE, 429 AUTH_RATE_LIMITED and generic
503 service/busy errors. JSON bodies are limited to 4 KiB. Auth responses inherit
Cache-Control: no-store. GET /api/jeepneys and /api/jeepneys/:id stay public.

## Local setup and migration

Node.js 24 and PostgreSQL are required for accounts. From the project root:

```powershell
cd backend
npm ci
# For a new setup only: copy .env.example to .env and configure DATABASE_URL.
# Preserve your existing .env; never overwrite it or commit its secrets.
npm run migrate
npm run check
npm test
npm run test:postgres
npm start
```

Restart any old backend process after upgrading; an already-running old server
will not acquire new endpoints automatically. The migration runner verifies
checksums and applies pending migrations transactionally. Do not edit already
applied migration files or rerun DEMO seeds for this task.

The new migration was applied successfully to the configured local database in
this development session. The integration test uses that database connection to
create a randomly named auth_test_* schema, runs the real migrations/API flow,
then removes only that schema and its generated test accounts. It does not seed
test passwords into the application tables. The test database role needs CREATE
SCHEMA permission; use a dedicated development/test database, never production.

New environment settings (defaults shown; no additional signing secret required):

```dotenv
NODE_ENV=development
SESSION_TTL_SECONDS=604800
AUTH_RATE_LIMIT=10
TRUST_PROXY=false
```

SESSION_TTL_SECONDS accepts 3600–2592000. AUTH_RATE_LIMIT accepts 1–100 attempts
per 15 minutes. Production requires NODE_ENV=production and HTTPS termination;
auth endpoints reject insecure requests. TRUST_PROXY=loopback is only for a
trusted TLS proxy on the same machine. Bind the Node service privately and do not
expose a proxy-trusting HTTP origin to untrusted traffic. Never bypass certificate
validation or relax the Android release network policy.

From a second project-root terminal:

```powershell
flutter pub get
flutter run -d windows --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
# Android emulator, after starting it:
flutter run -d emulator-5554 --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Release/profile API builds require an actual HTTPS origin. The auth HTTP client
also independently enforces secure origins and refuses redirects, including
redirects carrying passwords/tokens. Public map requests never receive account
authorization headers. Never put a password/token in dart-define or a URL.

## Physical Infinix X6885 / Android 16 verification

After starting the new backend, connect the USB-debugging phone:

```powershell
flutter devices
adb -s YOUR_PHONE_ID reverse tcp:3000 tcp:3000
flutter run -d YOUR_PHONE_ID --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

1. Continue as Guest; confirm route selection, map, refresh and no invented data.
2. Open the profile icon, register with a test email/name and unique passphrase,
   then confirm the profile. No confirmation email is promised.
3. Save an edited full name. Check password visibility/confirmation errors and
   keyboard scrolling at default and enlarged fonts.
4. Force-close/reopen the app; verify recovery through the backend, not merely a
   cached profile. Sign out online, relaunch, and confirm the account stays out.
5. Try wrong-password login and duplicate registration. Check that unknown email
   and wrong password share the same login message.
6. Disconnect the backend, sign out, and confirm the pending-server-logout notice.
   Reconnect, retry session recovery, and verify the old session cannot be used.
7. Relaunch DATA_MODE=demo: accounts must be unavailable and guest routes/maps
   usable. Check gesture insets, menu visibility, map loading and performance.

No physical-phone testing is claimed. Android secure-storage/backup behavior,
actual keyboard/autofill and lifecycle behavior require this device verification.
Other desktop/Apple keychain packaging has not been runtime verified in this phase.

## Checks and references

Historical authentication-phase results (2026-11-01; current account-management results are linked above):

- `npm run check`: passed.
- `npm test`: 28 passed; the PostgreSQL suite is intentionally skipped here.
- `npm run test:postgres`: 10 passed (the parent test and nine database subtests).
- `flutter analyze`: no issues.
- `flutter test`: 40 passed, including transport regressions, authentication,
  320-pixel layouts, enlarged text and keyboard handling.
- Android debug APK: built successfully at
  `build/app/outputs/flutter-apk/app-debug.apk` with API mode and the USB-phone URL.
- Login/registration widget previews were rendered and visually reviewed. These
  are desktop test renders, not screenshots from the physical phone.

```powershell
# backend directory
npm run check
npm test
npm run test:postgres
# project root
flutter analyze
flutter test
flutter build apk --debug --dart-define=DATA_MODE=api --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

The existing project-local Java socket workaround in [REDESIGN.md](REDESIGN.md)
may be necessary on this Windows host. Backend tests use the real Argon2 library;
the separate PostgreSQL suite uses real SQL and HTTP handlers. Flutter tests mock
HTTP and secure storage and do not prove native device-storage operation.

Design references: [node-argon2](https://github.com/ranisalt/node-argon2),
[OWASP password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html),
and [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage).

## Offline public data (2026-11-09)

[Offline handling](OFFLINE_HANDLING.md) adds a separate public transport cache.
Credentials, profiles, favorites and precise waiting locations never enter it.
Existing secure token storage, revocation, logout and HTTPS restrictions are
unchanged. Previously loaded favorites remain only in the same account's memory
session; they are cleared on account change/expiry/logout and never queued for
later save/remove. Public cache access does not grant account permissions.
