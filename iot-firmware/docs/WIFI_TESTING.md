# Wi-Fi bench testing with the existing API

This is a future physical test procedure. No device was flashed, no real position
was acquired and no ESP32-to-API communication was observed in Phase 7A.
Complete [hardware identification](HARDWARE_TEST_CHECKLIST.md) first.

## Prepare the laptop API without changing application code

The path is `ESP32 -> local Wi-Fi/LAN -> existing Express API -> PostgreSQL`.
Both devices need reachable addresses on the same approved bench network. On classic
ESP32, use compatible 2.4 GHz Wi-Fi. Guest/client isolation, VPN routing or a hotspot
that isolates clients can prevent access even when both show connected.

Find the laptop's actual adapter IPv4 address in PowerShell using `Get-NetIPConfiguration`
or `ipconfig`. Use its private LAN address in `apiOrigin`, including port 3000; do not
copy an example IP blindly. The origin has no path/trailing slash. `127.0.0.1` on ESP32
is the ESP32; `10.0.2.2` is an Android emulator convention, not the laptop's phone/ESP32
address. USB `adb reverse` is for the Android app and does not route ESP32 traffic.

The existing backend defaults to `HOST=127.0.0.1`, which is not reachable over LAN.
For this isolated development session, stop that instance and launch the same API
bound to the **actual LAN address** (preferred over all interfaces):

```powershell
cd C:\Users\Administrator\Projects\jeeplink\backend
$env:HOST = 'REPLACE_WITH_LAPTOP_PRIVATE_IPV4'
$env:PORT = '3000'
$env:NODE_ENV = 'development'
$env:ENABLE_GPS_SIMULATOR = 'false'
npm start
```

Process environment overrides the existing `.env` values without editing or printing
them. The existing database configuration/migrations must already be valid. Do not
rerun migrations/seeds to make records appear fresh. `HOST=0.0.0.0` can listen on all
interfaces but is broader exposure; use a specific interface where possible.
The simulator requires loopback by design and must be off for this LAN session.

Verify `http://<actual-laptop-LAN-IP>:3000/health` from a permitted LAN client; a healthy
response verifies database reachability, not physical GPS. Keep Admin web on its
existing local setup with its proxy pointed at the actual API if needed; do not
weaken CORS/cookie security. [Admin setup](../../docs/ADMIN_WEB.md) documents its
proxy configuration. Do not change passenger release cleartext permissions.

## Windows Firewall — narrow temporary rule

Do not disable the firewall. On a trusted **Private** bench-network profile, an
administrator can allow only TCP 3000, the specific laptop interface and the ESP32's
actual DHCP/reserved IP. Replace both placeholders before executing:

```powershell
New-NetFirewallRule -DisplayName 'AbangQue ESP32 bench TCP 3000' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3000 -LocalAddress LAPTOP_LAN_IPV4 -RemoteAddress ESP32_LAN_IPV4 -Profile Private
```

This task does not create the rule or change a network profile. Do not use Public/Any
profiles or internet port forwarding as a workaround. If DHCP changes addresses,
update the rule deliberately; a router reservation may simplify a supervised bench.
Review any managed-network restrictions with its administrator.

## Provision and run

1. In the existing Admin Device Management module, register the **actual** device,
   assign its correct jeepney and enable it. Provision/rotate and securely transfer
   the one-time token + returned jeepney ID into `.local/local_config.h`. No new
   registration API or simulator credential is used.
2. Set SSID/password, the actual origin and identified GNSS/switch pins/baud. Plain
   HTTP requires `allowDevelopmentHttp=true`, isolated development and nonproduction
   device credentials. A LAN is not encryption: keep this supervised and temporary.
3. For HTTPS, use the real server hostname, correct trust-root PEM and synchronized
   time. Build `esp32dev_https` to enforce HTTPS. Never bypass certificate verification
   to fix clock, CA, DNS or hostname errors.
4. Build, explicitly select the device COM port, flash and open 115200 Serial as
   described in the [README](../README.md). No module connected means no report.
5. Verify FULL/AVAILABLE/UNKNOWN behavior locally before relying on network outcomes.
   Give the real receiver a suitable sky view. Confirm UTC and real RMC; do not paste
   test fixture bytes into the physical reporter.
6. Once a real fresh fix and manual state exist, expect a report no more frequently
   than the configured interval. An accepted report must retain measured UTC and
   separate server receipt time. Check Admin Live Monitoring and passenger API through
   their existing routes. One accepted row proves only that submission was accepted.

## Failure tests and interpretation

| Condition | Expected firmware / server behavior |
| --- | --- |
| Wrong SSID or access point off | 15 s association timeout, bounded reconnect; GPIO continues working |
| Wi-Fi connected, API stopped/firewall blocked | Reporting error or unconfirmed timeout; no simulator fallback |
| SNTP unreachable or invalid time | Clock unavailable; no report, including plain HTTP development |
| GNSS absent, no sky view, invalid fix or stale UART | GPS unavailable; no fabricated coordinates/status-only POST |
| Open/conflicting latched contacts | UNKNOWN; no report; not a default AVAILABLE |
| Internet loss while switching | Retain current manual selection locally; no old-report queue |
| Restore network with only an old fix | Still no report; wait for a new valid measurement |
| Device disabled or credential revoked | 401; persistent lock; rotate/reprovision and reflash to resume |
| Provisioned ID mismatch | 403; investigate administrative binding, do not try random IDs |
| Duplicate time | 409; no receipt refresh or success blink |
| Wrong CA/hostname/expired certificate | TLS rejection, no cleartext fallback |
| Response 400 | Halt; inspect config, date/time and exact API contract |
| Response 429/5xx | Backoff, respect numeric Retry-After, use new measurements |

Do not deliberately post fake positions to test these conditions. Use native/mock
contract tests for synthetic cases; physical tests use actual receiver measurements.
Changing device disable/revocation is an admin operation with real consequences:
use an owner-designated bench device and its authorized assignment.

## Cleanup

Stop the LAN backend after the supervised test, remove the named temporary firewall
rule, clear the process overrides and return to the established loopback workflow:

```powershell
Remove-NetFirewallRule -DisplayName 'AbangQue ESP32 bench TCP 3000'
Remove-Item Env:HOST,Env:PORT,Env:NODE_ENV,Env:ENABLE_GPS_SIMULATOR -ErrorAction SilentlyContinue
npm start
```

Rotate/revoke temporary test credentials as appropriate. Keep logs secret-free and
record the observed results, exact hardware revisions and unresolved failures in the
checklist. Do not commit the local config, compiled firmware with secrets or database
exports. No deployment or permanent firewall opening is part of this phase.
