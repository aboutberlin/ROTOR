import Foundation

/// 伺服控制指令（标准 VESC COMM_SET_*），返回含 COMM id 的 payload。
public enum Control {
    static func cmdI32(_ cmd: Comm, _ value: Int) -> [UInt8] {
        var w = BufWriter(); w.i32(value)
        return [UInt8(cmd.rawValue)] + w.bytes
    }
    public static func setDuty(_ duty: Double) -> [UInt8] { cmdI32(.setDuty, Int((duty * 100000).rounded())) }
    public static func setCurrent(_ a: Double) -> [UInt8] { cmdI32(.setCurrent, Int((a * 1000).rounded())) }
    public static func setCurrentBrake(_ a: Double) -> [UInt8] { cmdI32(.setCurrentBrake, Int((a * 1000).rounded())) }
    public static func setRpm(_ erpm: Double) -> [UInt8] { cmdI32(.setRpm, Int(erpm.rounded())) }
    public static func setPos(_ deg: Double) -> [UInt8] { cmdI32(.setPos, Int((deg * 1_000_000).rounded())) }
    public static func setHandbrake(_ a: Double) -> [UInt8] { cmdI32(.setHandbrake, Int((a * 1000).rounded())) }
    public static func setCurrentRel(_ rel: Double) -> [UInt8] { cmdI32(.setCurrentRel, Int((rel * 100000).rounded())) }
    public static func alive() -> [UInt8] { [UInt8(Comm.alive.rawValue)] }
    public static func reboot() -> [UInt8] { [UInt8(Comm.reboot.rawValue)] }
}

/// AK V3 官方 UART 协议的控制 payload。
public enum RotorV3Control {
    static func cmdI32(_ cmd: RotorV3Comm, _ value: Int) -> [UInt8] {
        var w = BufWriter()
        w.i32(value)
        return [UInt8(cmd.rawValue)] + w.bytes
    }

    public static func setDuty(_ duty: Double) -> [UInt8] {
        cmdI32(.setDuty, Int((duty * 100_000).rounded()))
    }
    public static func setCurrent(_ current: Double) -> [UInt8] {
        cmdI32(.setCurrent, Int((current * 1_000).rounded()))
    }
    public static func setCurrentBrake(_ current: Double) -> [UInt8] {
        cmdI32(.setCurrentBrake, Int((current * 1_000).rounded()))
    }
    public static func setRpm(_ erpm: Double) -> [UInt8] {
        cmdI32(.setRpm, Int(erpm.rounded()))
    }
    public static func setPos(_ degrees: Double) -> [UInt8] {
        cmdI32(.setPos, Int((degrees * 1_000_000).rounded()))
    }
    public static func setHandbrake(_ current: Double) -> [UInt8] {
        cmdI32(.setHandbrake, Int((current * 1_000).rounded()))
    }
}

extension Array where Element == UInt8 {
    public var hex: String { map { String(format: "%02x", $0) }.joined() }
}
