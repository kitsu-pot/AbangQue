# Proposed hardware BOM — nothing purchased or confirmed

Start with a USB-powered ESP32, separate GNSS receiver and manual switch. Add cellular
only after Wi-Fi bench acceptance. Every item/model below is **proposed**; obtain the
exact board revision, module suffix, schematic and manufacturer datasheet before
buying or wiring. Cost categories are relative budget-planning categories, **not
current Philippine prices or quotations**. Compare total delivered cost, antennas,
cables and regulator/level-shifter needs, not just the bare-module listing.

| Proposed component | Purpose and interface | Required electrical/compatibility checks | Alternatives and limits | Relative cost |
| --- | --- | --- | --- | --- |
| Classic ESP32 development board with USB-UART, accessible headers and documented regulator | Runs firmware; USB upload/Serial; separate UART for GNSS; Wi-Fi first | 3.3 V GPIO; confirm board's actual USB/5 V/3.3 V supply inputs, flash, PSRAM, boot pins and regulator capacity. The compile target is `esp32dev`, not an exact board selection | Documented ESP32-DevKitC/WROOM-based carrier is a comparison baseline. C3/S3 or WROVER boards require target/UART/pin review; not drop-in equivalents | Low |
| Separate UART GNSS breakout, proposed u-blox MAX-M10S carrier or documented M8-family alternative | Real GNSS measurements, NMEA RMC with UTC date/time and fix status | Confirm **carrier** input supply and UART voltage separately; require 3.3 V-compatible signals or correct translator; antenna and cold-start current supported | M10 offers current multi-GNSS options; a genuine documented M8 carrier may reduce cost. Avoid undocumented/cloned modules where firmware/voltage identity cannot be verified. Neither receiver is confirmed | Low–medium; antenna/carrier affects cost |
| Matched GNSS antenna | Satellite reception; RF connector to receiver | Confirm active/passive antenna, bias supply/current, connector, impedance and mounting requirements from receiver/carrier datasheet | Integrated patch may be cheaper; external antenna may help sky view. Roof/mounting placement needs environmental and cable review | Low–medium |
| Latched SPDT two-position switch with three verified terminals | Manual FULL/AVAILABLE; common ground plus two GPIO contacts | Unpowered dry contacts; compatible with low-voltage logic; verify continuity and throw labels. Pull-ups to 3.3 V only | Two independent momentary buttons supported; need explicit selection after reboot. A one-input open/closed switch cannot distinguish a broken wire from one selection | Very low |
| Optional status LED and resistor | Local state indication from configurable GPIO | Check LED forward voltage/current and GPIO capability; choose resistance for modest current, not maximum rating. Confirm polarity | Serial-only operation saves cost; no built-in board LED is assumed | Very low |
| Data-capable USB cable and regulated bench supply | Safe first-stage programming/power | Board input rating, connector polarity, supply quality and cable drop; avoid ambiguous simultaneous power paths | Laptop USB may suffice for ESP32/GNSS only after current review. It is not a guaranteed modem supply | Low |
| Separate LTE breakout, proposed Quectel EG915U variant or SIMCom SIM7600-family carrier for comparison | Future UART data transport; SIM/antenna support | Confirm regional band suffix, actual carrier input supply, 1.8 V versus 3.3 V UART translation, peak-current delivery, PWRKEY/reset circuit, TLS/PPP support and documentation | Cat 1/Cat 1 bis can suit small periodic reports. Cat 4 can cost/use more power than needed. Do not substitute a 2G-only modem or assume LTE-M/NB-IoT access | Medium–high; likely largest electronics cost |
| LTE antenna(s), SIM holder/SIM and data plan | Carrier access | Correct LTE bands, connector, matching/ground-plane needs and any diversity port; data-enabled registered SIM with approved use and verified APN | Bundled antennas can reduce cost if genuine and matched. Carrier, plan and APN remain unselected; ongoing cost separate | Low–medium accessories; recurring data cost |
| Dedicated modem supply/regulator and local decoupling | Meet modem voltage and transmission bursts | Design to exact module/carrier datasheet, transient peak current, low wiring resistance, ripple and thermal requirements | A board with documented regulator/level translation can lower total integration cost. Never power from an ESP32 GPIO or assume the board's 3.3 V regulator is enough | Low–medium; must not be omitted |
| Signal level translator, if needed | Safe UART between differing I/O domains | Direction/speed, voltage range, power sequencing and unpowered isolation; confirm whether carrier already provides translation | Prefer a documented carrier with compatible logic for student wiring. A resistor divider alone is not a universal bidirectional UART solution | Low |
| Short bench wires, headers, prototype board, connectors | Bench signal wiring | Common ground, polarity, strain relief, wire current rating and contact reliability | Breadboard is for supervised bench testing; vibration/current-carrying vehicle wiring requires secured connectors and a suitable assembly | Low |
| Protected automotive DC-DC supply, fuse/holder and harness (future) | Vehicle battery to regulated electronics rails | Verify actual vehicle voltage/transients, reverse polarity, overvoltage/load-dump protection, fuse/wire sizing and thermal rating with a competent installer | A hobby buck module's voltage label does not prove automotive surge survival. No final regulator/fuse value selected; no backup battery currently planned | Medium; safety hardware is part of budget |
| Enclosure, standoffs, cable glands and mounting | Protect boards and secure installation | Heat dissipation, ingress/dust exposure, vibration, antenna RF clearance, access to manual control and no obstruction of driving | Low-cost enclosure is fine if it meets actual conditions. Metallic cases can shield antennas; do not mount RF antennas blindly inside | Low–medium |

## Manufacturer evidence and what it does not establish

- [Espressif ESP32 datasheet](https://documentation.espressif.com/esp32_datasheet_en.html)
  documents 3.3 V-domain GPIO and pin restrictions. Treat external 5 V logic as
  incompatible unless an exact intervening circuit establishes otherwise. Its chip
  ratings do not specify an unknown development board's input connector.
- [MAX-M10S datasheet R08](https://content.u-blox.com/sites/default/files/MAX-M10S_DataSheet_UBX-20035208.pdf)
  lists module VCC 1.76–3.6 V, and separate V_IO choices including a 3.3 V domain.
  Check carrier wiring/VIO_SEL; a seller's “5 V GPS” description may refer only to
  the carrier regulator input. The module document calls for startup-current headroom
  up to 100 mA. Do not transfer these values to a different model.
- [Quectel EG915U hardware design](https://images.quectel.com/python/sites/2/2023/05/Quectel_EG915U_Series_Hardware_Design_V1.1.pdf)
  and [module specification](https://images.quectel.com/python/sites/2/2023/06/Quectel_EG915U_Series_LTE_Standard_Module_Specification_V1.3.pdf)
  show why carrier details matter: the module supply is 3.3–4.3 V (typical 3.8 V)
  and its UART is in a 1.8 V domain. The manufacturer
  [reference design](https://developer.quectel.com/wp-content/uploads/2024/09/Quectel_EG915U_Series_QuecOpen_Reference_Design_V1.0.pdf)
  calls for supply capability of at least 3 A for that design. This is **an example,
  not a universal power requirement or wiring plan** for an unselected modem.
- [SIMCom's SIM7600 comparison](https://www.simcom.com/product/SIM7600.html)
  lists variant-specific bands and module supply ranges. Regional suffixes and
  carrier circuitry must be checked individually; similarly named listings can differ.

References reviewed for preparation on 2026-11-17. Manufacturer documentation and
carrier requirements must be rechecked against the exact part revision before an
order. The project has no current-price quote, carrier survey or hardware ownership
evidence. Recommended spending order: verify ESP32 + GNSS + switch over Wi-Fi, then
select modem/power/antennas together using [cellular preparation](CELLULAR_PREPARATION.md).
