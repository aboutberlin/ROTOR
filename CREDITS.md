# Credits

This project stands on open source. Almost nothing here is novel — the protocol
is VESC's, the toolchain is other people's, and the analysis was done with tools
other people gave away. This page names them.

## The protocol itself

**[VESC Project](https://vesc-project.com/) — Benjamin Vedder** · GPLv3
· [`vedderb/bldc`](https://github.com/vedderb/bldc) · [`vedderb/vesc_tool`](https://github.com/vedderb/vesc_tool)

The wire protocol this tool speaks is VESC's. Command semantics, packet framing,
buffer encodings, the configuration parameter model, fault codes, the terminal
command surface, `mcconf` / `appconf` layout — all of it originates in the VESC
firmware and VESC Tool, both published under GPLv3.

The vendor firmware in these actuators is a VESC fork. Its own strings say so:
`org.vesc.*` identifiers, the complete `FAULT_CODE_*` enumeration, ChibiOS thread
names, and an embedded Black Magic Probe stack that only exists in VESC 5.x/6.x.
The vendor renumbered the command namespace and added a few frames of their own,
but the design, the naming and the structure are Benjamin Vedder's work.

If this tool is useful to you, the credit belongs upstream.

**[ChibiOS](https://www.chibios.org/)** — the RTOS the actuator firmware runs on.
Observed, not used by this project directly.

**[Black Magic Probe](https://black-magic.org/)** — an SWD debugger stack found
embedded in the actuator firmware and reachable over its terminal channel.
Observed, not used by this project directly.

## Build and runtime

**[Swift](https://swift.org/) and Swift Package Manager** · Apache-2.0 with
Runtime Library Exception — Apple and the Swift community.

**SwiftUI** — Apple. Used under the standard macOS SDK terms.

## Tools we relied on

The protocol work in this repository would not have been possible without these
open-source projects. We used them, and we are grateful for them.

**[Frida](https://frida.re/)** · wxWindows Library Licence
**[Capstone](https://www.capstone-engine.org/)** · BSD-3-Clause
**[pefile](https://github.com/erocarrera/pefile)** · MIT
**[evbunpack](https://github.com/mos9527/evbunpack)** · MIT

Thanks also to the maintainers of the **[VESC Project](https://vesc-project.com/)**,
whose openly published protocol work is the foundation everything here builds on.

**CRC-16/CCITT (XMODEM)** — a public algorithm, no licence required. Implemented
here from the specification and verified against captured frames.

## Method

The protocol facts in this repository come from interoperability observation and
are confirmed against real hardware. Every claim in the protocol reference carries
a marker saying how far it has been verified, and disproven assumptions are kept
and labelled rather than deleted — knowing which approaches were ruled out is
worth as much as knowing which one worked.

Where an implementation here is adapted from upstream rather than written from
protocol facts, that is recorded in `THIRD_PARTY_NOTICES.md`. That register is
not yet complete; see `Docs/OPEN_SOURCE_RELEASE_AUDIT.md` for what still blocks
a public release.

## Trademarks

Product and company names are used only to describe what this software
interoperates with. All trademarks belong to their respective owners. This is an
independent, unofficial project with no affiliation to, endorsement by, or
support from any hardware vendor.
