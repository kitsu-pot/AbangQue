# Firmware architecture and behavior

## Boundaries

```text
UART RMC -> NmeaGpsReader -> Fix with measurement/reception times --+
                                                                |
Two GPIO contacts -> DriverInput -> FULL / AVAILABLE / UNKNOWN ---+-> shared snapshot
                                                                      |
SNTP -> TimeSync -> trusted UTC -------------------------------> Reporter
                                                                      |
                                                   DeviceApi -> NetworkTransport
                                                                      |
                                                          WifiTransport -> existing API
                                                          future modem adapter (pending)
```

`lib/AbangQueCore/src` has no Arduino hardware dependency. `src` contains the ESP32
adapters. `Reporter` knows only a `Clock`, `NetworkTransport`, configuration and a
sensor snapshot. A future cellular class implements `tick`, `connected` and `post`,
preserving TLS validation, timeouts, headers and response semantics. No AT commands
or modem supply/power-key assumptions exist in the foundation.

The Arduino loop samples at roughly five milliseconds and yields. A separate 12 KB
FreeRTOS network task performs Wi-Fi/SNTP/HTTP operations. A short critical section
copies only the latest sensor snapshot; no strings or network operations occur in
the lock. Atomic state communicates report outcomes back to the indicators. Only one
HTTP request can be in flight. Actual scheduling latency remains a hardware check.

## Configuration and source safety

`include/local_config.example.h` is blank and tracked. The user's copy lives at
`.local/local_config.h` and is ignored. `DeviceConfig` separates provisioning,
network settings, reporting interval and provisional hardware settings. The default
binary has no SSID, token, API host, active pins, source coordinates or automatic status.
Malformed IDs/tokens/URL, absent CA for HTTPS, invalid intervals or colliding/unsafe
pins disable reporting. GPIO restrictions target classic ESP32 only and supplement,
not replace, the actual board schematic. Reserved flash, UART0, boot-strapping and
possible PSRAM pins are conservatively excluded; switch pull-ups require output-capable
GPIOs. All example pin numbers are `-1` (unconfigured).

Local HTTP requires an explicit opt-in and a canonical RFC1918 IPv4 host. HTTPS
requires a supplied CA PEM and hostname checks. Origin paths, queries, fragments,
userinfo and trailing slashes are rejected. The `esp32dev_https` build also rejects
HTTP regardless of config. IPv6 and non-IP HTTP hostnames are intentionally unsupported
by this preparation policy. The API path is appended internally and redirects are refused.

## GPS and time

`GpsReader` is the adapter boundary. `NmeaGpsReader` accepts checksum-verified RMC
sentences from GP/GN/GL/GA/GB/BD talkers, parses a single coherent latitude/longitude,
UTC date and time, and validates bounds, hemisphere, minutes and calendar dates.
It supports whole seconds and 1–3 fractional digits. The receiver must emit RMC at
a suitable rate; 1 Hz is a proposed bench setting, not a configured module assumption.
The UART is receive-only, 8N1, with configurable baud and RX pin. GGA-only receivers,
binary protocols and additional quality fields need a concrete adapter/configuration.

RMC status must be `A`; invalid/no-fix `V` immediately invalidates reporting. If a
position mode is supplied, only A/D/F/R is accepted: simulator S, manual M, estimated
E and no-fix N are rejected. Optional navigation status S/V is supported; V in that
**separate field** means no navigation safety information is supplied for u-blox M10,
not that RMC's position is invalid. This does not establish safety integrity. See
[u-blox M10 SPG 5.21 interface description, RMC](https://content.u-blox.com/sites/default/files/documents/u-blox-M10-SPG-5.21_InterfaceDescription_UBXDOC-304424225-20430.pdf).

A fix retains GNSS measurement time and local monotonic reception time separately.
Repeated timestamps cannot refresh reception. Older timestamps invalidate the sample;
only a later valid fix recovers it. Oversized/malformed relevant sentences are rejected.
UART backlog beyond the configured drain threshold is discarded, never replayed as
new data. Lost serial input expires naturally after five seconds. Unrelated sentences
do not refresh RMC validity. If a receiver emits a wildly future date, fail-closed
timestamp ordering may require correcting the receiver and restarting the tracker.

SNTP is started without blocking sensor sampling. A callback establishes synchronized
UTC; reboot starts unsynchronized. A sync is usable for at most 24 hours. Reporting
requires plausible UTC (2024–2099), measurement age <=5 seconds, reception age <=5
seconds, and GNSS time no more than one second ahead of UTC. No valid timestamp is
invented from boot uptime. A receiver without UTC date/time does not report through
this adapter. SNTP is not authenticated time; this is a bench baseline, not a secure
clock/anti-spoofing design. TLS validation still requires a correct system clock.

No satellite/HDOP/accuracy threshold, spoof detection or map matching is claimed.
RMC validity is a starting gate, not evidence of road accuracy. Verify real sky view,
antenna mounting and suitable quality criteria with the selected receiver. Coordinate
`0,0` is not globally forbidden: a genuinely valid fix there is a legal coordinate;
missing/no-fix startup data must have invalid status and cannot become a report.

## Driver control

Default design: a latched **two-contact SPDT** switch, common to ground, each throw
to a separate pull-up input. Exactly one low contact is FULL or AVAILABLE. Both
high (open/disconnected) or both low (contradictory) are UNKNOWN. This avoids treating
an open wire as AVAILABLE. Never wire a powered vehicle signal to these inputs.

Fifty milliseconds of stable input establishes selection. Latched-switch movement
immediately inhibits reporting until settled. Stable repeated samples do not emit
events. At reboot the state starts UNKNOWN, then follows a uniquely established
physical switch position; it is never initialized to AVAILABLE by software.

Optional two momentary buttons retain the last debounced manual choice in RAM even
with no network. Release alone does not change it. Simultaneous buttons invalidate
it; an unambiguous subsequent press restores it. Reboot loses that RAM choice and
requires another explicit press (or a deliberately held button). A one-button toggle
with no confirmed initial state is not implemented. No flash-restored historical
AVAILABLE value is treated as current driver input.

## Reporting, errors and recovery

Default interval is 30 seconds; config permits 10–300 seconds. Switch changes do not
bypass the interval/backoff, preventing request bursts. A report requires connection,
trusted UTC, fresh GPS and known selection. The interval begins at request completion.
`Reporter` remembers the last attempted GNSS timestamp so even an uncertain timeout
cannot produce an accidental replay. No queue stores old fixes or old switch states.

Wi-Fi association gets 15 seconds, then reconnect waits 2/4/8/16/32/60 seconds; successful
association resets backoff. HTTP socket operations use an eight-second timeout with
an elapsed 15-second budget checked between calls. DNS/TLS/header processing can
extend actual elapsed time; **this is not a hard total deadline**. The worker cannot
block the GPIO loop. Response body storage is limited to 2 KB. SDK diagnostics are
disabled and application logs never include request content or secrets.

Transient transport/408/429/5xx failures retry after interval-based exponential backoff,
up to five minutes (default sequence 30/60/120/240/300 s). Numeric Retry-After can
extend the delay to one hour. Each retry uses a new current fix/selection; none retimes
old data. A duplicate 409 waits the normal interval without claiming a newly accepted
report. Unexpected bodies, 3xx or permanent 4xx halt for investigation.

401/403 rejection also writes the current token's digest to NVS. A reboot with that
same token remains blocked. Updating to a newly provisioned token clears the lock;
it does not assign a vehicle or change server state. Failed NVS setup halts reporting;
failure to persist a rejection halts this boot and requires storage investigation.
An NVS/flash failure could prevent persistence across a power loss, so that failure
mode must be physically tested. Credentials in flash are not encrypted by this phase.

## Optional LED and Serial meaning

No board LED is assumed. Configure a verified GPIO and an external resistor/LED with
the correct polarity, or leave `statusLedPin=-1` and use Serial only. Pulse groups
repeat every five seconds, with 100 ms pulses spaced 400 ms apart:

| Indication | Meaning |
| --- | --- |
| Startup Serial message | Boot began; hardware validation still pending |
| 2 pulses | Wi-Fi connecting/disconnected |
| 3 pulses | Wi-Fi connected, UTC not synchronized |
| 4 pulses | GPS unavailable/stale |
| 5 pulses | Manual driver selection unknown |
| Steady on | Wi-Fi, UTC, current fix and selection ready; not an API-success claim |
| Brief fast blink (one second) | Valid 201 received for a report |
| 6 pulses | Transient reporting error/backoff |
| 7 pulses | Credential/assignment rejected, reprovisioning required |
| 8 pulses | Configuration/halted error (configuration errors may be Serial-only because unsafe pins are never initialized) |

Serial prints transitions in plain English. Higher-priority faults can hide lower
priority ones on a single LED; check Serial and the backend separately. No LED proves
continuous tracking, GPS accuracy, passenger accommodation or cellular operation.

## Verification boundaries

Native tests exercise the production core with fake clock/transport and isolated
NMEA fixtures. The contract check feeds the actual C++ serialization to the existing
Express app with an in-memory repository. Neither test touches real GPS, radios,
flash storage or PostgreSQL. The ESP32 compile verifies adapter build/link compatibility.
Bench tests must still prove NVS persistence, physical debounce, UART buffers, SNTP,
CA/hostname rejection, response streaming, timeouts, disconnections and reboot behavior.
