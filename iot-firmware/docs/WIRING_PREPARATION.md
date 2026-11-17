# Wiring and power preparation — not a final installation procedure

No exact hardware is confirmed. **Do not connect vehicle 12 V directly to ESP32,
GNSS, UART, GPIO or an unspecified modem input. Never power a cellular modem from
an ESP32 GPIO.** A nominal “12 V” vehicle supply is not a stable laboratory rail.
This guide defines verification gates and interface examples; actual pins, regulator,
protection components, wire sizes and fuse ratings remain pending.

## Identify before connecting

Record photographs/model/revision and obtain each manufacturer's schematic/datasheet:
ESP32 carrier/module, GNSS carrier/module, switch contact diagram, future modem
carrier/module, antennas and each regulator. A **bare module** and its **breakout
board** may accept different input voltages. Pin labels such as VCC/VIN/5V/VBAT cannot
be interpreted interchangeably. Check UART electrical levels separately from power.

| Item | Required verification |
| --- | --- |
| ESP32 | 3.3 V GPIO domain, approved carrier supply input, boot straps, flash/PSRAM pins, UART pins, pin availability and pull-up support |
| GNSS | Actual supply range, startup/steady current, 3.3 V/1.8 V/other UART domain, 8N1 baud, RMC output, antenna bias and ground |
| Switch/buttons | Dry contacts, common/throws by continuity, no existing powered vehicle wiring, readable FULL/AVAILABLE labels |
| Modem | Actual VBAT/carrier input range, peak-current/transient requirement, logic translation, PWRKEY/reset timing, ground and RF ports |
| Power/protection | Regulator input/transient rating, current at temperature, reverse polarity/overvoltage protection, fuse and wiring plan |

The [ESP32 datasheet](https://documentation.espressif.com/esp32_datasheet_en.html)
defines chip electrical limits and restricted GPIOs. The firmware's conservative
classic-ESP32 pin filter rejects UART0, boot-strapping/flash/possible PSRAM pins and
input-only pins for internal-pull-up controls. It still cannot know your carrier's
onboard circuitry. All configured pins start disabled (`-1`).

## Provisional standard-interface examples

These are **signal relationships, not numbered pinouts**. Apply only after confirming
the actual interfaces and voltage compatibility. Power off before changing wiring.

```text
Verified UART GNSS TX --[translator if needed]--> verified ESP32 UART RX GPIO
GNSS ground ------------------------------------ ESP32 logic ground
GNSS supply <--- separately verified regulated rail/carrier input

GNSS RX: leave as manufacturer specifies; firmware sends no configuration commands.
Never connect RS-232 voltage-level outputs directly to ESP32 TTL/CMOS UART.
```

The firmware uses configurable RX on UART2, with no configured TX. Arduino may retain
a board-default UART TX mapping internally; no wire should be connected to it and
the firmware transmits no GNSS bytes. Verify routing on the actual core/board. A
receiver configured for binary-only output will not produce a valid RMC fix.

```text
3.3 V pull-up -> FULL GPIO -------- SPDT throw labeled FULL
3.3 V pull-up -> AVAILABLE GPIO --- SPDT throw labeled AVAILABLE
ESP32 ground --------------------- SPDT common
```

The sketch enables internal pull-ups on approved capable pins. Use an unpowered
switch: **no 5 V or battery positive goes to it**. Exactly one closed contact selects
a state; both open/both closed are UNKNOWN. This design detects many disconnected
or contradictory conditions but is not a fault-tolerant safety circuit. Label after
checking continuity; mechanical lever direction need not match the nearest lug.

For momentary mode, use two normally-open dry-contact buttons, each connecting its
own pull-up input to ground. Selection is held in RAM during internet loss; after
reboot press FULL or AVAILABLE again. A maintained switch can establish position
after reboot; a released momentary button cannot. The firmware never restores a
historical AVAILABLE state from flash. Long/noisy runs may need board-specific
external pull-ups, RC filtering, shielding/ESD protection and renewed debounce tests;
no resistor/capacitor value is finalized for unknown wiring.

Optional LED: verified GPIO -> correctly sized current-limiting resistor -> LED ->
ground (or verified active-low arrangement). Confirm LED forward voltage, modest
current and GPIO drive rating. Do not connect a bare LED or assume built-in LED pins.

## Power and ground

Begin on an isolated regulated USB bench setup for ESP32/GNSS. Verify power polarity,
rail voltage and current demand before adding signals. Establish common logic ground
between UART devices unless a deliberately designed isolated interface is used.
Keep high modem currents out of thin signal-ground paths. Check for back-powering
through UART pins when one module is off, and follow required power sequencing.
Do not connect USB and external rails simultaneously unless the carrier documents
safe power-path isolation.

Cellular transmit bursts can demand amperes even if average usage is small. The
ESP32's GPIO and a typical development-board regulator cannot supply that load.
Provide the modem's own correctly rated rail and nearby manufacturer-recommended
bulk/high-frequency decoupling with short, low-resistance wiring. Confirm voltage
under worst transmission bursts, regulator temperature and brownout recovery with
appropriate equipment. A multimeter average alone cannot reveal brief rail collapse.
Use the **exact modem/carrier** specification; examples in the [BOM](HARDWARE_BOM.md)
are not interchangeable voltages or pinouts. Many bare modems also need 1.8 V UART
translation even when their supply is near 4 V.

## Vehicle stage (pending design review)

The project currently plans to use the jeepney electrical supply without a backup
battery, but actual vehicle voltage/ground system and operating conditions must be
measured and confirmed. Alternator noise, cranking dips, jump starts, reverse polarity
and load-dump transients require an automotive-suitable supply/protection design.
An ordinary adjustable hobby buck is not automatically suitable.

Prepare for review: source connection point, disconnect method, fuse near the source,
wire/connector current rating, strain relief, insulation, reverse-polarity/overvoltage
protection, regulator/transient rating, grounding, heat/ingress/vibration and antenna
cable routing. A competent vehicle-electrician review is needed before finalizing
the installation. Do not tap braking, steering, airbag or other vehicle safety wiring.
No final connection sequence, fuse value, TVS choice or regulator schematic is supplied
until the actual parts and vehicle conditions are verified.

Record the approved pin/voltage table in the [hardware checklist](HARDWARE_TEST_CHECKLIST.md)
before Stage C. Stage C should start with USB power, not a vehicle battery.
