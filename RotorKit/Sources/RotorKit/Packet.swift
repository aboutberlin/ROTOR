import Foundation

/// COMM_PACKET_ID（bldc/datatypes.h，3.6x 稳定）
public enum Comm: Int {
    case fwVersion = 0
    case jumpToBootloader = 1
    case eraseNewApp = 2
    case writeNewAppData = 3
    case getValues = 4
    case setDuty = 5
    case setCurrent = 6
    case setCurrentBrake = 7
    case setRpm = 8
    case setPos = 9
    case setHandbrake = 10
    case setDetect = 11
    case setServoPos = 12
    case setMcconf = 13
    case getMcconf = 14
    case getMcconfDefault = 15
    case setAppconf = 16
    case getAppconf = 17
    case getAppconfDefault = 18
    case detectMotorParam = 24
    case detectMotorRL = 25
    case detectMotorFluxLinkage = 26
    case detectEncoder = 27
    case detectHallFoc = 28
    case reboot = 29
    case alive = 30
    case forwardCan = 34
    case getValuesSetup = 47
    case getValuesSelective = 50
    case setCurrentRel = 84
    // Rotor 在原版 VESC 协议上增加的持久模式切换命令。
    // 已与 Windows Rotor 的 Commands::jumpToCMESC/jumpToMIT 逐条核对。
    case jumpToCmesc = 100
    case jumpToMit = 101
}

/// 实机自动识别出的串口封包代际。
public enum RotorWireProtocol: Equatable {
    /// V1.32 / V2 驱动板使用的标准 VESC 0x02/0x03 封包。
    case vesc
    /// V3 驱动板使用的 Rotor 0xAA/0xAB ... 0xBB 封包。
    case v3

    public var title: String {
        switch self {
        case .vesc: return "VESC UART"
        case .v3: return "V3 UART"
        }
    }
}

/// AK V3 官方手册 §4.3.2 的串口命令编号。
public enum RotorV3Comm: Int {
    case fwVersion = 65
    case jumpToBootloader = 66
    case eraseNewApp = 67
    case writeNewAppData = 68
    case getValues = 69
    case setDuty = 70
    case setCurrent = 71
    case setCurrentBrake = 72
    case setRpm = 73
    case setPos = 74
    case setHandbrake = 75
    case setMcconf = 78
    case getMcconf = 79
    case getMcconfDefault = 80
    case setAppconf = 81
    case getAppconf = 82
    case getAppconfDefault = 83
    /// MIT 五参数阻抗控制。载荷固定 21 字节，全部 int32 大端 ÷1000。
    /// 顺序：pos, rpm, torque, kp, kd —— 与 CAN 上的 MIT 帧顺序**不同**。
    case setPidMit = 96
    /// `COMM_TERMINAL_CMD`(20) + 65。载荷是命令原文（ASCII，不含结尾 0）。
    /// 实测 `0x21`(33) 是同一处理器的别名，两个号都能用。
    case terminalCmd = 85
    /// `COMM_PRINT`(21) + 65。设备用它回送终端输出，一条命令可能回多帧。
    case terminalPrint = 86
    // 由 Windows V3 工具 Commands 类的实际打包/解包代码确认。
    case detectMotorParam = 89
    case detectMotorRL = 90
    case detectMotorFluxLinkage = 91
    case detectEncoder = 92
    case reboot = 94
    case alive = 95
    case getValuesSetup = 16
    case setPosSpd = 60
    case setPosMulti = 61
    case setPosSingle = 62
    case setPosUnlimited = 63
    case setPosOrigin = 64
    // Rotor 自定义模式镜像命令没有采用 +65 偏移，官方 V3 工具
    // Commands::jumpToCMESC / jumpToMIT 直接发送 0x64 / 0x65。
    case jumpToCmesc = 100
    case jumpToMit = 101
}

/// Windows Rotor V3.1.3 固件上传器使用的 IAP 暂存区线路命令。
///
/// 官方 `Commands` 层对大镜像（> 250000 B）选择逻辑命令 0x66/0x2A，
/// 对中等镜像（> 2800 B）选择 0x67/0x2B。同一命令族里的其他 V3 指令已经使用最终线路编号，因此这里不能再做 `+65`。应用先用
/// 0x42 进入 IAP，随后用这些命令写入暂存区。
public enum RotorV3FirmwareUploadCommand {
    public static let eraseLarge = 0x66
    public static let writeLarge = 0x2A
    public static let eraseMedium = 0x67
    public static let writeMedium = 0x2B
    public static let largeImageThreshold = 250_000
    public static let minimumImageSize = 2_800
}

/// VESC 标准封包：0x02/0x03/0x04 起始 + 大端长度 + payload + crc16(hi,lo) + 0x03
public enum Packet {
    public static func encode(_ payload: [UInt8]) -> [UInt8] {
        let n = payload.count
        let crc = CRC.crc16(payload)
        var out: [UInt8] = []
        if n < 256 {
            out = [0x02, UInt8(n)]
        } else if n < 65536 {
            out = [0x03, UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        } else {
            out = [0x04, UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        }
        out.append(contentsOf: payload)
        out.append(UInt8(crc >> 8)); out.append(UInt8(crc & 0xFF)); out.append(0x03)
        return out
    }

    public static func encodeCmd(_ cmd: Comm, _ data: [UInt8] = []) -> [UInt8] {
        encode([UInt8(cmd.rawValue)] + data)
    }
}

/// Rotor V3 串口封包：
/// 0xAA + uint8 长度，或 0xAB + uint16 长度；随后 payload + CRC16 + 0xBB。
public enum RotorV3Packet {
    public static func encode(_ payload: [UInt8]) -> [UInt8] {
        let n = payload.count
        let crc = CRC.crc16(payload)
        var out: [UInt8]
        if n < 256 {
            out = [0xAA, UInt8(n)]
        } else {
            precondition(n < 65536, "Rotor V3 payload too large")
            out = [0xAB, UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        }
        out.append(contentsOf: payload)
        out.append(UInt8(crc >> 8))
        out.append(UInt8(crc & 0xFF))
        out.append(0xBB)
        return out
    }

    public static func encodeCmd(_ cmd: RotorV3Comm, _ data: [UInt8] = []) -> [UInt8] {
        encode([UInt8(cmd.rawValue)] + data)
    }
}

/// 增量解码：喂字节，产出完整帧的 payload。（命名避开 Swift.Decoder 协议）
public final class PacketDecoder {
    private var buf: [UInt8] = []
    public init() {}

    public func feed(_ chunk: [UInt8]) -> [[UInt8]] {
        buf.append(contentsOf: chunk)
        var out: [[UInt8]] = []
        while true {
            let (payload, consumed) = tryOne()
            if payload == nil {
                if consumed > 0 { buf.removeFirst(consumed); continue }
                break
            }
            buf.removeFirst(consumed)
            out.append(payload!)
        }
        return out
    }

    private func tryOne() -> ([UInt8]?, Int) {
        let n = buf.count
        var i = 0
        while i < n {
            let start = buf[i]
            var ln = 0, hdr = 0
            if start == 0x02 {
                if i + 2 > n { return (nil, i) }
                ln = Int(buf[i+1]); hdr = 2
            } else if start == 0x03 {
                if i + 3 > n { return (nil, i) }
                ln = (Int(buf[i+1]) << 8) | Int(buf[i+2]); hdr = 3
            } else if start == 0x04 {
                if i + 4 > n { return (nil, i) }
                ln = (Int(buf[i+1]) << 16) | (Int(buf[i+2]) << 8) | Int(buf[i+3]); hdr = 4
            } else {
                i += 1; continue
            }
            let end = i + hdr + ln + 3
            if end > n { return (nil, i) }
            let payload = Array(buf[(i+hdr)..<(i+hdr+ln)])
            let crc = (UInt16(buf[i+hdr+ln]) << 8) | UInt16(buf[i+hdr+ln+1])
            let stop = buf[i+hdr+ln+2]
            if stop == 0x03 && CRC.crc16(payload) == crc {
                return (payload, end)
            }
            i += 1
        }
        return (nil, i)
    }
}

/// Rotor V3 0xAA/0xAB 封包的增量解码器。
public final class RotorV3PacketDecoder {
    private var buf: [UInt8] = []
    public init() {}

    public func feed(_ chunk: [UInt8]) -> [[UInt8]] {
        buf.append(contentsOf: chunk)
        var out: [[UInt8]] = []
        while true {
            let (payload, consumed) = tryOne()
            if payload == nil {
                if consumed > 0 {
                    buf.removeFirst(consumed)
                    continue
                }
                break
            }
            buf.removeFirst(consumed)
            out.append(payload!)
        }
        return out
    }

    private func tryOne() -> ([UInt8]?, Int) {
        let n = buf.count
        var i = 0
        while i < n {
            let start = buf[i]
            var length = 0
            var headerLength = 0
            if start == 0xAA {
                if i + 2 > n { return (nil, i) }
                length = Int(buf[i + 1])
                headerLength = 2
            } else if start == 0xAB {
                if i + 3 > n { return (nil, i) }
                length = (Int(buf[i + 1]) << 8) | Int(buf[i + 2])
                headerLength = 3
            } else {
                i += 1
                continue
            }

            let end = i + headerLength + length + 3
            if end > n { return (nil, i) }
            let payload = Array(buf[(i + headerLength)..<(i + headerLength + length)])
            let crcIndex = i + headerLength + length
            let crc = (UInt16(buf[crcIndex]) << 8) | UInt16(buf[crcIndex + 1])
            let stop = buf[crcIndex + 2]
            if stop == 0xBB && CRC.crc16(payload) == crc {
                return (payload, end)
            }
            i += 1
        }
        return (nil, i)
    }
}
