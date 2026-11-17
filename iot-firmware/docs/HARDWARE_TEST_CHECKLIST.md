# Hardware acceptance checklist — all physical items pending

Phase 7A creates code and preparation documents. It does not establish any checked
physical item below. Fill in actual observations during a supervised bench session;
do not mark a passed compiler/mock test as a successful physical connection.

## Record the setup (no secrets)

| Evidence | Actual value / observation |
| --- | --- |
| Test date, tester and firmware commit | Pending |
| ESP32 board/module, revision, flash and USB-UART model | Pending |
| PlatformIO environment / actual COM port | Pending |
| GNSS module + carrier revision, firmware, antenna | Pending |
| Confirmed RMC baud/format and data rate | Pending |
| GPIO mapping + board schematic references | Pending |
| Driver control type / contact diagram | Pending |
| Measured supply / UART logic voltages | Pending |
| Bench supply rating and observed current/transients | Pending |
| Admin registration ID and assigned jeepney ID (no token) | Pending |
| API environment and transport (private details kept locally) | Pending |
| Approved wiring review and unresolved issues | Pending |

Keep sensitive host/network details, tokens and raw private traces in ignored local
notes. Do not paste secrets into this checklist. A registration is not hardware proof.

## Stage A / B — software verification

- [ ] Re-run the exact pinned build/test commands in [README](../README.md) on the
  firmware revision to be flashed; record pass/fail, versions and limits.
- [ ] Confirm only test folders contain synthetic positions; normal firmware has no
  hardcoded location/fallback and unconfigured pins remain disabled.
- [ ] Check ignored config/build outputs and ensure the private token is absent from
  Git and logs. Compile success alone does not prove protection against flash extraction.
- [ ] Confirm API contract tests use an in-memory repository, not operational telemetry.

The implementation session's observed software results are in README; these boxes
are a repeatable acceptance record for the later hardware session, not missing claims
that hardware-independent checks prove electronics.

## Stage C1 — identification and safe USB power

- [ ] Confirm every model/revision/supply/interface from its actual documentation;
  resolve every pending pin. Do not use a picture of a similar-looking carrier.
- [ ] Verify power disconnected during wiring, polarity, common ground and no UART
  overvoltage/back-power path. Verify safe USB/external-supply coexistence.
- [ ] Use a suitable regulated bench supply. No jeepney battery or modem GPIO power.
- [ ] Compile for the exact board and select the exact COM port; upload and record
  actual success. Check boot/reboot and secret-free Serial at 115200.
- [ ] Verify optional LED GPIO/current/polarity; interpret Serial if LED is absent.

## Stage C2 — manual control

- [ ] Boot with disconnected contacts: UNKNOWN and no report.
- [ ] In latched mode, verify the labels against continuity; each side establishes
  only its own state after debounce. Both open/both shorted are UNKNOWN.
- [ ] Move/bounce rapidly: no request bursts or repeated stable-selection events.
- [ ] Power-cycle on each latched position: state is acquired physically, never a
  software default AVAILABLE. Test a broken contact/ground path.
- [ ] If momentary mode is selected, verify RAM retention after release/offline,
  simultaneous-press ambiguity and required explicit selection after reboot.
- [ ] During a slow/failed HTTP request, verify switch sampling remains responsive.

## Stage C3 — real GNSS

- [ ] Confirm compatible UART voltage, RX routing, baud and real RMC output. No
  synthetic UART injection is used as physical GPS evidence.
- [ ] With sky view, record actual acquisition time and compare coordinates/date/time
  with an independent reference; describe accuracy limits instead of claiming perfection.
- [ ] Remove GNSS/power/sky view: no new reports after validity/freshness expires.
- [ ] Verify invalid fixes, stale serial backlog and repeated timestamps cannot refresh
  the backend. Restore the receiver and confirm a new measured fix recovers reporting.
- [ ] Confirm GNSS UTC and SNTP agree within the firmware gate; investigate wrong
  receiver date or system time instead of retimestamping a cached location.

## Stage C4 — authenticated Wi-Fi / API

- [ ] Confirm LAN IP, explicit backend binding, simulator disabled and a temporary
  firewall rule limited to the bench ESP32; do not disable the firewall.
- [ ] Provision the real device through Admin; copy only its own token/assigned ID.
- [ ] With valid real GPS and manual selection, observe a valid 201 on the ESP32 and
  corresponding database/admin record. Compare measured time with received time.
- [ ] Check existing passenger filtering/source/manual-state and unavailable ETA.
  Confirm no numerical seats, fake route, fake movement or driver account appears.
- [ ] Stop the API and separately interrupt Wi-Fi: distinguish transport errors from
  missing GPS, confirm backoff and no old-report queue. Reconnect with fresh data.
- [ ] Test SNTP blocked/clock unavailable: no report; restore synchronization safely.
- [ ] With an authorized bench device, test disable/revoke/rotate/reassignment. 401/403
  must halt, including after power cycle with the same token. Re-enable alone does not
  clear the firmware lock; a new provisioned token does. Verify NVS write/read failures
  remain fail-closed without exposing credentials.
- [ ] Test HTTPS against an approved actual endpoint: valid CA/hostname works; wrong
  CA/hostname/expired certificate is rejected. No certificate bypass or downgrade.
- [ ] Verify real response streaming, body limit, duplicate 409 handling and timeout
  behavior. Use mock tests for artificial responses; do not pollute operational GPS.
- [ ] Let reports age beyond the backend's configured threshold and verify UNKNOWN /
  STALE; network connection alone must not keep driver availability current.
- [ ] Remove temporary firewall rule and return backend binding to the established
  local workflow. Secure/revoke test credentials and record issues before field use.

## Stage D / vehicle integration — separate future acceptance

- [ ] Confirm modem full variant/carrier revision, bands, logic levels, UART flow
  control, SIM/provider/APN, antennas and verified power design.
- [ ] Implement and test its concrete transport without altering the existing API.
- [ ] Demonstrate registration + authenticated HTTPS, reconnection and credential
  rejection on real cellular hardware; record actual data use and supply bursts.
- [ ] Survey real Marinduque operating coverage without inventing route records.
- [ ] Obtain reviewed automotive regulator/protection/fuse/harness/mounting design
  for the actual vehicle, then perform supervised installation/field acceptance.

No unchecked item is implied complete by this document. Recommended next work is
C1–C4 on USB-powered bench hardware, before any modem purchase decision or vehicle wiring.
