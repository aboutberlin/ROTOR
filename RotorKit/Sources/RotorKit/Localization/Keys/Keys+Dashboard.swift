import Foundation

extension L10n {
    public enum Dashboard {
        // Metric labels
        public static let speed = L10nKey("dashboard.speed", "Speed")
        public static let phaseCurrent = L10nKey("dashboard.phase_current", "Phase Current")
        public static let busCurrent = L10nKey("dashboard.bus_current", "Bus Current")
        public static let voltage = L10nKey("dashboard.voltage", "Voltage")
        public static let dutyCycle = L10nKey("dashboard.duty_cycle", "Duty Cycle")
        public static let temperatureFet = L10nKey("dashboard.temperature_fet", "FET Temperature")
        public static let temperatureMotor = L10nKey("dashboard.temperature_motor", "Motor Temperature")
        public static let position = L10nKey("dashboard.position", "Position")

        // Units
        public static let unitErpm = L10nKey("dashboard.unit.erpm", "ERPM")
        public static let unitVolt = L10nKey("dashboard.unit.volt", "V")
        public static let unitAmpere = L10nKey("dashboard.unit.ampere", "A")
        public static let unitCelsius = L10nKey("dashboard.unit.celsius", "°C")
        public static let unitDegree = L10nKey("dashboard.unit.degree", "°")

        // State labels
        public static let temperatureNotConnected = L10nKey("dashboard.temperature_not_connected", "Not Connected")
        public static let notConnected = L10nKey("dashboard.not_connected", "Not Connected")

        // Tooltips and messages
        public static let temperatureMotorNote = L10nKey("dashboard.temperature_motor_note", "Approximately −90 °C is a firmware sentinel value indicating the temperature sensor is not connected or not enabled by firmware, not actual motor temperature.")
        public static let connectionInstructions = L10nKey("dashboard.connection_instructions", "Select a simulator or serial port at the top, then click \\\"Connect\\\". The simulator requires no hardware and is available for preview.")

        // Chart
        public static let liveChart = L10nKey("dashboard.live_chart", "Live Chart")
        public static let window = L10nKey("dashboard.window", "Window")
        public static let windowLength = L10nKey("dashboard.window_length", "Window Length")
        public static let windowOption = L10nKey("dashboard.window_option", "%@ seconds")
        public static let chartEmpty = L10nKey("dashboard.chart_empty", "Connect to see live chart")

        // Chart axes
        public static let relativeTime = L10nKey("dashboard.relative_time", "Relative Time")
        public static let chartXAxis = L10nKey("dashboard.chart_x_axis", "Seconds (from now)")

        // Current field tooltip table header/content
        public static let currentFieldTooltip = L10nKey("dashboard.current_field_tooltip", "CAN / UART Current Field Correspondence\n\nMeaning | Mac UART Field | Teensy CAN Field | Relationship\nTorque Current Iq | iqCurr (UI \\\"Phase Current\\\") | servo_cur_A | Yes, usually compared by magnitude\nMotor Output Current | currentMotor | No independent field | May be very close to Iq when Id ≈ 0\nBus/Battery Current | currentIn (UI \\\"Bus Current\\\") | 8-byte feedback not provided | Not corresponding\n\nWhat's read from CAN is motor-side current, currently interpreted as Iq; not bus current.\n\nIa, Ib, Ic: Instantaneous currents flowing in three motor phase lines U/V/W, continuously changing positive and negative.\nId, Iq: Two components obtained by transforming three-phase current to a coordinate system rotating with the rotor based on rotor angle.\n\nId (Flux-Axis Current)\n• Primarily controls magnetic flux, does not directly carry main torque output.\n• In normal operation of permanent magnet motors, usually maintained close to 0 A.\n• Uses negative Id during high-speed field weakening.\n• Some salient-pole motor MTPA control may use non-zero Id.\n\nIq (Torque-Axis Current)\n• Primarily determines torque magnitude and direction.\n• Under Rotor \\\"current control\\\", the Iq being sent is exactly this.\n• Current AK80-9 approximation: Output torque [Nm] = 0.5701 × Iq [A].\n\nMotor current vector magnitude ≈ √(Id² + Iq²)\nWhen Id ≈ 0, motor current magnitude ≈ |Iq|; therefore in engineering, Iq is commonly called \\\"phase current\\\".")

        public static let all: [L10nKey] = [
            speed, phaseCurrent, busCurrent, voltage, dutyCycle, temperatureFet, temperatureMotor, position,
            unitErpm, unitVolt, unitAmpere, unitCelsius, unitDegree,
            temperatureNotConnected, notConnected,
            temperatureMotorNote, connectionInstructions,
            liveChart, window, windowLength, windowOption, chartEmpty,
            relativeTime, chartXAxis,
            currentFieldTooltip
        ]
    }
}
