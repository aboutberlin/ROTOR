import Foundation

extension L10n {
    public enum Status {
        public static let iapCannotOpenPort = L10nKey(
            "status.iap_cannot_open_port",
            "Cannot open the serial port \u{2014} is another program holding it? Disconnect in Rotor, or quit any other tool using the port.")
        public static let iapFailedNextSteps = L10nKey(
            "status.iap_failed_next_steps",
            "Recovery failed. The link is left untouched. Next: cut the motor's MAIN power for 10 s, unplug the USB adapter, then power up and reconnect.")
        public static let ackButReadbackFailed = L10nKey("status.ack_but_readback_failed", "ACK received, but post-write readback failed")
        public static let backingUpFirmware = L10nKey("status.backing_up_firmware", "Reading and backing up firmware info and parameters…")
        public static let backupComplete = L10nKey("status.backup_complete", "Backup complete: %@")
        public static let backupDonePrepareUpload = L10nKey("status.backup_done_prepare_upload", "Backup complete, preparing upload staging area…")
        public static let backupFailed = L10nKey("status.backup_failed", "Backup failed: %@")
        public static let backupFailedNoErase = L10nKey("status.backup_failed_no_erase", "Parameter read failed before erase; no erase executed")
        public static let bootloaderEntryFailed = L10nKey("status.bootloader_entry_failed", "IAP/Bootloader entry failed; no erase executed")
        public static let bootloaderTimeoutManualRecovery = L10nKey("status.bootloader_timeout_manual_recovery", "Image written, but bootloader timeout; power cycle to verify")
        public static let bootloaderWaiting = L10nKey("status.bootloader_waiting", "Bootloader not returning; reconnecting in 4 seconds…")
        public static let cannotStartDetection = L10nKey("status.cannot_start_detection", "Cannot start detection")
        public static let checkingCustomImage = L10nKey("status.checking_custom_image", "Checking custom image structure…")
        public static let connectedDetails = L10nKey("status.connected_details", "Connected @ %@ · %@ · %@")
        public static let connectedSimulator = L10nKey("status.connected_simulator", "Connected (Simulator)")
        public static let connectionCancelled = L10nKey("status.connection_cancelled", "Connection cancelled")
        public static let connectionLost = L10nKey("status.connection_lost", "Serial connection lost")
        public static let connecting = L10nKey("status.connecting", "Connecting…")
        public static let connectFirstFirmware = L10nKey("status.connect_first_firmware", "Connect motor first to verify model and protocol branch")
        public static let controlActive = L10nKey("status.control_active", "Command written · holding (10 Hz)")
        public static let controlNotSent = L10nKey("status.control_not_sent", "Control command not sent")
        public static let customImageValid = L10nKey("status.custom_image_valid", "Vector table valid (%@); not officially verified, confirm source")
        public static let detectingEncoder = L10nKey("status.detecting_encoder", "Detecting encoder… up to 3 minutes, do not operate")
        public static let detectingFlux = L10nKey("status.detecting_flux", "Detecting flux λ; motor will spin…")
        public static let detectingRl = L10nKey("status.detecting_rl", "Detecting R / L…")
        public static let detectionNotRun = L10nKey("status.detection_not_run", "Parameter detection not run")
        public static let disconnected = L10nKey("status.disconnected", "Not connected")
        public static let downloadingFirmware = L10nKey("status.downloading_firmware", "Downloading and verifying %@ %@…")
        public static let encoderDetectionApplied = L10nKey("status.encoder_detection_applied", "Encoder detection results applied; check then write to motor")
        public static let encoderDetectionFailed = L10nKey("status.encoder_detection_failed", "Encoder detection failed: %@")
        public static let encoderDetectionSuccess = L10nKey("status.encoder_detection_success", "Encoder detection successful: Offset %@°, Ratio %@, %@")
        public static let encoderNotConfigured = L10nKey("status.encoder_not_configured", "Firmware reports encoder not configured (Offset=1001, Ratio=0)")
        public static let encoderTimeout = L10nKey("status.encoder_timeout", "No result packet within 180s; if motor keeps beeping, firmware task failed")
        public static let enteringIap = L10nKey("status.entering_iap", "Entering IAP; no erase or write…")
        public static let finalCheckBackup = L10nKey("status.final_check_backup", "Final verification and parameter backup…")
        public static let firmwareChecksumOk = L10nKey("status.firmware_checksum_ok", "Official archive and image SHA-256 verification passed")
        public static let firmwareExactMatch = L10nKey("status.firmware_exact_match", "Exact match: AK80-9 · %@ · %@")
        public static let firmwareNotSelected = L10nKey("status.firmware_not_selected", "No firmware selected")
        public static let firmwareRecoveryFailed = L10nKey("status.firmware_recovery_failed", "Failed to auto-recover after firmware write")
        public static let firmwareStartingServo = L10nKey("status.firmware_starting_servo", "Firmware written, starting Servo… %@/2")
        public static let firmwareWaitStartup = L10nKey("status.firmware_wait_startup", "Firmware written; waiting for app startup and verification… %@/%@")
        public static let fluxDetectionComplete = L10nKey("status.flux_detection_complete", "Flux detection complete; check results then apply")
        public static let fluxDetectionFailed = L10nKey("status.flux_detection_failed", "Flux detection failed or timeout")
        public static let forward = L10nKey("status.forward", "Forward")
        public static let handshakingBaud = L10nKey("status.handshaking_baud", "Handshaking… %@")
        public static let iapFailed = L10nKey("status.iap_failed", "IAP round-trip failed · Serial safely released; no erase, reconnect")
        public static let iapJumpSequence = L10nKey("status.iap_jump_sequence", "Executing official jump sequence… %@/2")
        public static let iapLostConnection = L10nKey("status.iap_lost_connection", "IAP round-trip failed: serial connection lost")
        public static let iapSuccess = L10nKey("status.iap_success", "IAP round-trip successful · Both A1 rounds and 0x41 readback passed; no erase")
        public static let invalidEncoderValues = L10nKey("status.invalid_encoder_values", "Firmware returned invalid values (Offset=%@, Ratio=%@)")
        public static let invalidRlValues = L10nKey("status.invalid_rl_values", "Firmware returned invalid results (R=%@ Ω, L=%@ µH, Lq−Ld=%@ µH)")
        public static let localImageMatch = L10nKey("status.local_image_match", "Local file matches official image SHA-256")
        public static let malforrmedResponseBytes = L10nKey("status.malformed_response_bytes", "Firmware response incomplete (%@ bytes)")
        public static let modeSwitchFailed = L10nKey("status.mode_switch_failed", "Mode switch send failed")
        public static let modeSwitchSent = L10nKey("status.mode_switch_sent", "Mode switch command sent, waiting for motor restart…")
        public static let modeSwitching = L10nKey("status.mode_switching", "Control stopped, switching mode…")
        public static let modeWrittenReconnecting = L10nKey("status.mode_written_reconnecting", "Mode written, waiting for reconnection")
        public static let moreItems = L10nKey("status.more_items", " and %@ more items")
        public static let motorDetectionApplied = L10nKey("status.motor_detection_applied", "Motor detection results applied; check then write to motor")
        public static let noResponseHelp = L10nKey("status.no_response_help", "No response: try another port / unplug R-LINK / refresh and reconnect")
        public static let notServoMode = L10nKey("status.not_servo_mode", "Not in Servo mode, not sent")
        public static let rawFlashNote = L10nKey(
            "status.raw_flash_note",
            "The UART/CAN protocol has no command to read MCU flash. This backup "
                + "contains only readable parameters and the firmware identity."
        )
        public static let outputDisabledReason = L10nKey("status.output_disabled_reason", "Critical output limits are 0/reversed (%@)")
        public static let outputLimitsRestored = L10nKey("status.output_limits_restored", "Critical output limits restored to signed defaults; not written to motor")
        public static let readbackMismatch = L10nKey("status.readback_mismatch", "Motor readback inconsistent after ACK: %@%@")
        public static let reconnectVerifyVersion = L10nKey("status.reconnect_verify_version", "Write complete, reconnecting and verifying version… 0/%@")
        public static let reversed = L10nKey("status.reversed", "Reversed")
        public static let rlDetectionComplete = L10nKey("status.rl_detection_complete", "RL detection complete; check results then apply")
        public static let rlDetectionFailed = L10nKey("status.rl_detection_failed", "RL detection failed: %@")
        public static let rlTimeout = L10nKey("status.rl_timeout", "No result packet within 30s")
        public static let selectFirmware = L10nKey("status.select_firmware", "Select official or registered local firmware")
        public static let sendFailed = L10nKey("status.send_failed", "Send failed: serial write error")
        public static let simulatorNoResponse = L10nKey("status.simulator_no_response", "Simulator not responding")
        public static let stillAbnormal = L10nKey("status.still_abnormal", "Still abnormal")
        public static let stopSent = L10nKey("status.stop_sent", "Stop command sent")
        public static let stoppingConnection = L10nKey("status.stopping_connection", "Stopping connection attempt…")
        public static let sineTorqueActive = L10nKey("status.sine_torque_active", "Command written · sine torque running (100 Hz)")
        public static let upgradeStopped = L10nKey("status.upgrade_stopped", "Upgrade stopped: %@")
        public static let upgradeVerified = L10nKey("status.upgrade_verified", "Upgrade complete · Reconnect verification passed: %@")
        public static let uploadDoneJumpFailed = L10nKey("status.upload_done_jump_failed", "Image transferred, but jump-to-app command failed")
        public static let uploadFailed = L10nKey("status.upload_failed", "Erase or block write failed: %@")
        public static let uploadingFirmware = L10nKey("status.uploading_firmware", "Writing firmware… %@%%")
        public static let verifyingLocalImage = L10nKey("status.verifying_local_image", "Verifying local image…")
        public static let versionMismatch = L10nKey("status.version_mismatch", "Reconnected, but version mismatch: expected %@, got %@")
        public static let writeFailedNoAck = L10nKey("status.write_failed_no_ack", "Write failed · Motor did not ACK")
        public static let writeSuccess = L10nKey("status.write_success", "Write successful · ACK and modified field readback verification passed")
        public static let writing = L10nKey("status.writing", "Writing…")
        public static let writingMode = L10nKey("status.writing_mode", "Writing %@ mode… %@/5")
        public static let unknownMode = L10nKey("status.unknown_mode", "Unknown mode")

        public static let deviceStoppedResponding = L10nKey(
            "status.device_stopped_responding",
            "Device stopped responding — port released. Power the motor, then press Connect.")

        public static let all: [L10nKey] = [
            ackButReadbackFailed, backingUpFirmware, backupComplete, backupDonePrepareUpload,
            backupFailed, backupFailedNoErase, bootloaderEntryFailed, bootloaderTimeoutManualRecovery,
            bootloaderWaiting, cannotStartDetection, checkingCustomImage, connectedDetails,
            connectedSimulator, connectionCancelled, connectionLost, connecting,
            connectFirstFirmware, controlActive, controlNotSent, customImageValid,
            detectingEncoder, detectingFlux, detectingRl, detectionNotRun,
            disconnected, downloadingFirmware, encoderDetectionApplied, encoderDetectionFailed,
            encoderDetectionSuccess, encoderNotConfigured, encoderTimeout, enteringIap,
            finalCheckBackup, firmwareChecksumOk, firmwareExactMatch, firmwareNotSelected,
            firmwareRecoveryFailed, firmwareStartingServo, firmwareWaitStartup, fluxDetectionComplete,
            deviceStoppedResponding,
            fluxDetectionFailed, forward, handshakingBaud, iapFailed, iapFailedNextSteps, iapCannotOpenPort,
            iapJumpSequence, iapLostConnection, iapSuccess, invalidEncoderValues,
            invalidRlValues, localImageMatch, malforrmedResponseBytes, modeSwitchFailed,
            modeSwitchSent, modeSwitching, modeWrittenReconnecting, moreItems,
            motorDetectionApplied, noResponseHelp, notServoMode, outputDisabledReason, rawFlashNote,
            outputLimitsRestored, readbackMismatch, reconnectVerifyVersion, reversed,
            rlDetectionComplete, rlDetectionFailed, rlTimeout, selectFirmware,
            sendFailed, simulatorNoResponse, stillAbnormal, stopSent,
            stoppingConnection, sineTorqueActive, upgradeStopped, upgradeVerified, uploadDoneJumpFailed,
            uploadFailed, uploadingFirmware, verifyingLocalImage, versionMismatch,
            writeFailedNoAck, writeSuccess, writing, writingMode,
            unknownMode,
        ]
    }
}
