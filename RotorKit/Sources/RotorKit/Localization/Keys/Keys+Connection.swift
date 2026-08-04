import Foundation

extension L10n {
    public enum Connection {
        public static let modeReal = L10nKey("connection.mode_real", "Hardware")
        public static let modeDemo = L10nKey("connection.mode_demo", "Demo")
        public static let modeHelp = L10nKey(
            "connection.mode_help",
            "Hardware talks to your motor over the serial port. Demo runs a built-in "
                + "simulated motor so you can explore the interface without any hardware."
        )
        public static let port = L10nKey("connection.port", "Port")
        public static let refreshPorts = L10nKey("connection.refresh_ports", "Refresh ports")
        public static let baudRate = L10nKey("connection.baud_rate", "Baud rate")
        public static let fault = L10nKey("connection.fault", "Fault")
        public static let controllerID = L10nKey("connection.controller_id", "Controller ID")
        public static let stopTrying = L10nKey("connection.stop_trying", "Stop")
        public static let disconnect = L10nKey("connection.disconnect", "Disconnect")
        public static let connect = L10nKey("connection.connect", "Connect")
        public static let languageHelp = L10nKey(
            "connection.language_help",
            "Interface language. Takes effect immediately; no restart needed."
        )

        public static let all: [L10nKey] = [
            modeReal, modeDemo, modeHelp, port, refreshPorts, baudRate,
            fault, controllerID, stopTrying, disconnect, connect, languageHelp,
        ]
    }
}
