# Device API integration — inspected 2026-11-17

The implementation, not a new firmware protocol, is authoritative:
[app.js](../../backend/src/app.js), [validation.js](../../backend/src/validation.js),
[security.js](../../backend/src/security.js), [repository.js](../../backend/src/repository.js),
[config.js](../../backend/src/config.js),
[admin repository](../../backend/src/admin-device-repository.js), migrations
[001](../../backend/migrations/001_initial.sql),
[003](../../backend/migrations/003_simulated_device_source.sql) and
[008](../../backend/migrations/008_device_management.sql).

## Identity, authentication and headers

`POST /api/device-updates` takes `Authorization: Bearer <credential-uuid>.<secret-hex>`.
The UUID is 36 characters; the secret is 32 random bytes represented by 64 hexadecimal
characters. Admin provisioning produces lowercase hex. Secret case is significant
because hashing uses the supplied secret string. Do not normalize/copy only part of it.
The server stores a SHA-256 secret hash, never the retrievable token.

Required media type: `Content-Type: application/json`. Firmware also sends
`Accept: application/json`. No administrator cookies, passenger credentials, CSRF
headers or MAC-address headers belong here. Device updates are not browser requests.

Three identities are deliberately separate:

| Value | Meaning / source |
| --- | --- |
| Admin device ID | Stable `iot_devices.id`, 1–96 uppercase letters/digits/underscore/hyphen, beginning with letter/digit; copy locally for inventory |
| Credential UUID | One credential version bound to the registered device and jeepney; sent inside bearer token |
| `jeepneyId` | Exact administrative assignment returned by provision/rotation, 1–64 uppercase letters/digits/underscore/hyphen, beginning with letter/digit |

The strict body **does not accept `deviceId` or `source`**. The backend resolves device
identity/source from the credential. Copying another vehicle ID into firmware cannot
reassign a device. Route assignment is unrelated and stays administrative.

## Request fields (exactly five)

| Field | Backend rule | Firmware behavior |
| --- | --- | --- |
| `jeepneyId` | Valid ID, equal to credential's vehicle binding | Uses provisioned assignment |
| `latitude` | Finite JSON number from -90 through 90 | Validated actual RMC latitude |
| `longitude` | Finite JSON number from -180 through 180 | Validated actual RMC longitude |
| `status` | Exactly `FULL` or `AVAILABLE` | Debounced manual control; UNKNOWN suppresses reporting |
| `timestamp` | Valid ISO date/time with timezone | Original GNSS UTC date/time as `YYYY-MM-DDTHH:mm:ss.sssZ` |

No optional heartbeat, status-only report, null-coordinate update, seat field, route
field, device-selected source or ETA is accepted. Extra fields fail strict validation.
When GPS or driver selection is unavailable, **send nothing**. Wi-Fi connectivity does
not create a new last-communication record in PostgreSQL.

Default server timestamp limits: at most 86,400 seconds old and at most 30 seconds
ahead of server time (`MAX_UPDATE_AGE_SECONDS`, `MAX_FUTURE_SKEW_SECONDS`). The firmware
is intentionally stricter: measurement/reception age <=5 seconds, GNSS time <=1 second
ahead of synchronized UTC, valid date in 2024–2099. It never substitutes submission
time for measurement time. Leap seconds (`ss=60`) are rejected rather than normalized.

Backend coordinate range validation does not verify GPS accuracy, receiver provenance
or physical hardware. A source of `device` means credential-authorized telemetry;
it is not proof of a tested physical tracker. All synthetic fixtures stay in tests
with in-memory repositories. The existing development simulator has separate
`simulated` provenance and remains unchanged.

## Frequency, freshness and duplicate behavior

`DEVICE_RATE_LIMIT` defaults to **120 POST attempts/minute per IP**, before device
authentication; several devices behind one router share it. JSON size limit is 8 KB.
Firmware defaults to 30 seconds per attempt (two requests/minute/device), configurable
10–300 seconds, with no extra immediate POST for switch movement. Manual changes are
captured locally immediately after debounce and go in the next eligible report.

The server's default `STALE_AFTER_SECONDS=120` applies to both measurement and receipt
age. Keep the field interval comfortably below the chosen stale threshold; large
intervals/backoff can legitimately show UNKNOWN. Duplicate `(credential_id,
recorded_at)` produces 409 and **does not refresh receipt time**. Out-of-order packets
can be stored, but do not replace the newest measured location. Firmware avoids
reusing a measurement timestamp and has no backlog queue.

## Responses and firmware action

| HTTP | Response / cause | Action |
| --- | --- | --- |
| 201 | `data: { id: string, jeepneyId, source: "device", isSimulated: false, receivedAt: ISO UTC }` | Validate body/provenance/identity; next normal interval |
| 409 | `error: "DUPLICATE_UPDATE"` | Do not relabel it as a new success or refresh; wait normal interval for a new fix |
| 401 | `UNAUTHORIZED`: missing/malformed/unknown/wrong/revoked key, disabled device, lost binding, or race recheck | Halt and persist rejection digest; new credential required |
| 403 | `DEVICE_NOT_ASSIGNED` or `SIMULATION_DISABLED` | Halt and persist digest; verify assignment and use actual hardware provisioning |
| 400 | `INVALID_UPDATE` with `fields`, `TIMESTAMP_OUT_OF_RANGE`, or `INVALID_JSON` | Halt until local config/clock/contract issue is investigated |
| 413 | `BODY_TOO_LARGE` | Halt |
| 415 | `JSON_REQUIRED` | Halt |
| 404 / redirects / other unexpected response | Wrong path/proxy/contract | Halt; no redirect is followed with the bearer token |
| 429 | `RATE_LIMITED`, rate-limit headers and typically `Retry-After` | Retry current fresh data after backoff; honor delta-seconds up to one hour |
| 503 | `SERVICE_UNAVAILABLE` (sanitized DB/server error) | Transient retry |
| 408, other 5xx, transport failure/timeout | May be a proxy or an uncertain submitted outcome | Transient retry using a NEW current fix |

Backoff with default interval: 30, 60, 120, 240, then 300 seconds maximum, resetting on
accepted/duplicate responses. A numeric Retry-After may extend this to one hour.
HTTP-date Retry-After is not interpreted; use exponential fallback. A malformed 201
body halts because acceptance cannot be trusted. Errors/response bodies and headers
are never printed. A timeout can occur after the server commits; it is not proof of
rejection. The next attempt preserves its own new measurement timestamp.

## Admin lifecycle and storage

Register actual hardware, assign an eligible active real jeepney, enable it, then
provision once through the existing [Admin workflow](../../docs/DEVICE_MANAGEMENT.md).
Lost credentials cannot be read back: rotate and update the ignored configuration.
Rebuild/reflash privately after rotation or assignment changes. No device-side
registration or automatic vehicle choice exists.

Disable rejects ingestion without deleting keys/history. Re-enable can restore a
valid key on the backend, but this conservative firmware keeps a previously rejected
token locked: **rotate/provision a new token** and reflash to resume. Revocation and
reassignment revoke old keys; enable alone never un-revokes them. Ingestion rechecks
registration and credential under locks, preserving administrative race protection.

The NVS rejection lock stores SHA-256 of the complete token, not the token itself.
It compares at boot and clears only when the locally provisioned token changes.
Storage failure halts reports; physical persistence still needs testing. The device
must possess its plaintext token to authenticate: the ignored source and resulting
flash image are sensitive. Production flash/credential protection is pending.

Jeepney deactivation hides passenger service but, by existing policy, does not stop
authorized ingestion. Disable the device to stop ingestion. Passenger history ages
under existing stale rules; disable/revoke does not rewrite already accepted driver
reports. Admin monitoring additionally checks current ownership/credential state.
This distinction is preserved, not changed by firmware. ETA stays unavailable;
passenger route filtering and manual availability semantics remain untouched.
