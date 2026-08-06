import Foundation

extension L10n {
    public enum Firmware {
        public static let recoverToApp = L10nKey("firmware.recover_to_app", "Recover to application")
        public static let recoverToAppHelp = L10nKey(
            "firmware.recover_to_app_help",
            "Sends the official two-round A1 IAP→Servo jump. Does not erase and does not write firmware.")
        public static let recoverToAppHint = L10nKey(
            "firmware.recover_to_app_hint",
            "If the motor spins but never answers: cut the motor's MAIN power for 10 s (a soft reset is not enough \u{2014} the bootloader flag lives in the RTC backup domain), unplug the USB adapter, then power up and reconnect.")
        // MARK: 步骤 1 - 连接
        public static let step1Title = L10nKey("firmware.step_1_title", "Connect Motor")
        public static let step1Hint = L10nKey(
            "firmware.step_1_hint",
            "Select port from top bar and connect; subsequent steps depend on reading firmware and protocol branch"
        )
        public static let notConnected = L10nKey("firmware.not_connected", "Not connected yet")

        // MARK: 步骤 2 - 选择镜像
        public static let step2Title = L10nKey("firmware.step_2_title", "Select Image")
        public static let step2Hint = L10nKey(
            "firmware.step_2_hint",
            "Official catalog, locally registered files, or self-compiled images"
        )
        public static let officialCatalog = L10nKey("firmware.official_catalog", "Official catalog")
        public static let verifyOK = L10nKey("firmware.verify_ok", "Verified")
        public static let select = L10nKey("firmware.select", "Select")
        public static let downloadAndVerify = L10nKey("firmware.download_and_verify", "Download and verify")
        public static let archiveOnly = L10nKey(
            "firmware.archive_only",
            "This entry is for archive only; cannot be flashed"
        )
        public static let localOfficialFile = L10nKey("firmware.local_official_file", "Local official file…")
        public static let localOfficialFileHelp = L10nKey(
            "firmware.local_official_file_help",
            "File must match the complete SHA-256 of an official image in the catalog above"
        )
        public static let customCompiledImage = L10nKey("firmware.custom_compiled_image", "Self-compiled image…")
        public static let selfCompiledCatalog = L10nKey("firmware.self_compiled_catalog", "Self-compiled")
        public static let selfCompiledNone = L10nKey("firmware.self_compiled_none", "Not selected")
        public static let selfCompiledEmpty = L10nKey(
            "firmware.self_compiled_empty",
            "No .bin in the folder yet — click \"Open folder\" and drop your images there")
        public static let revealSelfCompiled = L10nKey("firmware.reveal_self_compiled", "Open folder")
        public static let rescanSelfCompiled = L10nKey("firmware.rescan_self_compiled", "Rescan the folder")
        public static let customCompiledImageHelp = L10nKey(
            "firmware.custom_compiled_image_help",
            """
            For flashing firmware you compiled or modified yourself.
            Does not do SHA-256 whitelisting; instead does structural validation: the image must fit in the Servo slot
            (≤ 393,208 B), and the Cortex-M vector table at the start must be legal——
            initial SP in SRAM(0x2000_0000+), reset vector in Flash(0x0800_0000+) with Thumb bit set.
            This blocks "selected wrong file", but cannot block "firmware itself has bugs".
            """
        )
        public static let pendingImage = L10nKey("firmware.pending_image", "Image to flash")
        public static let customCompiled = L10nKey("firmware.custom_compiled", "Self-compiled")
        public static let customFirmwareAcknowledgment = L10nKey(
            "firmware.custom_firmware_acknowledgment",
            "I confirm the source and content of this image; I understand that flashing incorrectly may require SWD debrick"
        )

        // MARK: 步骤 3 - 备份参数
        public static let step3Title = L10nKey("firmware.step_3_title", "Back up parameters")
        public static let step3Hint = L10nKey(
            "firmware.step_3_hint",
            "Export firmware identity, mcconf and appconf; upgrade is allowed only after this step completes"
        )
        public static let exportFirmwareAndBackup = L10nKey(
            "firmware.export_firmware_and_backup",
            "Export firmware info and parameter backup"
        )
        public static let showInFinder = L10nKey("firmware.show_in_finder", "Show in Finder")
        public static let backupComplete = L10nKey("firmware.backup_complete", "Backed up")
        public static let backupNote = L10nKey(
            "firmware.backup_note",
            "UART/CAN has no command to read MCU Flash; cannot pull the firmware from the board as-is; "
                + "backup contents are firmware identity, mcconf, and appconf, not a flashable image."
        )

        // MARK: 步骤 4 - 升级
        public static let step4Title = L10nKey("firmware.step_4_title", "Confirm and upgrade")
        public static let step4Hint = L10nKey(
            "firmware.step_4_hint",
            "Do not power off or unplug during upgrade; failure stops immediately with no ACK and does not retry infinitely"
        )
        public static let powerOffWarning = L10nKey(
            "firmware.power_off_warning",
            "I confirm motor is unloaded/fixed and power is stable; I will not power off or unplug during upgrade"
        )
        public static let startUpgrade = L10nKey(
            "firmware.start_upgrade",
            "Begin upgrade and verify reconnection version"
        )

        // MARK: 状态与文件对话框
        public static let statusFailed = L10nKey("firmware.status_failed", "failed")
        public static let statusStopped = L10nKey("firmware.status_stopped", "stopped")
        public static let statusMismatch = L10nKey("firmware.status_mismatch", "mismatch")
        public static let statusPassed = L10nKey("firmware.status_passed", "passed")
        public static let statusComplete = L10nKey("firmware.status_complete", "complete")
        public static let selectCustomImageTitle = L10nKey(
            "firmware.select_custom_image_title",
            "Select self-compiled image (.bin)"
        )
        public static let selectOfficialFileTitle = L10nKey(
            "firmware.select_official_file_title",
            "Select registered Rotor official firmware"
        )

        // MARK: FirmwareView 新增
        public static let notConnectedYet = L10nKey("firmware.not_connected_yet", "Not connected yet")
        public static let vectorTableSummary = L10nKey("firmware.vector_table_summary", "Vector table %@")

        public static let all: [L10nKey] = [
            step1Title, step1Hint, notConnected,
            step2Title, step2Hint, officialCatalog, verifyOK, select, downloadAndVerify,
            archiveOnly, localOfficialFile, localOfficialFileHelp,
            customCompiledImage, selfCompiledCatalog, selfCompiledNone,
            selfCompiledEmpty, revealSelfCompiled, rescanSelfCompiled, customCompiledImageHelp,
            pendingImage, customCompiled, customFirmwareAcknowledgment,
            step3Title, step3Hint, exportFirmwareAndBackup, showInFinder, backupComplete, backupNote,
            step4Title, step4Hint, powerOffWarning,
            recoverToApp, recoverToAppHelp, recoverToAppHint, startUpgrade,
            statusFailed, statusStopped, statusMismatch, statusPassed, statusComplete,
            selectCustomImageTitle, selectOfficialFileTitle,
            notConnectedYet, vectorTableSummary,
        ]
    }
}
