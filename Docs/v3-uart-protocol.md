# CubeMars AK V3 UART protocol - verified on hardware

Verified on 2026-07-30 with:

- Motor firmware: `FW 5.1`
- Hardware string: `CMESC_AK80_9_SW_V3.2`
- Serial adapter: FTDI FT232R, `/dev/cu.usbserial-XXXXXXXX`
- Baud: `921600`, 8-N-1

## Confirmed V2/V3 connection difference

V2 hardware accepts the standard VESC packet used by the old Mac client:

```text
02 01 00 00 00 03
```

The connected V3 hardware did not answer that request. It immediately answered
the CubeMars V3 packet below:

```text
AA 01 41 58 E5 BB
```

Decoded:

- `AA`: short-packet header
- `01`: payload length
- `41`: `COMM_FW_VERSION` (`65`)
- `58 E5`: CRC16-CCITT/XMODEM over payload `41`
- `BB`: tail

Example response:

```text
AA 3F
41 05 01 06
43 4D 45 53 43 5F 41 4B 38 30 5F 39 5F 53 57 5F 56 33 2E 32 00
41 4B 38 30 5F 39 5F 53 45 5F 56 33 2E 32 00
41 4B 38 30 5F 39 56 33 00
4F 00 27 00 11 51 34 30 33 39 35 30 00 00
6E 40 BB
```

The response payload starts with:

- command `0x41`
- firmware major `5`
- firmware minor `1`
- mode/type byte `0x06`
- zero-terminated hardware string `CMESC_AK80_9_SW_V3.2`

## Confirmed systematic command offset

For the commands shared with the legacy VESC protocol, V3 uses the legacy
command ID plus 65. Examples:

| Function | V1/V2 | V3 |
| --- | ---: | ---: |
| Firmware version | `0x00` | `0x41` |
| Get values | `0x04` | `0x45` |
| Set current | `0x06` | `0x47` |
| Set motor configuration | `0x0D` | `0x4E` |
| Get motor configuration | `0x0E` | `0x4F` |
| Detect R/L | `0x19` | `0x5A` |
| Detect encoder | `0x1B` | `0x5C` |
| Reboot | `0x1D` | `0x5E` |
| Alive | `0x1E` | `0x5F` |

Together with the deliberate change from the VESC `02/03...03` frame to the
`AA...BB` frame, this strongly indicates a versioned command namespace rather
than accidental renumbering. The vendor's motivation is not documented, so
claims about why it was introduced remain inference.

## Confirmed real-time request

Request:

```text
AA 01 45 18 61 BB
```

`0x45` is `COMM_GET_VALUES` (`69`). SW_V3.2 returns an 85-byte payload, while
SW_V3.4 returns an 81-byte payload. The common layout is:

1. command
2. MOS temperature: int16 / 10
3. motor temperature: int16 / 10
4. output motor current: int32 / 100
5. input/bus current: int32 / 100
6. Id current: int32 / 100
7. Iq current: int32 / 100
8. duty: int16 / 1000
9. ERPM: int32
10. input voltage: int16 / 10
11. reserved: 24 bytes
12. fault: uint8
13. outer-loop position: big-endian IEEE-754 float
14. controller/CAN ID: uint8
15. temperature reserved values: 6 bytes
16. Vd and Vq: int32 / 1000 each
17. current-control mode: int32
18. encoder angle: IEEE-754 float
19. optional outer-encoder angle: IEEE-754 float (present on SW_V3.2, omitted
    on the observed SW_V3.4)

The original Mac parser required 85 bytes and therefore discarded every valid
SW_V3.4 response even though its CRC and all common fields were valid. The
parser now accepts both 81- and 85-byte layouts.

## Implementation status

Implemented in the Swift client:

- automatic standard VESC -> V3 handshake fallback
- V3 packet encoder and incremental decoder
- V3 firmware parsing
- V3 real-time telemetry parsing
- V3 duty/current/RPM/position/handbrake command framing
- V3 motor/application configuration read and acknowledged write
- V3 R/L, flux and encoder identification framing
- V3 reboot and periodic Alive
- persistent Servo/MIT jump commands

Read-only hardware verification succeeded through the same Swift `Client`:

```text
V3 UART FW 5.1 HW CMESC_AK80_9_SW_V3.2
24.6 V, 0 ERPM, Iq 0.00 A, MOS 36.0 °C, controller ID 104
```

## Confirmed V3 configuration channel

The V3 configuration commands use shifted command IDs, while the serialized
configuration bodies still follow the supplied VESC XML metadata:

| Function | Command | Response |
| --- | ---: | --- |
| Set motor configuration | `0x4E` / 78 | one-byte `0x4E` ACK |
| Get motor configuration | `0x4F` / 79 | command + 477-byte body |
| Get default motor configuration | `0x50` / 80 | command + 477-byte body |
| Set application configuration | `0x51` / 81 | one-byte `0x51` ACK |
| Get application configuration | `0x52` / 82 | command + 389-byte body |
| Get default application configuration | `0x53` / 83 | command + 389-byte body |

The connected hardware returned:

- motor configuration signature `0x6FE6775A`
- application configuration signature `0x92A2DE2E`
- controller/CAN ID `104`

`mcconf_v3.xml` must be serialized in its `<SerOrder>` order rather than XML
definition/UI order. With that ordering it produces the exact 477-byte device
body and matching signature. Same-value writes for both configurations were
acknowledged by the motor and reread byte-for-byte unchanged.

## Confirmed V3 identification commands

The unpacked Windows V3 `Commands` implementation confirms:

| Function | Command | Request body | Response body |
| --- | ---: | --- | --- |
| R/L identification | `0x5A` / 90 | none | R: int32 / 1e6, L: int32 / 1e3 |
| Flux linkage identification | `0x5B` / 91 | current, min ERPM, low duty: int32 / 1e3; R: int32 / 1e6 | flux: int32 / 1e7 |
| Encoder identification | `0x5C` / 92 | current: int32 / 1e3, clamped to ±10 A | offset and ratio: int32 / 1e6; inverted: uint8 |

Before repairing the stored output limits, a direct `0x5A` probe returned:

```text
5a000ff733fffffb6f
R = 1.046323 ohm
L = -1.169 uH
```

After repairing the zero output limits, the same real motor returned:

```text
5a00012bf900003cf7
R = 0.076793 ohm
L = 15.607 uH
```

The post-repair result validates the command, response decoder and real
identification path. Invalid negative-inductance results are reported to the UI
and are never offered for write-back.

A real `0x5C` encoder test produced sustained identification sound, confirming
that the firmware entered the task, but no final response arrived in the
initial 75-second observation window. The Mac client now waits up to 180
seconds and sends Alive approximately once per second. A complete final
encoder response remains to be verified.

## Confirmed zero-limit failure mode

The connected motor stored all of these values as zero:

```text
l_current_max_scale
l_current_min_scale
l_min_erpm
l_max_erpm
l_min_duty
l_max_duty
l_watt_max
l_watt_min
```

This disabled Servo output and caused invalid powered-identification results.
It was not a config-decoder alignment error: the device signature exactly
matched the V3 XML, and an official Windows V3 capture contained the same
full configuration body with the same zero values.

After restoring only those fields to the same-signature XML defaults, a 1 A
current request produced 1.00 A Iq, and R/L detection produced a valid positive
result. Original 477-byte configuration backups, hashes and the byte-verified
repair procedure are documented in:

本项目的真机调试记录（含原始参数备份，属于设备专有研究数据，未随公开树发布）

## Confirmed persistent mode commands

The Windows V3 tool packs the following one-byte commands:

- enter new bootloader: `0x42` / 66
- jump to Servo/CMESC: `0x64` / 100
- jump to MIT: `0x65` / 101

References:

- CubeMars AK Series Module Product Manual V3.0, section 4.3.2:
  https://img.cubemars.com/products/cubemars-product-parameter/AK-Series-Module-Product-Manual-v3.0.0-Download.pdf
- CubeMars AK V3.2.0 official manual:
  https://www.cubemars.com/data/cms/202602/ak-series-prodcut-manual-v3-2-0-for-ak-3-0-robotic-actuator.pdf

The latest static command checks in this project used the official
the vendor's Windows tool, in addition to the earlier V3.1.3 artifact.

### Authoritative runtime capture: R-LINK/IAP `A1` application return

The ordinary V3 command `0x64` exists, but the “jump to application” action does
**not** use an `AA ... BB` frame. A complete recording of the serial traffic
established:

- “jump to bootloader” transmits `AA 01 42 68 86 BB`, receives the identical
  ACK, then leaves the port at 1200 7N1 with RTS+DTR asserted and closes it;
- the first “jump to application” activation opens at 921600 8N1 and transmits
  four raw packets `EC 96 0E 30..33 A1 07 checksum`, then leaves the same
  1200/7N1 line state and closes;
- the second activation transmits sequence `34..37` in another four-packet
  burst and closes;
- 155 ms later the tool automatically reopens; 258 ms after that it sends the
  normal outer V3 `0x41` query and receives the full V3.2 firmware response.

Raw packet format:

```text
EC 96 0E <uint8 sequence> A1 07 <sum(first six bytes) mod 256>
```

Examples from the successful run are `EC960E30A10768` and
`EC960E37A1076F`. The sequence is a process-local rolling byte: it continued
from `0x30` to `0x37` across the two activations and resets when the official
process restarts, so it is not persistent device state.

The generator's behaviour was independently confirmed, and
the four calls at return addresses `0x14002AE47`, `0x14002AE69`,
`0x14002AE8B`, and `0x14002AEAD`, all passing command byte `0xA1`.

The authoritative capture is
`captures/capture-20260731-181846-iap-a1-stack.jsonl`. Earlier conclusions
based on hooks that missed the 7-byte writes (including timeout-only and
`0x64 × 5` recovery theories) are superseded by this capture.

The matching macOS implementation was subsequently verified on the same
AK80-9 V3.2 hardware. It completed both A1 bursts and received a valid outer
V3 `0x41` response after reopening the FTDI port. No erase (`0x43`) or firmware
data (`0x44`) command was sent during this round-trip test.

## Configuration write verification

A V3 configuration ACK confirms reception of the SET command, but individual
fields must still be checked by an immediate GET. Verification compares each
parameter after applying its XML-defined wire encoding (`d16`, `d32`,
`d32auto`, integer, enum or bool). Comparing decoded floating-point values for
exact host-language equality produces false mismatches after normal wire
quantization. Byte-equivalent values are accepted; fields whose encoded bytes
remain different are reported as rejected or clamped by firmware.

## Firmware erase transport: negative results pending an official upload capture

Independent analysis of selects Commands-layer `0x66/0x2A` for
images larger than 250000 bytes and `0x67/0x2B` for images larger than 2800
bytes. This does not yet identify the final serial transport. On the same
AK80-9 V3.2 hardware, all of the following erase frames produced zero RX bytes:

```text
IAP, V3 outer, old +65 hypothesis: AA05430005FFF879A2BB
application, V3 outer, 0x66:       AA05660005FFF85241BB
application, V3 outer, 0xA7:       AA05A70005FFF8CBA8BB
IAP, V3 outer, 0x66:               AA05660005FFF85241BB
IAP, standard VESC frame, 0x66:    0205660005FFF8524103
```

Every run stopped before the first data chunk and was recovered to a valid
`CMESC_AK80_9_SW_V3.2` application with the captured A1 sequence. These
results supersede both the earlier `0x43/0x44` assumption and the unverified
claim that the `0x66/0x2A` pair can be sent directly in
application state. The missing evidence is an official Windows firmware-upload
capture covering erase ACK and the first data ACK; there may be an R-LINK
forwarding header or a packet-state transition not visible in the Commands
helper alone.
