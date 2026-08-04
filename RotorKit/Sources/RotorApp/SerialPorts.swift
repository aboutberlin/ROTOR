import Foundation
import RotorKit

enum SerialPorts {
    /// 列出 /dev/cu.* 串口，把最可能是 R-LINK 的排前面。
    static func list() -> [String] {
        let all = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let cu = all.filter { $0.hasPrefix("cu.") }.map { "/dev/\($0)" }
        func rank(_ p: String) -> Int {
            let l = p.lowercased()
            if l.contains("wchusbserial") { return 0 }              // CH340 = R-LINK 最可能
            if l.contains("slab_usbtouart") || l.contains("usbserial") { return 1 }  // CP210x
            if l.contains("usbmodem") { return 2 }
            if l.contains("bluetooth") || l.contains("debug") { return 9 }
            return 5
        }
        return cu.sorted { (rank($0), $0) < (rank($1), $1) }
    }

    static func note(_ p: String) -> String {
        let l = p.lowercased()
        if l.contains("wchusbserial") { return L10n.t(L10n.SerialPorts.ch340RLink) }
        if l.contains("slab_usbtouart") { return L10n.t(L10n.SerialPorts.cp210xRLinkMaybe) }
        if l.contains("usbserial") { return L10n.t(L10n.SerialPorts.usbSerialRLinkMaybe) }
        if l.contains("usbmodem") { return L10n.t(L10n.SerialPorts.usbCDC) }
        if l.contains("bluetooth") || l.contains("debug") { return L10n.t(L10n.SerialPorts.systemBuiltin) }
        return L10n.t(L10n.SerialPorts.usbSerial)
    }
}
