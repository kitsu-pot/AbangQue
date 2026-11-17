# AbangQue ESP32 Firmware Foundation — Phase 7A

This is a **bench-preparation firmware foundation**, not completed physical IoT
integration. No purchased board, GNSS receiver, modem, pins, SIM, carrier or vehicle
power circuit is confirmed. Stage A is implemented; Stage B verification is recorded
below. Stage C (physical ESP32/GNSS/Wi-Fi) and Stage D (cellular) remain pending.
Checkpoint: `checkpoint/firmware-foundation-2026-11-17` at `4a98f23`.

## What it does

- Reads checksum-verified UART NMEA RMC positions with their original UTC time.
- Debounces a two-contact latched FULL/AVAILABLE switch or two momentary buttons.
- Connects to Wi-Fi, synchronizes UTC, and uses the existing authenticated device API.
- Sends only with a fresh actual fix and a known manual selection. Missing hardware
  produces no location report. There is no simulator, default location or status-only payload.
- Keeps sampling responsive in the Arduino loop while a separate network task handles
  bounded requests. Reconnects and retries transient failures with backoff.
- Stops on rejected credentials; a digest lock in NVS survives reboot until the token
  changes. There is no driver login, route assignment, seat counting or ETA calculation.
- Exposes a transport interface for a later, identified cellular modem driver.

## Framework and layout

PlatformIO + Arduino provides a familiar student workflow, reproducible dependencies,
UART/GPIO/Wi-Fi support, and host tests of the same reporting logic. The underlying
Espressif HTTP/TLS client avoids an additional network library. ArduinoJson is the only
explicit runtime library. Core logic is portable C++; adapters remain ESP32-specific.

The representative target is PlatformIO `esp32dev` (classic ESP32, 4 MB flash), **not a
claim about the owner's actual board**. Platform `espressif32@6.13.0` pins Arduino
2.0.17 / ESP-IDF 4.4.7; this is a reproducible preparation baseline, not a declaration
that this older SDK is deployment-ready. Review current SDK/security updates before
public use and repeat all checks after a toolchain change. See the official
[board definition](https://docs.platformio.org/en/latest/boards/espressif32/esp32dev.html)
and [platform release notes](https://github.com/platformio/platform-espressif32/releases/tag/v6.13.0).

```text
iot-firmware/
  platformio.ini                 pinned ESP32 / HTTPS-policy / native-test targets
  include/local_config.example.h blank configuration template
  lib/AbangQueCore/src/           GPS, time validation, switch, API, retry, reporter
  src/                           Arduino entry point, Wi-Fi/TLS, SNTP, NVS lock, LED
  test/test_core/                 isolated synthetic fixtures; no physical transport
  tools/check_contract.mjs        native serializer -> mocked Express contract checks
  docs/                          hardware preparation and acceptance guides
  .local/                        ignored private config, Python tools, package cache
  .pio/                          ignored binaries/build dependencies
```

## Tools and exact commands (Windows PowerShell)

Use Python 3, Node.js 24, and internet access for the first dependency installation.
Run from the repository root. A project-local install avoids changing other projects:

```powershell
cd C:\Users\Administrator\Projects\jeeplink\iot-firmware
python -m venv .local/venv
& .local/venv/Scripts/python.exe -m pip install platformio==6.1.18
& .local/venv/Scripts/python.exe -m platformio run -e esp32dev -j 2
& .local/venv/Scripts/python.exe -m platformio run -e esp32dev_https -j 2
& .local/venv/Scripts/python.exe -m platformio test -e native
node tools/check_contract.mjs
```

Run these commands sequentially: PlatformIO build/test commands share `.pio`
metadata and may clean build folders after configuration changes.

The native target installs a pinned Windows MinGW compiler and Unity; it needs no
ESP32. The contract script requires the existing backend's `npm ci` dependencies.
Run it **after** native tests build `.pio/build/native/program.exe`. It instantiates
Express with a mock repository on an ephemeral local test socket; it never uses the
configured server, `.env`, PostgreSQL or a real credential. Do not run its fixtures
against an operational API. This Windows native target is not a Linux/macOS toolchain.

An existing PlatformIO CLI can run the equivalent `pio run -e esp32dev -j 2`,
`pio run -e esp32dev_https -j 2` and `pio test -e native` commands here.
Use two compile jobs on the owner's 8 GB laptop. Downloads/build caches are sizable;
do not commit them. No hardware is needed to compile the unconfigured foundation.

## Private configuration and provisioning

```powershell
New-Item -ItemType Directory -Force .local | Out-Null
Copy-Item include/local_config.example.h .local/local_config.h
```

Edit that ignored file locally in a private editor. Blank defaults intentionally
disable reporting. Supply Wi-Fi SSID/password, the actual API origin, Admin device ID,
Admin-provisioned jeepney ID and its one-time device token. Set pins only after
identification and electrical review. **Do not paste secrets into chat, logs, build
flags, screenshots or Git.** Never use passenger/admin session credentials.

For an isolated LAN test, explicitly set `allowDevelopmentHttp = true` and use the
laptop's private LAN IPv4 origin, with no trailing slash/path. `127.0.0.1` is the ESP32
itself. For HTTPS use the actual hostname and trusted root CA PEM. The
`esp32dev_https` environment rejects HTTP even if the local opt-in is true; certificate
and hostname verification remain enabled. No server is deployed by this phase.

Provision through **Admin IoT Devices → assigned, enabled device → Provision
credentials** (or **Rotate credentials**). Copy the token and returned jeepney ID
together. Reassignment revokes old credentials; provision again afterward. The
backend derives physical device identity and provenance from the credential, not
from an extra `deviceId` field. See [API integration](docs/DEVICE_API_INTEGRATION.md).

The local header and compiled firmware contain plaintext device/Wi-Fi secrets.
Git ignore prevents accidental normal staging, **not extraction from flash or a
shared binary**. Keep builds private; rotate exposed tokens. Production provisioning,
secure boot/flash encryption, protected storage and recovery require a separate
board-specific security plan. This phase does not burn irreversible eFuses.

## Flash and monitor — instructions only, hardware pending

First confirm the exact board, flash size, pinout and USB interface; create a suitable
PlatformIO environment if it differs. With verified compatible hardware and a safe
USB bench supply, enumerate and explicitly select its port:

```powershell
& .local/venv/Scripts/python.exe -m platformio device list
# Replace COM_PORT with the identified device, e.g. the actual COM number reported above.
& .local/venv/Scripts/python.exe -m platformio run -e esp32dev -t upload --upload-port COM_PORT -j 2
& .local/venv/Scripts/python.exe -m platformio device monitor --port COM_PORT --baud 115200
```

No upload is performed by a normal build/test. Follow the confirmed board's bootloader
instructions if auto-reset fails; do not guess button/pin sequences. Exit the monitor
before uploading. Logs show state reasons only, never tokens, passwords, raw requests
or precise coordinates. A missing config says **Configuration required**; configured
hardware without RMC says **GPS fix unavailable/stale** and sends no report.

## Guides and current limits

- [Hardware BOM](docs/HARDWARE_BOM.md): proposed affordable separate parts and alternatives.
- [Wiring preparation](docs/WIRING_PREPARATION.md): voltage, UART, switch and power boundaries.
- [Firmware architecture](docs/FIRMWARE_ARCHITECTURE.md): timing, state, retries and LEDs.
- [Device API integration](docs/DEVICE_API_INTEGRATION.md): exact inspected backend contract.
- [Wi-Fi testing](docs/WIFI_TESTING.md): LAN binding, narrowly scoped firewall and troubleshooting.
- [Cellular preparation](docs/CELLULAR_PREPARATION.md): modem/SIM/band/power selection gates.
- [Hardware test checklist](docs/HARDWARE_TEST_CHECKLIST.md): pending bench and field evidence.

SNTP must synchronize before reporting; no RTC/holdover beyond 24 hours is supplied.
RMC fix age must be at most five seconds (and at most one second ahead of SNTP).
Receiver quality/accuracy, antenna performance, electrical noise, TLS connectivity,
GPIO timing and NVS behavior still require physical tests. No offline report queue,
OTA updater, captive portal, modem AT driver, vehicle installation or production
credential provisioning is implemented. In-flight reports retain the selection and
measurement captured when dispatched; they cannot reflect a later switch change.

## Verification record

Observed in this implementation session (2026-11-17):

| Check | Result / scope |
| --- | --- |
| Native firmware core tests | 30 passed; synthetic fixtures with fake clock/transport |
| C++ serializer -> existing Express contract | 7 checks passed; in-memory repository only |
| Existing backend `npm run check` | Passed |
| Existing backend `npm test` | 57 passed, 9 PostgreSQL suites skipped; no database operations |
| Documentation local links and secret/build ignore rules | Passed |
| `esp32dev` firmware build | Passed; no upload |
| `esp32dev_https` firmware build | Passed; HTTPS-only configuration policy compiled, no upload |

The native Windows compiler is MinGW GCC 5.1.0, package `1.50100.0`; test assertions
explicitly enable 64-bit timestamp and double support. `tools/native_toolchain.py`
sets the compiler path only for the build and statically links compiler runtimes, so
the test executable/contract bridge does not depend on a global PATH change. Runtime
ArduinoJson is pinned to 7.4.2; the test-only Unity version resolved to 2.6.1.

Both representative builds used Xtensa GCC 8.4.0 and the pinned Arduino framework
`3.20017.241212+sha.dcc1105b`. Each reported 46,040 bytes static RAM (14.1% of 327,680)
and 931,713 bytes application flash (71.1% of the default 1,310,720-byte partition).
These are compile/link figures for the blank-config build, not measured runtime
heap, stack headroom, power consumption or physical performance. Serial/NVS/Wi-Fi/TLS
adapters compiled successfully; their real-device behavior remains unverified.

Early validation exposed host compiler-path/runtime-linking and JSON-view compatibility
issues, which were fixed before the passing runs. An overlapping PlatformIO job also
cleaned the first development-build directory; a subsequent sequential build passed.
Use the sequential commands above. The standard native command was verified again
with the normal project cache after setup; no global compiler PATH was changed.

No ESP32 upload, physical GPS fix, ESP32 Wi-Fi request or cellular attachment has
been performed. Backend/database contents, passenger Flutter and admin web code are
unchanged. The unrelated thesis edits remain outside this checkpoint's implementation.

Next stage: **Stage C, identification and USB-powered Wi-Fi bench acceptance**, using
the checklist. Cellular implementation follows only after that passes and exact modem
hardware, carrier access, power requirements and secure transport are confirmed.
