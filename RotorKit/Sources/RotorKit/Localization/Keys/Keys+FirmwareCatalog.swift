import Foundation

extension L10n {
    public enum FirmwareCatalog {
        // MARK: 错误消息
        public static let downloadFailedTemplate = L10nKey(
            "firmware_catalog.download_failed",
            "Official file download failed: %@"
        )
        public static let archiveHashTemplate = L10nKey(
            "firmware_catalog.archive_hash",
            "Official archive verification failed: expected %@, actual %@"
        )
        public static let extractionFailedTemplate = L10nKey(
            "firmware_catalog.extraction_failed",
            "Firmware extraction failed: %@"
        )
        public static let imageSizeTemplate = L10nKey(
            "firmware_catalog.image_size",
            "Image length mismatch: expected %@ bytes, actual %@ bytes"
        )
        public static let imageHashTemplate = L10nKey(
            "firmware_catalog.image_hash",
            "Image SHA-256 mismatch: expected %@, actual %@"
        )
        public static let unknownImageTemplate = L10nKey(
            "firmware_catalog.unknown_image",
            "Not a registered official AK80-9 image (SHA-256 %@)"
        )
        public static let incompatibleTemplate = L10nKey(
            "firmware_catalog.incompatible",
            "Image incompatible with current motor: %@"
        )

        // MARK: 固件记录说明文字 (note 字段)
        public static let recordV3_4Note = L10nKey(
            "firmware_catalog.record_v3_4_note",
            "Verified with this tool on real hardware and cold-started. Link base 0x08060000 (Servo slot, "
                + "393,208 B = VESC APP_MAX_SIZE). Contains mc_interface_set_pid_mit; "
                + "MIT five-parameter impedance control already merged into this firmware, no need to jump to separate MIT app."
        )
        public static let recordV2_1ServoNote = L10nKey(
            "firmware_catalog.record_v2_1_servo_note",
            "V2.1 era Servo app, similarly in 0x08060000 slot. "
                + "Byte-for-byte identical to factory HEX in same region for 393,201/393,208 (difference only 8 bytes bookkeeping at slot tail). "
                + "Flashing downgrades V3 back to V2; use only when rollback is needed."
        )
        public static let recordV2_1MITNote = L10nKey(
            "firmware_catalog.record_v2_1_mit_note",
            "V2 era independent MIT app, link base 0x080C0000 (different partition from Servo slot, "
                + "loaded via BOOT chain). V3 already merged MIT control into Servo firmware; this path is historical archive. "
                + "Cross-mode flashing not verified in closed-loop on this hardware, hence not enabled."
        )
        public static let recordV2_1FullNote = L10nKey(
            "firmware_catalog.record_v2_1_full_note",
            "Complete 1 MB chip image (BOOT 0x08000000 / Servo 0x08060000 / MIT 0x080C0000). "
                + "UART upgrade interface only accepts raw .bin, not Intel HEX, hence cannot flash. "
                + "But it is the factory recovery source for SWD/ST-Link debrick; must be retained."
        )

        // MARK: 其他错误和验证相关消息
        public static let qtResourceExtractionFailed = L10nKey(
            "firmware_catalog.qt_resource_extraction_failed",
            "Qt resource offset exceeds official exe length"
        )
        public static let protocolMismatchTemplate = L10nKey(
            "firmware_catalog.protocol_mismatch",
            "Current is %@, image is %@"
        )
        public static let hardwareNameNotAK80 = L10nKey(
            "firmware_catalog.hardware_name_not_ak80",
            "Hardware name is not AK80-9: %@"
        )
        public static let v3ImageOnlyForV3Hardware = L10nKey(
            "firmware_catalog.v3_image_only_for_v3_hardware",
            "V3 images can only be flashed to V3 hardware branch"
        )
        public static let v2ImageCannotFlashToV3 = L10nKey(
            "firmware_catalog.v2_image_cannot_flash_to_v3",
            "V2 images cannot be flashed to V3 hardware branch"
        )
        public static let mustConnectServoBootloader = L10nKey(
            "firmware_catalog.must_connect_servo_bootloader",
            "Please connect Servo/IAP firmware first; current is %@"
        )
        public static let unzipCannotReadEntry = L10nKey(
            "firmware_catalog.unzip_cannot_read_entry",
            "unzip cannot read %@"
        )
        public static let notLegalCortexMTemplate = L10nKey(
            "firmware_catalog.not_legal_cortex_m",
            "Not a legal Cortex-M application image (%@). "
                + "Servo slot images must satisfy: initial SP in SRAM(0x2000_0000+), "
                + "reset vector in Flash(0x0800_0000+) with Thumb bit set."
        )
        public static let customImageDescription = L10nKey(
            "firmware_catalog.custom_image_description",
            "Self-compiled / modified image (not officially verified)"
        )
        public static let customImageVersion = L10nKey(
            "firmware_catalog.custom_image_version",
            "Self-compiled"
        )
        public static let customImageNote = L10nKey(
            "firmware_catalog.custom_image_note",
            "Self-compiled image, not in official whitelist; only structural vector table validation"
        )

        public static let v21FullImageTitle = L10nKey("firmware_catalog.v21_full_image_title", "AK80-9 V2.1 full image")
        public static let sourceCache = L10nKey("firmware_catalog.source_cache", "Official cache (both SHA-256 verified)")
        public static let sourceDownload = L10nKey("firmware_catalog.source_download", "Rotor official download (archive and image both verified)")
        public static let sourceLocal = L10nKey("firmware_catalog.source_local", "Local file (matches official image SHA-256)")

        public static let all: [L10nKey] = [
            v21FullImageTitle, sourceCache, sourceDownload, sourceLocal,
            downloadFailedTemplate, archiveHashTemplate, extractionFailedTemplate,
            imageSizeTemplate, imageHashTemplate, unknownImageTemplate, incompatibleTemplate,
            recordV3_4Note, recordV2_1ServoNote, recordV2_1MITNote, recordV2_1FullNote,
            qtResourceExtractionFailed,
            protocolMismatchTemplate, hardwareNameNotAK80,
            v3ImageOnlyForV3Hardware, v2ImageCannotFlashToV3, mustConnectServoBootloader,
            unzipCannotReadEntry, notLegalCortexMTemplate,
            customImageDescription, customImageVersion, customImageNote,
        ]
    }
}
