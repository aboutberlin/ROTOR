import Foundation

public protocol Transport: AnyObject {
    @discardableResult func write(_ data: [UInt8]) -> Bool
    func read(max: Int) -> [UInt8]
    @discardableResult func prepareForBootloaderTimeout() -> Bool
    /// 0x42 ACK 后，把 R-LINK 置为官方工具实测的 1200/7N1、RTS+DTR
    /// 关口状态并关闭，再以 921600/8N1 重开，供 0x43/0x44 固件上传使用。
    @discardableResult func enterV3FirmwareUploadLink() -> Bool
    /// 执行 Rotor V3 R-LINK/IAP 层的“跳转应用”动作。真串口实现会
    /// 完整复刻官方工具的两轮开口、原始 A1 包、关口和最终重开。
    @discardableResult func performV3ApplicationReturn(
        startingSequence: UInt8, rounds: Int
    ) -> Bool
    /// A1 已执行但同一文件描述符没有收到 0x41 时，以正常应用态参数
    /// 关闭并新建串口句柄。macOS FTDI 路径实测需要这个一次性兜底。
    @discardableResult func reopenNormalAfterIAP() -> Bool
    func close()
}

public extension Transport {
    /// 非真机传输无需改变串口线路状态。
    @discardableResult func prepareForBootloaderTimeout() -> Bool { true }

    @discardableResult func enterV3FirmwareUploadLink() -> Bool { true }

    /// 回环/测试传输没有可重开的物理端口，只发送同样的原始包。
    @discardableResult func performV3ApplicationReturn(
        startingSequence: UInt8, rounds: Int = 2
    ) -> Bool {
        guard rounds > 0 else { return false }
        var sequence = startingSequence
        for _ in 0..<rounds {
            for _ in 0..<4 {
                guard write(RotorV3IAP.jumpApplication(sequence: sequence)) else {
                    return false
                }
                sequence &+= 1
            }
        }
        return true
    }

    @discardableResult func reopenNormalAfterIAP() -> Bool { true }
}

/// R-LINK/IAP 原始层。这不是外层 `AA ... BB` V3 UART 帧。
///
/// 2026-07-31 在真实 AK80-9 V3 硬件上完整抓包确认（详见
/// `reverse-engineering/v3-firmware-upload-protocol.md`）：
///
/// - 主机发：`EC 96 <type> <seq> A1 <len> [payload] <additiveChecksum>`
/// - 设备回：`7B 8C <type> <seq> A1 <len> [payload] <additiveChecksum>`
///
/// 校验为该包内除末字节外所有字节之和 mod 256。索引 4 的 `A1` 是目标字节，
/// 真正的类型在索引 2：`0E` 控制、`2D` 数据、`2E` 数据 ACK。
public enum RotorV3IAP {
    public static let target: UInt8 = 0xA1
    public static let typeControl: UInt8 = 0x0E
    public static let typeData: UInt8 = 0x2D
    public static let typeDataAck: UInt8 = 0x2E
    /// 每个数据包固定携带 128 字节镜像内容，不足补 0xFF。
    public static let blockSize = 128
    /// 首包令牌。设备在首个 ACK 中返回真正的会话令牌，其后必须改用该值。
    public static let initialSessionToken: [UInt8] = [0x00, 0x00, 0x00, 0x01]

    private static func sealed(_ bytes: [UInt8]) -> [UInt8] {
        var out = bytes
        out.append(out.reduce(UInt8(0), &+))
        return out
    }

    /// 7 字节控制包。上传前发一个；“跳转应用”为两轮各四个。
    public static func controlPacket(sequence: UInt8) -> [UInt8] {
        sealed([0xEC, 0x96, typeControl, sequence, target, 0x07])
    }

    public static func jumpApplication(sequence: UInt8) -> [UInt8] {
        controlPacket(sequence: sequence)
    }

    /// 144 字节固件数据包。`blockIndex * 128` 即镜像内字节偏移。
    /// `sessionToken` 必须是 4 字节，按抓到的原样回填，不做端序解释。
    public static func dataPacket(
        sequence: UInt8,
        sessionToken: [UInt8],
        blockIndex: UInt16,
        data: [UInt8]
    ) -> [UInt8]? {
        guard sessionToken.count == 4, data.count <= blockSize else { return nil }
        var bytes: [UInt8] = [0xEC, 0x96, typeData, sequence, target, 0x90]
        bytes.append(contentsOf: sessionToken)
        bytes.append(contentsOf: [0x0C, 0x00])
        bytes.append(UInt8(blockIndex >> 8))
        bytes.append(UInt8(blockIndex & 0xFF))
        bytes.append(UInt8(blockSize))
        bytes.append(contentsOf: data)
        // 末块补 0xFF，与擦除态一致。
        if data.count < blockSize {
            bytes.append(contentsOf: [UInt8](repeating: 0xFF, count: blockSize - data.count))
        }
        return sealed(bytes)
    }

    public struct UploadAck: Equatable {
        public let sequence: UInt8
        public let sessionToken: [UInt8]
        /// 设备期待的下一个块号。
        public let nextBlock: UInt16
    }

    /// 从接收缓冲中切出 ACK。设备会把多个 ACK 粘在一次读里，且读边界不保证
    /// 对齐帧边界，因此必须按魔数 + 长度字段扫描，不能按固定长度盲切。
    /// 返回已消费的字节数，调用方保留剩余部分等待后续数据。
    public static func parseAcks(_ buffer: [UInt8]) -> (acks: [UploadAck], consumed: Int) {
        var acks: [UploadAck] = []
        var i = 0
        var consumed = 0
        while i + 6 <= buffer.count {
            guard buffer[i] == 0x7B, buffer[i + 1] == 0x8C else {
                i += 1
                consumed = i
                continue
            }
            let length = Int(buffer[i + 5])
            guard length >= 7, length <= 64 else {
                i += 1
                consumed = i
                continue
            }
            guard i + length <= buffer.count else { break } // 帧未收全，留给下次
            let frame = Array(buffer[i..<(i + length)])
            let checksum = frame.dropLast().reduce(UInt8(0), &+)
            if checksum == frame[frame.count - 1],
               frame[2] == typeDataAck,
               length >= 13 {
                acks.append(UploadAck(
                    sequence: frame[3],
                    sessionToken: Array(frame[6..<10]),
                    nextBlock: (UInt16(frame[10]) << 8) | UInt16(frame[11])
                ))
            }
            i += length
            consumed = i
        }
        return (acks, consumed)
    }
}

/// 回环：写入喂给模拟器，缓存其响应帧供读取（无硬件测试）。
public final class LoopbackTransport: Transport {
    let sim: MotorSimulator
    private var rx: [UInt8] = []
    public init(_ sim: MotorSimulator) { self.sim = sim }
    @discardableResult public func write(_ data: [UInt8]) -> Bool {
        for r in sim.feed(data) { rx.append(contentsOf: r) }
        return true
    }
    public func read(max: Int) -> [UInt8] {
        let n = Swift.min(max, rx.count); let out = Array(rx[0..<n]); rx.removeFirst(n); return out
    }
    public func close() {}
}

/// 真机串口（POSIX termios）。高波特率用 IOSSIOSPEED（macOS 专有 ioctl）。
public final class SerialTransport: Transport {
    private var fd: Int32
    private let port: String
    private let baud: Int
    // 与 pyserial 在 macOS 完全一致：_IOW('T', 2, 4字节) —— 实测这条路能把 CH340 设到 921600。
    private static let IOSSIOSPEED: UInt = 0x8004_5402

    public init?(port: String, baud: Int = 921600) {
        self.port = port
        self.baud = baud
        fd = -1
        guard reopenNormal() else { return nil }
    }

    /// 端口是否已被别的进程独占。
    ///
    /// macOS 的 `/dev/cu.*` 默认允许多进程同时打开，两边一起收发会互相搅乱，
    /// 症状是“握手无响应”——把矛头指向电机，实际问题在本机。本类开口时会用
    /// `TIOCEXCL` 独占，于是第二个进程能干脆地判定出来。
    ///
    /// 局限：只有当占用方**也**设置了 `TIOCEXCL` 时才测得出来。占用方若是旧版本
    /// 或第三方程序，这里会返回 false，此时仍需 `lsof` 才能定位。
    public static func isPortBusy(_ port: String) -> Bool {
        let fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return errno == EBUSY }
        let busy = ioctl(fd, TIOCEXCL) != 0
        Darwin.close(fd)
        return busy
    }

    /// 上一次开口失败是否因为端口已被别的进程独占。
    public private(set) var lastOpenFailedBecauseBusy = false

    /// 正常应用态/IAP 通信端口：921600 8N1、CLRRTS、SETDTR。
    /// 这里也用于两轮 A1 之间以及第二轮后的最终重开。
    @discardableResult
    private func reopenNormal() -> Bool {
        close()
        lastOpenFailedBecauseBusy = false
        fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        if fd < 0 {
            lastOpenFailedBecauseBusy = (errno == EBUSY)
            return false
        }
        // 独占本端口；已被别人独占时这里会失败，说明有另一个进程正在用。
        if ioctl(fd, TIOCEXCL) != 0 {
            lastOpenFailedBecauseBusy = true
            close()
            return false
        }
        var tio = termios()
        guard tcgetattr(fd, &tio) == 0 else { close(); return false }
        cfmakeraw(&tio)
        tio.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tio.c_cflag &= ~tcflag_t(CRTSCTS)
        guard tcsetattr(fd, TCSANOW, &tio) == 0 else { close(); return false }
        var speed = UInt32(baud)                          // 4 字节，和 pyserial 一致
        guard withUnsafeMutablePointer(to: &speed, {
            ioctl(fd, SerialTransport.IOSSIOSPEED, $0)
        }) == 0 else { close(); return false }
        // Windows V3.1.3/QSerialPort 真机抓取：正常打开 921600 8N1 后
        // 明确 CLRRTS + SETDTR。特别是 IAP 失败探测的上一次关口会
        // 把 RTS/DTR 都置位，因此下一次开口必须产生 RTS 下降沿。
        var clearBits = Int32(TIOCM_RTS)
        _ = withUnsafeMutablePointer(to: &clearBits) { ioctl(fd, TIOCMBIC, $0) }
        var setBits = Int32(TIOCM_DTR)
        _ = withUnsafeMutablePointer(to: &setBits) { ioctl(fd, TIOCMBIS, $0) }
        usleep(60_000)                 // CH340 开口后稍等稳定
        tcflush(fd, TCIOFLUSH)         // 清掉开口瞬间的杂散字节
        return true
    }

    @discardableResult public func write(_ data: [UInt8]) -> Bool {
        guard fd >= 0 else { return false }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            var wouldBlockRetries = 0
            while offset < raw.count {
                let n = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if n > 0 {
                    offset += n
                    wouldBlockRetries = 0
                } else if n < 0 && errno == EINTR {
                    continue
                } else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)
                            && wouldBlockRetries < 20 {
                    wouldBlockRetries += 1
                    usleep(500)
                } else {
                    return false
                }
            }
            return true
        }
    }

    public func read(max: Int) -> [UInt8] {
        guard fd >= 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: max)
        let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        return n > 0 ? Array(buf[0..<n]) : []
    }

    /// 复刻 Windows V3.1.3/QSerialPort 在进入 IAP 后关闭端口前留下的线路状态。
    /// 真机抓取为 1200 baud、7N1、RTS/DTR 置位；V3 Bootloader 的无上传
    /// 超时回退会受到这个关闭状态影响。这里只改变串口线路状态，不发送任何
    /// 擦除、写入或跳转应用命令。
    @discardableResult
    public func prepareForBootloaderTimeout() -> Bool {
        guard fd >= 0 else { return false }
        var tio = termios()
        guard tcgetattr(fd, &tio) == 0 else { return false }
        cfmakeraw(&tio)
        tio.c_cflag &= ~tcflag_t(PARENB | PARODD | CSTOPB | CSIZE | CRTSCTS)
        tio.c_cflag |= tcflag_t(CS7 | CLOCAL | CREAD)
        guard cfsetispeed(&tio, speed_t(B1200)) == 0,
              cfsetospeed(&tio, speed_t(B1200)) == 0,
              tcsetattr(fd, TCSANOW, &tio) == 0 else { return false }

        var speed = UInt32(1200)
        guard withUnsafeMutablePointer(to: &speed, {
            ioctl(fd, SerialTransport.IOSSIOSPEED, $0)
        }) == 0 else { return false }

        var modemBits = Int32(TIOCM_DTR | TIOCM_RTS)
        guard withUnsafeMutablePointer(to: &modemBits, {
            ioctl(fd, TIOCMBIS, $0)
        }) == 0 else { return false }
        usleep(20_000)
        return true
    }

    /// 固件上传专用关口：**115200 / 8N1 / CLRRTS / SETDTR**，随后关闭。
    ///
    /// 与 `prepareForBootloaderTimeout()`（1200/7N1/RTS+DTR，属于“跳转应用”
    /// 路径）是两套不同的线路状态，切勿混用。本函数依据 2026-07-31 成功升级
    /// 抓包写成：`0x42` ACK 之后官方立即执行这一组设置再 close。
    @discardableResult
    public func prepareForFirmwareUploadGate() -> Bool {
        guard fd >= 0 else { return false }
        var tio = termios()
        guard tcgetattr(fd, &tio) == 0 else { return false }
        cfmakeraw(&tio)
        tio.c_cflag &= ~tcflag_t(PARENB | PARODD | CSTOPB | CSIZE | CRTSCTS)
        tio.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        guard cfsetispeed(&tio, speed_t(B115200)) == 0,
              cfsetospeed(&tio, speed_t(B115200)) == 0,
              tcsetattr(fd, TCSANOW, &tio) == 0 else { return false }

        var speed = UInt32(115_200)
        guard withUnsafeMutablePointer(to: &speed, {
            ioctl(fd, SerialTransport.IOSSIOSPEED, $0)
        }) == 0 else { return false }

        var clearBits = Int32(TIOCM_RTS)
        guard withUnsafeMutablePointer(to: &clearBits, {
            ioctl(fd, TIOCMBIC, $0)
        }) == 0 else { return false }
        var setBits = Int32(TIOCM_DTR)
        guard withUnsafeMutablePointer(to: &setBits, {
            ioctl(fd, TIOCMBIS, $0)
        }) == 0 else { return false }
        usleep(20_000)
        return true
    }

    /// `0x42` ACK 之后进入可接收 R-LINK 固件数据的链路：
    /// 115200 关口 → close → 重开 921600 8N1 CLRRTS/SETDTR。
    @discardableResult
    public func enterV3FirmwareUploadLink() -> Bool {
        guard prepareForFirmwareUploadGate() else { return false }
        close()
        usleep(150_000)
        guard reopenNormal() else { return false }
        usleep(200_000)
        return true
    }

    /// 官方 V3.1.3 “跳转应用”的实测顺序：
    /// 1. 当前口留下 1200/7N1、RTS+DTR 后关闭；
    /// 2. 正常重开，连续发四个 A1 原始包，再以同样关口关闭；
    /// 3. 再执行一次四包动作；约 155 ms 后正常重开；
    /// 4. 调用方随后用外层 V3 `0x41` 校验 APP 已恢复。
    ///
    /// 该路径不发送 0x43/0x44，不擦除、不写入 Flash。
    @discardableResult
    public func performV3ApplicationReturn(
        startingSequence: UInt8, rounds: Int = 2
    ) -> Bool {
        guard rounds > 0 else { return false }
        guard prepareForBootloaderTimeout() else { return false }
        close()

        var sequence = startingSequence
        for round in 0..<rounds {
            // 第一轮官方界面开口至首次写约 438 ms；后续轮次可立即写。
            guard reopenNormal() else { return false }
            if round == 0 { usleep(380_000) } // reopenNormal 已含 60 ms
            for _ in 0..<4 {
                guard write(RotorV3IAP.jumpApplication(sequence: sequence)) else {
                    close()
                    return false
                }
                sequence &+= 1
            }
            _ = tcdrain(fd)
            guard prepareForBootloaderTimeout() else { close(); return false }
            close()
            if round + 1 < rounds { usleep(155_000) }
        }

        // 成功抓包：第二轮 close→最终 open 为 155 ms；open→0x41 为 258 ms。
        usleep(155_000)
        guard reopenNormal() else { return false }
        usleep(198_000) // reopenNormal 已含 60 ms
        return true
    }

    @discardableResult
    public func reopenNormalAfterIAP() -> Bool {
        reopenNormal()
    }

    public func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
}
