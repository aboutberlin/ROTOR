import Foundation

extension L10n {
    public enum SerialPorts {
        public static let ch340RLink = L10nKey("serial_ports.ch340_rlink", "CH340 (WCH driver) · R-LINK")
        public static let cp210xRLinkMaybe = L10nKey("serial_ports.cp210x_rlink_maybe", "CP210x · Possibly R-LINK")
        public static let usbSerialRLinkMaybe = L10nKey("serial_ports.usb_serial_rlink_maybe", "USB Serial (CH340/CP210x) · Possibly R-LINK")
        public static let usbCDC = L10nKey("serial_ports.usb_cdc", "USB CDC")
        public static let systemBuiltin = L10nKey("serial_ports.system_builtin", "System Built-in")
        public static let usbSerial = L10nKey("serial_ports.usb_serial", "USB Serial")

        public static let all: [L10nKey] = [
            ch340RLink, cp210xRLinkMaybe, usbSerialRLinkMaybe,
            usbCDC, systemBuiltin, usbSerial,
        ]
    }
}
