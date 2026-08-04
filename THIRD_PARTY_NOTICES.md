# Third-party notices and provenance register

This register deliberately distinguishes confirmed facts from unresolved provenance. A root license can license only material for which the project contributors have the necessary rights; it cannot relicense third-party material merely because that material is present in the same repository.

## License policy for this repository

- Original source code authored specifically for CubeMarsTool-Mac is offered under `GPL-3.0-or-later` unless an individual file states otherwise.
- Existing third-party copyright and license notices take precedence for their material.
- Items marked **unresolved / exclude** are not covered by the project's GPL grant and must be removed from a public source tree and binary release until their status is resolved.
- Protocol facts learned through interoperability testing are documented separately from copied implementation text or assets.

## Provenance register

| Component or reference | How it is used | Known source / license | Current release decision |
|---|---|---|---|
| VESC wire protocol concepts and terminology | UART framing, command semantics, buffer formats and configuration concepts | VESC Project / VESC Tool. Exact upstream version and the origin of each local implementation have not yet been mapped. Local documents describe the upstream as GPL, but this still needs source-by-source verification. | **Audit required.** Retain GPL compatibility; compare source files and record whether each implementation is independent or adapted. Preserve any upstream notices for adapted code. |
| CubeMars V1.32 and V3.1.3 Windows tools | Interoperability research and behavior comparison | CubeMars-distributed binaries; no redistribution permission has been established in this repository | **Do not distribute.** The executables currently reside outside the Git worktree and must remain outside releases. |
| CubeMars AK-series manual | Protocol and hardware reference | CubeMars manual; manufacturer copyright notice is present in the local PDF/text copy | **Unresolved / exclude.** Do not publish `tmp/pdfs/` or bundle the manual. Link to an official manufacturer download instead. |
| `reverse-engineering/extracted-config/**` | Extracted parameter definitions used to reconstruct configuration layouts | Extracted from tool binaries; contains full Qt-formatted descriptions and parameter metadata. The exact upstream copyright/license for each file is not established. | **Unresolved / exclude.** Do not publish until matched to a redistributable upstream source or replaced with an independently generated minimal schema. |
| `apps/CubeMarsKit/Sources/CubeMarsApp/mcconf.xml` | V2 motor configuration schema bundled into the App | Closely corresponds to extracted/VESC-style configuration XML; exact provenance still under audit | **Unresolved / exclude from public binary** until provenance is documented or the file is replaced. |
| `apps/CubeMarsKit/Sources/CubeMarsApp/mcconf_v3.xml` | V3 motor configuration schema bundled into the App | Derived during CubeMars V3 interoperability work; contains substantial VESC/Qt-style descriptive text | **Unresolved / exclude from public binary** until provenance is documented or the file is replaced. |
| `apps/CubeMarsKit/Sources/CubeMarsApp/appconf.xml` | Application/CAN configuration schema bundled into the App | Closely corresponds to extracted/VESC-style configuration XML; exact provenance still under audit | **Unresolved / exclude from public binary** until provenance is documented or the file is replaced. |
| `reverse-engineering/captures/*.bin` | Serial protocol observations | Captured from real sessions with official tools and hardware | **Private research data by default.** Publish only minimal, sanitized fixtures with documented provenance and no device-specific values. |
| `hardware-debug/*.bin` | Real-motor configuration backups | Generated from specific test motors | **Exclude.** Device-specific research backups are not part of the open-source distribution. |

## Required source-level audit

Before the first public release, review every Swift, Python and C source file and record one of these outcomes:

1. **Original implementation:** authored for this project from protocol facts or independent tests; retain a short design/test citation.
2. **Adapted implementation:** based on identified upstream source; add upstream copyright, exact repository/version, file path and license.
3. **Generated or extracted data:** document the generator and input license, or replace it with a clean minimal representation.
4. **Unresolved:** keep it out of the public branch and release artifacts.

At minimum, the audit must cover CRC, packet framing, buffer/float encoding, configuration parameter parsing/serialization, command numbers, the three bundled XML files, and all reverse-engineering helpers.

## Trademark and affiliation

CubeMars, VESC, AK-series model names and related marks belong to their respective owners. Their names are used only for compatibility description. CubeMarsTool-Mac is not affiliated with, endorsed by, or supported by CubeMars or the VESC Project.
