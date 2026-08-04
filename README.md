# Rotor — a native macOS tool for CubeMars AK-series actuators

**Configure, tune, control and flash CubeMars AK motors from a Mac.**
No Windows, no virtual machine, no vendor account.

Free, open source, independent. A native macOS implementation of the VESC serial
protocol, verified against **AK80-9, AK80-8 and AK60-6** hardware. Works with the
V1/V2 and V3 firmware branches, in both Servo and MIT modes.

If you own an AK-series actuator — AK80-9, AK80-8, AK80-64, AK70-10, AK60-6,
AK10-9 — and a Mac, this replaces the Windows-only vendor upper-computer software
for everyday work: reading and writing motor parameters, live telemetry, servo
control, FOC parameter detection, CAN status configuration and firmware upgrade.

> ### ⚠️ Bolt the motor down before you connect
>
> This software energises motors and makes them **rotate suddenly, under power,
> with no warning**. Before running it: **mount the motor rigidly to a bench**,
> **remove the load**, clear the rotation envelope, and keep a physical power cut
> within reach that you have already tested.
>
> **Using this software means accepting full responsibility for any damage or
> injury.** Read [DISCLAIMER.md](DISCLAIMER.md) first — it is not boilerplate.

---

## What this is

VESC-derived motor controllers speak a well-defined serial protocol. The vendor
tooling for these actuators is Windows-only, so this project implements that
protocol natively on macOS instead.

The protocol is not ours. It originates in the [VESC Project](https://vesc-project.com/)
(`vedderb/bldc` and `vesc_tool`, GPLv3) — command semantics, packet framing,
buffer encodings, the configuration model, fault codes and the terminal command
surface all come from there. The controller firmware in these actuators is a VESC
fork, and its own strings say so. See [CREDITS.md](CREDITS.md).

What this project adds is a clean, documented, open implementation for a platform
that had none.

## What works today

Verified against real hardware:

- **Connect and identify** — automatic protocol-branch detection, live telemetry
- **Configuration** — motor and application parameters, with byte-level read-back
  verification after every write
- **Servo control** — duty, current, RPM, position, handbrake
- **Parameter detection** — resistance, inductance, flux linkage, encoder
- **Firmware upgrade** — full image upload with bounded failure, parameter backup
  taken before erase, and version verified after reconnect
- **Terminal channel** — 50+ controller commands, including state and fault dumps
- **CAN telemetry** — including status groups that ship disabled, which is why
  temperature, input current, position and bus voltage never reach the bus by
  default

The protocol is documented in
[`Docs/PROTOCOL-REFERENCE.md`](Docs/PROTOCOL-REFERENCE.md).
Every claim there is marked as measured on hardware, derived but not yet
confirmed on the bus, or inferred — and superseded conclusions are kept and labelled rather than deleted,
because knowing which approaches were ruled out is worth as much as knowing which
one worked.

## Tested hardware

Every row below was read from a real motor through this tool, in one sitting, on
one adapter. Nothing here is inferred from a datasheet.

| Actuator | Firmware | Protocol | Parameters | Status |
| --- | --- | --- | ---: | --- |
| CubeMars AK80-9 | `CMESC_AK80_9` (V2) | VESC UART | 139 | Registered — full read/write |
| CubeMars AK80-9 | `CMESC_AK80_9_SW_V3.4` | V3 UART | 149 | Registered — full read/write |
| CubeMars AK80-8 | `CMESC_AK80_8` | VESC UART | 139 | Recognised — read-only |
| CubeMars AK60-6 | `CMESC_AK60_6_SW_V2.1` | VESC UART | 139 | Recognised — read-only |

**Read-only is deliberate, not a limitation of the protocol work.** A motor
becomes writable only once a device profile has been written for it, because the
parameter *layout* matching is not the same claim as the parameter *ranges* being
right for that model — pole count, gear ratio and current limits have to come
from a datasheet, not from a signature match. Connecting an unlisted actuator is
safe and shows you exactly what the tool could and could not determine about it.

Adding an actuator is a registry entry, not a code change. Pull requests welcome
if you have hardware to test against.

## Hardware notes

**Use an FTDI FT232RL USB-to-serial adapter.** The protocol runs at 921600 baud.
CH340-based adapters enumerate fine on macOS but cannot reliably produce that
rate — measured error was about 8%, outside UART tolerance, and the symptom is a
device that simply never answers.

**Never change the controller's baud rate to accommodate a bad adapter.** Fix the
host side instead. Writing a mismatched rate into the controller can leave it
unreachable from any host.

## Building

macOS 13+ and a Swift toolchain. Xcode is not required.

```sh
cd RotorKit
swift build                # library, CLI and app
swift run kitcheck         # offline test suite
swift run RotorApp -- --selftest    # headless end-to-end check
./make_app.sh              # package Rotor.app
./make_app.sh --lang en    # English-only build
```

`kitcheck` is the real test suite — Command Line Tools ships no XCTest, so the
checks are executable assertions. Protocol tests use golden vectors taken from
observed traffic rather than constructed expectations, and the device simulator
reproduces the controller's *refusal* behaviour, so an implementation that skips
a required handshake fails instead of quietly passing.

## Language

The interface is English by default, with translations loaded from
`Localization/<lang>.lproj/`. Switching is instant and needs no restart. Adding a
language is one file and no code, and a build can ship any chosen subset.

## Status

Working and used daily against real hardware; interfaces may still change.

The bundled parameter tables carry only the facts needed for interoperability —
name, type, serialisation order, range, enum labels. The vendor's help prose that
originally accompanied them is **not** included and is never parsed by this
software; roughly 440 KB of it was removed rather than redistributed. See
[`RELEASE_STATUS.md`](RELEASE_STATUS.md).

## License

`GPL-3.0-or-later` for original code in this project. The upstream protocol work
is GPLv3 and this stays compatible with it. See [LICENSE](LICENSE),
[NOTICE](NOTICE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Independence

Independent and unofficial. Not affiliated with, endorsed by, or supported by any
hardware vendor. Product names are used only to describe what this software
interoperates with; trademarks belong to their respective owners.
