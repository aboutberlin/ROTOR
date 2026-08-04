import Foundation

extension L10n {
    public enum Control {
        // Mode labels
        public static let modeDutyCycle = L10nKey("control.mode_duty_cycle", "Duty Cycle")
        public static let modeCurrent = L10nKey("control.mode_current", "Current")
        public static let modeRpm = L10nKey("control.mode_rpm", "RPM")
        public static let modePosition = L10nKey("control.mode_position", "Position")
        public static let modeHandbrake = L10nKey("control.mode_handbrake", "Handbrake")
        public static let modeSineTorque = L10nKey("control.mode_sine_torque", "Sine Torque")

        // UI labels
        public static let firmwareMode = L10nKey("control.firmware_mode", "Motor Mode")
        public static let modeWriteNote = L10nKey("control.mode_write_note", "Mode written to motor and persists after power-off")
        public static let modeSwitching = L10nKey("control.mode_switching", "Switching…")
        public static let modeSwitchTo = L10nKey("control.mode_switch_to", "Switch to %@ and save")
        public static let modeSwitchWarning = L10nKey("control.mode_switch_warning", "Switching stops control; motor will restart and auto-reconnect")

        // Servo controls
        public static let servoControl = L10nKey("control.servo_control", "Servo Control")
        public static let amplitude = L10nKey("control.amplitude", "Amplitude")
        public static let torqueAmplitude = L10nKey("control.torque_amplitude", "Torque Amplitude")
        public static let frequency = L10nKey("control.frequency", "Frequency")
        public static let target = L10nKey("control.target", "Target")
        public static let eStop = L10nKey("control.estop", "E-Stop")

        // Value displays
        public static let targetDisplay = L10nKey("control.target_display", "Target %@")

        // Mode notes
        public static let mitModeNote = L10nKey("control.mit_mode_note", "Currently in MIT mode; can switch to Servo to use controls below")
        public static let positionControlUnavailable = L10nKey("control.position_control_unavailable", "Position control not available")

        // Sine torque
        public static let updateSineTorque = L10nKey("control.update_sine_torque", "Update Sine Torque")
        public static let startSineTorque = L10nKey("control.start_sine_torque", "Start Sine Torque")
        public static let updateCommand = L10nKey("control.update_command", "Update Command")
        public static let startContinuous = L10nKey("control.start_continuous", "Start Continuous Sending")
        public static let frequencyRange = L10nKey("control.frequency_range", "Frequency 0.05–5 Hz; click start after setting; stops on E-stop, disconnect, or mode switch")
        public static let sliderNote = L10nKey("control.slider_note", "Release slider or press Enter to start; stops on E-stop, disconnect, or mode switch")

        // Units
        public static let unitAmpere = L10nKey("control.unit.ampere", "A")
        public static let unitErpm = L10nKey("control.unit.erpm", "ERPM")
        public static let unitDegree = L10nKey("control.unit.degree", "°")
        public static let unitNm = L10nKey("control.unit.nm", "Nm")

        public static let all: [L10nKey] = [
            modeDutyCycle, modeCurrent, modeRpm, modePosition, modeHandbrake, modeSineTorque,
            firmwareMode, modeWriteNote, modeSwitching, modeSwitchTo, modeSwitchWarning,
            servoControl, amplitude, torqueAmplitude, frequency, target, eStop,
            targetDisplay,
            mitModeNote, positionControlUnavailable,
            updateSineTorque, startSineTorque, updateCommand, startContinuous, frequencyRange, sliderNote,
            unitAmpere, unitErpm, unitDegree, unitNm
        ]
    }
}
