# Cellular preparation — Stage D pending

The Wi-Fi foundation does not implement cellular attachment, AT commands, PPP, SIM
handling or modem power-key control. Exact modem/carrier/antenna/power design must be
identified after the Wi-Fi bench stage. Prefer a separate, documented modem carrier
over an expensive all-in-one ESP32/GNSS/LTE board unless a later cost comparison
justifies it. No carrier, APN, SIM plan or modem purchase is selected here.

## Choose a modem as a complete electrical/network combination

Compare documented LTE Cat 1/Cat 1 bis UART carriers first for small periodic reports;
Cat 4 is an alternative if cost, availability and support justify it. Proposed families
for comparison are [Quectel EG915U](https://www.quectel.com/product/lte-cat-1-bis-eg915u-series/)
and [SIMCom SIM7600](https://www.simcom.com/product/SIM7600.html). These names cover
regional variants: the full suffix and carrier revision are essential. Their example
supplies/logic levels are described in the [BOM](HARDWARE_BOM.md), not universal wiring.

Require documentation for UART baud/flow control, voltage translation, power-on/reset
timing, network registration, PDP/APN setup, DNS, TCP, TLS certificate/hostname
verification, firmware version and recovery. An inexpensive bare LGA module may need
more regulator/level-shifter/PCB work than a documented breakout, increasing total
cost. Existing onboard GNSS does not force abandoning the separate GPS architecture.
Do not buy a 2G-only module because its listing is cheap; do not assume LTE-M/NB-IoT
subscription or coverage merely because LTE phone service exists.

## Philippine bands and Marinduque coverage

The [GSMA Philippines spectrum report (2026)](https://www.gsma.com/connectivity-for-good/spectrum/wp-content/uploads/2026/02/GSMA_Accelerating-5G-and-5G-Advanced-in-Philippines.pdf)
describes multiple low/mid-band allocations and fragmented FDD/TDD assignments.
Frequency/band/duplex must all match; “4G worldwide” is not sufficient. Build a matrix
against the **actual carrier's current LTE deployment and exact modem variant**.
These are candidate comparisons, not a claim that each band is active on your route:

| Band to check with carrier | Nominal range / mode | Why check |
| --- | --- | --- |
| B28 | 700 MHz, FDD | Low-band option; some regional modem variants omit it |
| B5 / B8 | 850 / 900 MHz, FDD | Variant/carrier-dependent low-band compatibility |
| B3 / B1 | 1800 / 2100 MHz, FDD | Common regional mid-band comparison candidates |
| B7 | 2600 MHz, FDD | Not interchangeable with 2600 MHz TDD |
| B38 / B40 / B41 | 2600 / 2300 / 2500 MHz, TDD | Verify TDD support and local use; similar frequency labels can hide different bands |

Band-number/frequency mappings are defined in the industry
[GSMA spectrum reference](https://www.gsma.com/solutions-and-impact/connectivity-for-good/public-policy/mobile-policy-handbook/wp-content/uploads/2019/01/MPH7_ENG_web_spreads.pdf).
An older [Globe LTE deployment statement](https://www.globe.com.ph/about-us/newsroom/corporate/globe-partners-mmda-enhance-network-coverage-capacities)
documents 700/1800/2600 MHz use in its stated rollout, but **does not establish current
Marinduque coverage**. Never use an old national announcement as route acceptance.

No Marinduque LTE field survey was performed. Compare current carrier coverage
information and conduct permitted tests along the actual owner-approved operation,
including terminals, hills, shielded areas and different times. Record signal/quality,
registration, uplink success, latency, outages and recovery. A phone result is only a
preliminary survey; modem bands, antenna and mounting can perform differently. Do not
invent official routes, stops or a preferred carrier from anecdotes.

## SIM, APN, antennas and data cost

Use a carrier-activated, correctly registered/data-enabled SIM whose plan permits the
intended device use. Confirm SIM size, PIN policy, validity/renewal, balance, roaming,
network restrictions and device/certification requirements with the carrier. Obtain
the APN and any credentials from that provider for the actual subscription; there is
no default APN in firmware. Do not put SIM/APN secrets in Git. Outbound API reporting
does not require exposing a modem server or requesting inbound public-IP access.

Match LTE antenna bands, connector, cable loss, ground plane, mounting and diversity
requirements to the exact modem. Keep GNSS and cellular antenna/power noise coupling
under review. Do not transmit without the manufacturer's required RF load/antenna.
Never substitute a GNSS antenna for an LTE antenna based only on matching connectors.

At the provisional 30-second interval there are 120 scheduled opportunities/hour,
960 in eight hours or 2,880 in 24 hours **if all report gates are satisfied**. Measure
actual bytes per session: JSON, HTTP headers, TLS handshakes, DNS/time sync, carrier
overhead and retries all count. A planning formula is:

`monthly MB = measured bytes per reporting session × sessions per day × days / 1,000,000`

Add observed reconnect/retry usage and the carrier's billing granularity. No current
price/data allowance or unlimited-plan promise is supplied. Obtain quotes only after
band/coverage/power compatibility; compare prepaid expiry and refill overhead as well
as headline price. Keep default rates conservative until measured field evidence
supports a change. Retry storms waste data and increase per-IP API rate limiting.

## Power and UART gate

Modem supply and UART logic are different electrical domains. A carrier advertised
for USB/5 V may regulate to a module VBAT near 4 V and translate 1.8 V UART—or may do
neither. Require its schematic. Provide a separately sized regulated rail, measured
peak-current headroom, short ground/power paths and specified decoupling; never use
ESP32 GPIO as power or assume ESP32 regulator capacity. Verify boot/transmit bursts
with appropriate equipment. Do not assign ESP32/modem TX/RX/RTS/CTS/PWRKEY/reset pins
until the hardware and voltage translators are identified.

## Future driver contract and acceptance

Implement `NetworkTransport` from `lib/AbangQueCore/src/Reporter.h` after confirming
whether the modem should use a supported PPP/IP path or validated built-in socket/TLS
commands. Explain that concrete choice before changing network architecture. The
reporter, GPS timestamp, input state and API serializer remain reusable.

The adapter must:

1. Progress through power, SIM-ready, network registration, data context and actual
   internet reachability with finite timeouts; “registered” alone is not API success.
2. Keep UART data/parser access separate from the GNSS UART and protect GPIO sampling.
3. Implement correct CA/hostname validation, certificate-time checks and no HTTP
   downgrade/redirect. A modem's HTTPS command name alone does not prove verification.
4. Use bounded reconnect/backoff, current fresh fixes only, no historical-report queue,
   and identical 401/403 handling. Preserve original measurement timestamps.
5. Handle data-plan expiry, SIM removal/PIN failure, weak coverage, failed DNS/TLS,
   temporary registration loss, power droop and reboot. Reset/power-cycle only according
   to the identified hardware timing and a bounded policy.
6. Validate real authenticated HTTPS reporting, credential rotation/revocation,
   reconnection, power stability, data use and field coverage before claiming completion.

Stage D starts only after Stage C evidence and the exact model/suffix, supply circuit,
logic levels, SIM/provider/APN and antennas are recorded. No unverified module-specific
AT sequence or final vehicle installation procedure is part of Phase 7A.
