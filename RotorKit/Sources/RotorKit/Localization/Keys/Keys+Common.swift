import Foundation

extension L10n {
    public enum Tab {
        public static let realtime = L10nKey("tab.realtime", "Live & Control")
        public static let parameters = L10nKey("tab.parameters", "Parameters")
        public static let device = L10nKey("tab.device", "Device")
        public static let firmware = L10nKey("tab.firmware", "Firmware")

        public static let all: [L10nKey] = [realtime, parameters, device, firmware]
    }
}
