import Foundation

extension L10n {
    public enum Config {
        // Config view status
        public static let configNotLoaded = L10nKey("config.config_not_loaded", "Config not loaded")
        public static let configLoadedDescription = L10nKey(
            "config.config_loaded_description",
            "Motor configuration is read automatically after connection, or click \"Refresh\"."
        )
        public static let commonAndDetection = L10nKey("config.common_and_detection", "Common · Parameter Detection")
        public static let commonParams = L10nKey("config.common_params", "Common Parameters")
        public static let searchPlaceholder = L10nKey("config.search_placeholder", "Search parameters…")
        public static let pendingChanges = L10nKey("config.pending_changes", "Unsaved changes")
        public static let refreshConfig = L10nKey("config.refresh_config", "Refresh")
        public static let writeToMotor = L10nKey("config.write_to_motor", "Write to Motor")

        // Category names
        public static let categoryLimits = L10nKey("config.category_limits", "Limits")
        public static let categoryFOC = L10nKey("config.category_foc", "FOC")
        public static let categorySetup = L10nKey("config.category_setup", "Setup")
        public static let categoryPID = L10nKey("config.category_pid", "PID")
        public static let categoryMotor = L10nKey("config.category_motor", "Motor")
        public static let categoryCurrent = L10nKey("config.category_current", "Current Control")
        public static let categoryBLDCHall = L10nKey("config.category_bldc_hall", "BLDC/Hall")
        public static let categoryOther = L10nKey("config.category_other", "Other")

        // Output configuration health
        public static let outputDisabled = L10nKey(
            "config.output_disabled",
            "Output disabled by parameters: control and detection will not work"
        )
        public static let abnormalFields = L10nKey("config.abnormal_fields", "Abnormal fields: %@")
        public static let restoreDefaults = L10nKey("config.restore_defaults", "Restore default limits for this signature")

        // Motor parameter detection header
        public static let detectionWarning = L10nKey(
            "config.detection_warning",
            "Detection will energize the motor; flux and encoder detection will cause rotation. "
                + "Please remove any load and ensure the area is clear of people and obstacles."
        )
        public static let motorElectricalParams = L10nKey("config.motor_electrical_params", "Motor Electrical Parameter Detection")
        public static let detectionCurrent = L10nKey("config.detection_current", "Detection current")
        public static let detectionCurrentUnit = L10nKey("config.detection_current_unit", "A")
        public static let openLoopSlope = L10nKey("config.open_loop_slope", "Open-loop slope")
        public static let openLoopSlopeUnit = L10nKey("config.open_loop_slope_unit", "ERPM/s")
        public static let lowDutyCycle = L10nKey("config.low_duty_cycle", "Low duty cycle")
        public static let currentLoopTimeConstant = L10nKey("config.current_loop_time_constant", "Current loop time constant")
        public static let timeConstantUnit = L10nKey("config.time_constant_unit", "µs")
        public static let detectRL = L10nKey("config.detect_rl", "Detect R / L")
        public static let detectFluxLinkage = L10nKey("config.detect_flux_linkage", "Detect flux linkage λ")
        public static let applyToParams = L10nKey("config.apply_to_params", "Apply to parameters")

        // Common communication settings
        public static let commonCommSettings = L10nKey("config.common_comm_settings", "Common Communication Settings")

        // Encoder detection
        public static let encoderParamDetection = L10nKey("config.encoder_param_detection", "Encoder Parameter Detection")
        public static let encoderInvertedHelp = L10nKey(
            "config.encoder_inverted_help",
            "foc_encoder_inverted is a FOC commutation calibration parameter, not a user direction control. "
                + "Flipping it alone will corrupt the relationship between encoder angle and three-phase commutation, "
                + "potentially causing stalling, whistling, and violent vibration. "
                + "m_invert_direction is the user direction control, but current Rotor firmware does not accept direct modification. "
                + "Two independent switches are exposed here for strict comparative testing; after modification, click \"Write to Motor\" in the top right."
        )
        public static let startEncoderDetection = L10nKey("config.start_encoder_detection", "Start encoder detection")
        public static let detectionInProgress = L10nKey("config.detection_in_progress", "Detecting…")
        public static let detectionHint = L10nKey(
            "config.detection_hint",
            "\"Apply\" only modifies pending parameters; verify them carefully, then click \"Write to Motor\" in the top right."
        )

        // Detection status messages
        public static let detectingRL = L10nKey("config.detecting_rl", "Detecting R / L?")
        public static let detectRLMessage = L10nKey(
            "config.detect_rl_message",
            "The motor will be energized and emit a test sound, but should not rotate under normal conditions. Please stop any other control first."
        )
        public static let startDetection = L10nKey("config.start_detection", "Start Detection")
        public static let detectingFlux = L10nKey("config.detecting_flux", "Detect flux linkage λ?")
        public static let detectFluxMessage = L10nKey(
            "config.detect_flux_message",
            "The motor will rotate in open loop. Please remove the load and ensure the area is clear of people and obstacles."
        )
        public static let confirmAndStart = L10nKey("config.confirm_and_start", "Confirm and Start")
        public static let detectingEncoder = L10nKey("config.detecting_encoder", "Start encoder parameter detection?")
        public static let detectEncoderMessage = L10nKey(
            "config.detect_encoder_message",
            "The motor will rotate slowly. Please remove the load and ensure the area is clear of people and obstacles."
        )

        // Motor results display
        public static let motorReadValue = L10nKey("config.motor_read_value", "Motor read value")
        public static let newDetectedValue = L10nKey("config.new_detected_value", "New detected value")
        public static let resultSeparator = L10nKey("config.result_separator", "/")
        public static let resistanceUnit = L10nKey("config.resistance_unit", "mΩ")
        public static let inductanceUnit = L10nKey("config.inductance_unit", "µH")
        public static let fluxLinkageUnit = L10nKey("config.flux_linkage_unit", "mWb")
        public static let detectionFailed = L10nKey("config.detection_failed", "Detection failed: %@")
        public static let encoderResultHint = L10nKey("config.encoder_result_hint", "Offset / Ratio / Direction: not yet detected")

        // CAN configuration
        public static let canID = L10nKey("config.can_id", "CAN ID")
        public static let canIDDescription = L10nKey(
            "config.can_id_description",
            "CAN bus node address; multiple motors must use different IDs"
        )
        public static let configNotLoaded2 = L10nKey("config.config_not_loaded_2", "Config not loaded")
        public static let canIDHelp = L10nKey(
            "config.can_id_help",
            "controller_id, range 0–255, used to identify this controller on the CAN bus. "
                + "Motors on the same CAN bus should use different IDs, otherwise messages will collide. "
                + "Changes only affect pending application config, still need to click \"Write to Motor\" in the top right."
        )
        public static let canStatusLevel = L10nKey("config.can_status_level", "CAN Status Frame Level")
        public static let canStatusLevelDescription = L10nKey(
            "config.can_status_level_description",
            "Determines which groups of status frames are periodically broadcast; levels are cumulative, factory default broadcasts only group 1"
        )
        public static let disable = L10nKey("config.disable", "Disable")
        public static let canStatusLevelDisabledHelp = L10nKey(
            "config.can_status_level_disabled_help",
            "send_can_status = 0: do not broadcast status frames at all"
        )
        public static let canStatusRate = L10nKey("config.can_status_rate", "CAN Status Frame Rate")
        public static let canStatusRateDescription = L10nKey(
            "config.can_status_rate_description",
            "send_can_status_rate_hz; number of frames increases multiplicatively with level, pay attention to bus bandwidth"
        )
        public static let hertzUnit = L10nKey("config.hertz_unit", "Hz")
        public static let canStatusRateHelp = L10nKey(
            "config.can_status_rate_help",
            "Broadcast frequency of each status frame group. At level 5, 5 frames are sent per cycle; "
                + "total bus load ≈ frequency × level frames/second, ensure CAN bandwidth is sufficient. "
                + "Changes only affect pending config, still need to click \"Write to Motor\" in the top right."
        )

        // Direction parameters
        public static let encoderCommutationDirection = L10nKey("config.encoder_commutation_direction", "Encoder Commutation Direction")
        public static let encoderCommutationHelp = L10nKey(
            "config.encoder_commutation_help",
            "FOC calibration value; changing it alone strictly prohibits sending control commands"
        )
        public static let userControlDirection = L10nKey("config.user_control_direction", "User Control Direction")
        public static let userControlDirectionHelp = L10nKey(
            "config.user_control_direction_help",
            "CAN / UART command and feedback user coordinate direction"
        )
        public static let reversed = L10nKey("config.reversed", "Reversed")
        public static let forward = L10nKey("config.forward", "Forward")
        public static let directionState = L10nKey("config.direction_state", "%@ · Motor %@ / Pending %@")

        // Status messages
        public static let successMarker = L10nKey("config.success_marker", "Success")
        public static let signatureFormat = L10nKey("config.signature_format", "Signature 0x%@")
        public static let fieldSeparator = L10nKey("config.field_separator", "、")
        public static let identificationFailed = L10nKey("config.identification_failed", "Identification failed: %@")

        /// 参数表签名与设备不符时的封锁提示。
        public static let schemaMismatchTitle = L10nKey(
            "config.schema_mismatch_title",
            "No parameter definition for this device")
        public static let schemaMismatchBody = L10nKey(
            "config.schema_mismatch_body",
            "This firmware reports layout signature %@, but the bundled parameter table is %@. The two do not describe the same layout, so any value shown here would be decoded at the wrong offsets. Editing and writing are disabled. Reading telemetry and firmware info is unaffected.")
        public static let schemaMismatchWriteBlocked = L10nKey(
            "config.schema_mismatch_write_blocked",
            "Write blocked: parameter table does not match this device (%@ vs %@).")

        /// 未登记设备的只读提示。
        public static let unknownDeviceTitle = L10nKey(
            "config.unknown_device_title",
            "New motor — read-only")
        public static let unknownDeviceBody = L10nKey(
            "config.unknown_device_body",
            "This device (%@) is not in the device registry, so its profile was guessed from the protocol family alone. The parameter layout decodes correctly, but pole count, gear ratio, current limits and encoder type are all unverified for this model. Reading is safe and is exactly how a new motor gets characterised; editing, writing and parameter detection stay disabled until a profile is written for it.")
        public static let unknownDeviceWriteBlocked = L10nKey(
            "config.unknown_device_write_blocked",
            "Write blocked: %@ is not a registered device. Reading is allowed; writing is not, until it has a profile.")

        public static let all: [L10nKey] = [
            configNotLoaded, configLoadedDescription, commonAndDetection, commonParams, searchPlaceholder,
            pendingChanges, refreshConfig, writeToMotor,
            categoryLimits, categoryFOC, categorySetup, categoryPID, categoryMotor, categoryCurrent, categoryBLDCHall, categoryOther,
            outputDisabled, abnormalFields, restoreDefaults,
            detectionWarning, motorElectricalParams, detectionCurrent, detectionCurrentUnit, openLoopSlope, openLoopSlopeUnit,
            lowDutyCycle, currentLoopTimeConstant, timeConstantUnit, detectRL, detectFluxLinkage, applyToParams,
            commonCommSettings,
            encoderParamDetection, encoderInvertedHelp, startEncoderDetection, detectionInProgress, detectionHint,
            detectingRL, detectRLMessage, startDetection, detectingFlux, detectFluxMessage, confirmAndStart,
            detectingEncoder, detectEncoderMessage,
            motorReadValue, newDetectedValue, resultSeparator, resistanceUnit, inductanceUnit, fluxLinkageUnit,
            detectionFailed, encoderResultHint,
            canID, canIDDescription, configNotLoaded2, canIDHelp, canStatusLevel, canStatusLevelDescription,
            disable, canStatusLevelDisabledHelp, canStatusRate, canStatusRateDescription, hertzUnit, canStatusRateHelp,
            encoderCommutationDirection, encoderCommutationHelp, userControlDirection, userControlDirectionHelp,
            reversed, forward, directionState,
            successMarker, signatureFormat, fieldSeparator, identificationFailed,
            schemaMismatchTitle, schemaMismatchBody, schemaMismatchWriteBlocked,
            unknownDeviceTitle, unknownDeviceBody, unknownDeviceWriteBlocked,
        ]
    }
}
