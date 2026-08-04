import Foundation

/// POSIX `usleep` 可被信号提前中断。固件页的 1 s 命令间隔不能
/// 因终端或系统信号缩短，因此用 `nanosleep` 的剩余时间重试。
private func firmwareSleep(_ seconds: TimeInterval) {
    guard seconds > 0 else { return }
    let whole = floor(seconds)
    var requested = timespec(
        tv_sec: Int(whole),
        tv_nsec: Int((seconds - whole) * 1_000_000_000)
    )
    var remaining = timespec()
    while nanosleep(&requested, &remaining) == -1 && errno == EINTR {
        requested = remaining
    }
}

/// 高层客户端：握手、实时数据、读写配置、伺服控制。
/// 写配置默认复用最近一次 getMcconf 从设备读回的签名 → 与固件匹配。
public final class Client: FirmwareUploadHost {
    let t: Transport
    private let vescDecoder = PacketDecoder()
    private let v3Decoder = RotorV3PacketDecoder()
    public let codec: ConfigCodec?
    public let v3Codec: ConfigCodec?
    public let appconfCodec: ConfigCodec?
    public private(set) var deviceMcconfSignature: UInt32?
    public private(set) var deviceAppconfSignature: UInt32?
    public private(set) var wireProtocol: RotorWireProtocol = .vesc
    /// 握手后匹配到的设备档案。未连接时是通用兜底。
    /// 上层应当问 `supports(_:)` 而不是判断 `wireProtocol`——
    /// 前者加设备不用改，后者每加一款都要回头找所有判断点。
    public private(set) var profile: DeviceProfile =
        DeviceRegistry.genericVesc(for: DeviceIdentity(
            hardwareName: "", firmwareMajor: 0, firmwareMinor: 0, wireProtocol: .vesc))
    public private(set) var connectedModeCode: Int?
    /// 可选的原始线路诊断。默认关闭；固件升级 CLI 开启后会记录实际 TX/RX，
    /// 用于区分“设备明确拒绝”和“没有收到/没有解出响应”。
    public var wireTrace: ((String, [UInt8]) -> Void)?
    /// 官方工具进程内维护一个滚动的 UInt8 序号；重启官方工具会从 0
    /// 重新开始，因此设备不要求跨进程持久化。每次 A1 包发送后递增。
    private var v3IAPSequence: UInt8 = 0
    public var configurationCodec: ConfigCodec? {
        wireProtocol == .v3 ? v3Codec : codec
    }
    public var supportsConfiguration: Bool {
        configurationCodec != nil && appconfCodec != nil
    }

    public init(_ t: Transport, codec: ConfigCodec? = nil,
                v3Codec: ConfigCodec? = nil,
                appconfCodec: ConfigCodec? = nil) {
        self.t = t
        self.codec = codec
        self.v3Codec = v3Codec
        self.appconfCodec = appconfCodec
    }

    private func requestVesc(_ payload: [UInt8], expect: Int, retries: Int = 100,
                             delayUs: UInt32 = 2000,
                             shouldCancel: (() -> Bool)? = nil) -> [UInt8]? {
        let packet = Packet.encode(payload)
        wireTrace?("TX-VESC", packet)
        guard t.write(packet) else { return nil }
        for _ in 0..<retries {
            if shouldCancel?() == true { return nil }
            let chunk = t.read(max: 8192)
            if !chunk.isEmpty { wireTrace?("RX-RAW", chunk) }
            for frame in vescDecoder.feed(chunk) {
                wireTrace?("RX-VESC", frame)
                if let first = frame.first, Int(first) == expect { return frame }
            }
            usleep(delayUs)
        }
        return nil
    }

    private func requestV3(_ payload: [UInt8], expect: Int, retries: Int = 100,
                           delayUs: UInt32 = 2000,
                           keepAlive: Bool = false,
                           shouldCancel: (() -> Bool)? = nil) -> [UInt8]? {
        let packet = RotorV3Packet.encode(payload)
        wireTrace?("TX-V3", packet)
        guard t.write(packet) else { return nil }
        // 官方 V3 工具约每秒发送一次 0x5F。耗时辨识期间维持同样节奏，
        // 避免过密心跳干扰固件的阻塞式辨识任务。
        let keepAliveInterval = max(1, Int(1_000_000 / max(delayUs, 1)))
        for attempt in 0..<retries {
            if shouldCancel?() == true { return nil }
            let chunk = t.read(max: 8192)
            if !chunk.isEmpty { wireTrace?("RX-RAW", chunk) }
            for frame in v3Decoder.feed(chunk) {
                wireTrace?("RX-V3", frame)
                if let first = frame.first, Int(first) == expect { return frame }
            }
            if keepAlive, attempt > 0, attempt % keepAliveInterval == 0 {
                _ = t.write(RotorV3Packet.encodeCmd(.alive))
            }
            usleep(delayUs)
        }
        return nil
    }

    private func requestVesc(_ payload: [UInt8], expect: Comm, retries: Int = 100,
                             delayUs: UInt32 = 2000) -> [UInt8]? {
        requestVesc(payload, expect: expect.rawValue, retries: retries, delayUs: delayUs)
    }

    public func fwVersion(shouldCancel: (() -> Bool)? = nil) -> (major: Int, minor: Int, hw: String)? {
        if let frame = requestVesc([UInt8(Comm.fwVersion.rawValue)],
                                   expect: Comm.fwVersion.rawValue,
                                   shouldCancel: shouldCancel),
           frame.count >= 3 {
            wireProtocol = .vesc
            connectedModeCode = nil
            let zero = frame[3...].firstIndex(of: 0) ?? frame.count
            let hw = String(decoding: frame[3..<zero], as: UTF8.self)
            adoptProfile(hardwareName: hw, major: Int(frame[1]), minor: Int(frame[2]))
            return (Int(frame[1]), Int(frame[2]), hw)
        }

        let command = UInt8(RotorV3Comm.fwVersion.rawValue)
        guard let frame = requestV3([command], expect: Int(command),
                                    shouldCancel: shouldCancel),
              frame.count >= 5 else {
            wireProtocol = .vesc
            return nil
        }
        wireProtocol = .v3
        connectedModeCode = Int(frame[3])
        // V3 FW_VERSION: cmd, major, minor, mode/type byte, zero-terminated HW string...
        let hwStart = frame[3] < 0x20 ? 4 : 3
        let zero = frame[hwStart...].firstIndex(of: 0) ?? frame.count
        let hw = String(decoding: frame[hwStart..<zero], as: UTF8.self)
        adoptProfile(hardwareName: hw, major: Int(frame[1]), minor: Int(frame[2]))
        return (Int(frame[1]), Int(frame[2]), hw)
    }

    /// 已确认为 V3 线路时仅发送 V3 `0x41`。IAP 等待结束时不应
    /// 先混入 VESC 封包；Windows V3.1.3 也是直接连续查询该命令。
    public func fwVersionV3Only(retries: Int = 100,
                                delayUs: UInt32 = 2_000)
        -> (major: Int, minor: Int, hw: String)? {
        let command = UInt8(RotorV3Comm.fwVersion.rawValue)
        guard let frame = requestV3([command], expect: Int(command),
                                    retries: retries, delayUs: delayUs),
              frame.count >= 5 else { return nil }
        wireProtocol = .v3
        connectedModeCode = Int(frame[3])
        let hwStart = frame[3] < 0x20 ? 4 : 3
        let zero = frame[hwStart...].firstIndex(of: 0) ?? frame.count
        return (Int(frame[1]), Int(frame[2]),
                String(decoding: frame[hwStart..<zero], as: UTF8.self))
    }

    public func getValues() -> MotorValues? {
        switch wireProtocol {
        case .vesc:
            guard let frame = requestVesc([UInt8(Comm.getValues.rawValue)],
                                          expect: .getValues) else { return nil }
            return MotorValues.parse(frame)
        case .v3:
            let command = UInt8(RotorV3Comm.getValues.rawValue)
            guard let frame = requestV3([command], expect: Int(command)) else { return nil }
            return MotorValues.parseRotorV3(frame)
        }
    }

    public func getMcconf() -> (UInt32, [String: ParamValue])? {
        guard supportsConfiguration, let codec = configurationCodec else { return nil }
        let fr: [UInt8]?
        switch wireProtocol {
        case .vesc:
            fr = requestVesc([UInt8(Comm.getMcconf.rawValue)],
                             expect: Comm.getMcconf.rawValue)
        case .v3:
            let command = UInt8(RotorV3Comm.getMcconf.rawValue)
            fr = requestV3([command], expect: Int(command), retries: 1_000)
        }
        guard let fr else { return nil }
        let (sig, values) = codec.unpack(Array(fr.dropFirst()))
        deviceMcconfSignature = sig
        return (sig, values)
    }

    @discardableResult public func setMcconf(_ values: [String: ParamValue],
                                             signature: UInt32? = nil) -> Bool {
        guard supportsConfiguration, let codec = configurationCodec else { return false }
        let sig = signature ?? deviceMcconfSignature ?? codec.signature
        switch wireProtocol {
        case .vesc:
            let payload = [UInt8(Comm.setMcconf.rawValue)]
                + codec.pack(values, signature: sig)
            // V2/VESC 固件会以同命令号返回 ACK。不能只把 POSIX write 成功
            // 当作电机确认，否则后续回读失败时会误报“已经收到 ACK”。
            return requestVesc(payload, expect: Comm.setMcconf.rawValue,
                               retries: 1_000) != nil
        case .v3:
            let command = UInt8(RotorV3Comm.setMcconf.rawValue)
            let payload = [command] + codec.pack(values, signature: sig)
            return requestV3(payload, expect: Int(command), retries: 1_000) != nil
        }
    }

    public func getAppconf() -> (UInt32, [String: ParamValue])? {
        guard supportsConfiguration, let codec = appconfCodec else { return nil }
        let fr: [UInt8]?
        switch wireProtocol {
        case .vesc:
            fr = requestVesc([UInt8(Comm.getAppconf.rawValue)],
                             expect: Comm.getAppconf.rawValue)
        case .v3:
            let command = UInt8(RotorV3Comm.getAppconf.rawValue)
            fr = requestV3([command], expect: Int(command), retries: 1_000)
        }
        guard let fr else { return nil }
        let (sig, values) = codec.unpack(Array(fr.dropFirst()))
        deviceAppconfSignature = sig
        return (sig, values)
    }

    @discardableResult public func setAppconf(_ values: [String: ParamValue],
                                              signature: UInt32? = nil) -> Bool {
        guard supportsConfiguration, let codec = appconfCodec else { return false }
        let sig = signature ?? deviceAppconfSignature ?? codec.signature
        switch wireProtocol {
        case .vesc:
            let payload = [UInt8(Comm.setAppconf.rawValue)]
                + codec.pack(values, signature: sig)
            return requestVesc(payload, expect: Comm.setAppconf.rawValue,
                               retries: 1_000) != nil
        case .v3:
            let command = UInt8(RotorV3Comm.setAppconf.rawValue)
            let payload = [command] + codec.pack(values, signature: sig)
            return requestV3(payload, expect: Int(command), retries: 1_000) != nil
        }
    }

    // 伺服控制
    @discardableResult public func servoDuty(_ v: Double) -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encode(RotorV3Control.setDuty(v)))
            : t.write(Packet.encode(Control.setDuty(v)))
    }
    @discardableResult public func servoCurrent(_ a: Double) -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encode(RotorV3Control.setCurrent(a)))
            : t.write(Packet.encode(Control.setCurrent(a)))
    }
    @discardableResult public func servoRpm(_ e: Double) -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encode(RotorV3Control.setRpm(e)))
            : t.write(Packet.encode(Control.setRpm(e)))
    }
    @discardableResult public func servoPos(_ d: Double) -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encode(RotorV3Control.setPos(d)))
            : t.write(Packet.encode(Control.setPos(d)))
    }
    @discardableResult public func handbrake(_ a: Double) -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encode(RotorV3Control.setHandbrake(a)))
            : t.write(Packet.encode(Control.setHandbrake(a)))
    }
    /// Windows V3 工具会周期发送 0x5F；控制和耗时辨识都要维持该心跳。
    @discardableResult public func alive() -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encodeCmd(.alive))
            : t.write(Packet.encode(Control.alive()))
    }

    /// 让当前 Servo 固件重新启动。V3 官方工具使用 0x5E。
    @discardableResult public func reboot() -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encodeCmd(.reboot))
            : t.write(Packet.encode(Control.reboot()))
    }

    // FOC 参数辨识（Rotor / VESC Tool 3.x 协议）
    public func detectMotorRLDetailed(
    ) -> Result<MotorRLDetection, MotorRLDetectionFailure> {
        guard supportsConfiguration else { return .failure(.noResponse) }
        let command = wireProtocol == .v3
            ? RotorV3Comm.detectMotorRL.rawValue
            : Comm.detectMotorRL.rawValue
        let fr = wireProtocol == .v3
            ? requestV3([UInt8(command)], expect: command, retries: 15_000,
                        keepAlive: true)
            : requestVesc([UInt8(command)], expect: command, retries: 15_000)
        guard let fr else { return .failure(.noResponse) }
        guard fr.count >= 9 else {
            return .failure(.malformedResponse(length: fr.count))
        }
        var r = BufReader(fr.dropFirst())
        let resistance = r.f32(1e6)
        let inductanceMicrohenry = r.f32(1e3)
        let differenceMicrohenry = r.remaining >= 4 ? r.f32(1e3) : 0
        guard resistance.isFinite, inductanceMicrohenry.isFinite,
              resistance > 0, inductanceMicrohenry > 0 else {
            return .failure(.invalidValues(
                resistance: resistance,
                inductanceMicrohenry: inductanceMicrohenry,
                differenceMicrohenry: differenceMicrohenry))
        }
        return .success(MotorRLDetection(
            resistance: resistance,
            inductanceMicrohenry: inductanceMicrohenry,
            differenceMicrohenry: differenceMicrohenry))
    }

    /// 兼容原有调用方；需要失败原因时使用 `detectMotorRLDetailed`。
    public func detectMotorRL() -> MotorRLDetection? {
        try? detectMotorRLDetailed().get()
    }

    public func detectMotorFluxLinkage(current: Double, minERPM: Double,
                                       lowDuty: Double, resistance: Double) -> Double? {
        guard supportsConfiguration else { return nil }
        var w = BufWriter()
        let command = wireProtocol == .v3
            ? RotorV3Comm.detectMotorFluxLinkage.rawValue
            : Comm.detectMotorFluxLinkage.rawValue
        w.u8(command)
        w.f32(current, 1e3)
        w.f32(minERPM, 1e3)
        w.f32(lowDuty, 1e3)
        w.f32(resistance, 1e6)
        let fr = wireProtocol == .v3
            ? requestV3(w.bytes, expect: command, retries: 15_000,
                        keepAlive: true)
            : requestVesc(w.bytes, expect: command, retries: 15_000)
        guard let fr, fr.count >= 5 else { return nil }
        var r = BufReader(fr.dropFirst())
        let flux = r.f32(1e7)
        return flux > 0 ? flux : nil
    }

    public func detectEncoderDetailed(
        current: Double
    ) -> Result<EncoderDetection, EncoderDetectionFailure> {
        guard supportsConfiguration else {
            return .failure(.noResponse)
        }
        var w = BufWriter()
        let command = wireProtocol == .v3
            ? RotorV3Comm.detectEncoder.rawValue
            : Comm.detectEncoder.rawValue
        w.u8(command)
        // Windows V3 工具把辨识电流限制在 -10...10 A。
        let safeCurrent = wireProtocol == .v3 ? min(max(current, -10), 10) : current
        w.f32(safeCurrent, 1e3)
        // 部分 AK V3 驱动的编码器辨识会持续超过一分钟；两套协议均留出
        // 180 秒，期间继续发送官方 0x5F 心跳。
        let retries = 90_000
        let fr = wireProtocol == .v3
            ? requestV3(w.bytes, expect: command, retries: retries,
                        keepAlive: true)
            : requestVesc(w.bytes, expect: command, retries: retries)
        guard let fr else {
            return .failure(.noResponse)
        }
        guard fr.count >= 10 else {
            return .failure(.malformedResponse(length: fr.count))
        }
        var r = BufReader(fr.dropFirst())
        let result = EncoderDetection(offset: r.f32(1e6),
                                      ratio: r.f32(1e6),
                                      inverted: r.i8() != 0)

        // VESC FW 5.01 在 encoder_is_configured() 为 false 时返回固定哨兵值
        // offset=1001、ratio=0、inverted=false。
        if result.offset >= 1000, result.ratio == 0 {
            return .failure(.encoderNotConfigured)
        }
        guard result.offset.isFinite, result.ratio.isFinite,
              abs(result.offset) <= 720, result.ratio > 0 else {
            return .failure(.invalidValues(offset: result.offset, ratio: result.ratio))
        }
        return .success(result)
    }

    /// 兼容原有调用方；需要失败原因时使用 `detectEncoderDetailed`。
    public func detectEncoder(current: Double) -> EncoderDetection? {
        try? detectEncoderDetailed(current: current).get()
    }

    /// Rotor 的模式切换流程会先让当前固件进入 Bootloader，
    /// 再由 Bootloader 接收 jumpToCMESC / jumpToMIT。
    @discardableResult public func jumpToBootloader() -> Bool {
        wireProtocol == .v3
            ? t.write(RotorV3Packet.encodeCmd(.jumpToBootloader))
            : t.write(Packet.encodeCmd(.jumpToBootloader))
    }

    /// MIT 五参数阻抗控制（`0x60`）。
    ///
    /// 载荷固定 21 字节：命令号 + 5 个 int32 大端，各自 ÷1000。
    /// **固件不做长度校验**，短包会读越界，因此这里必须精确构造。
    /// 命令不返回应答包，但设备每收一条会回吐一行 `0x56` 文本调试回显。
    /// 力矩字段固件内部还会再除以 `KIT_OUT`（用终端命令 `custp` 可读）。
    ///
    /// 字段顺序与 CAN 上的 MIT 帧**不同**，不要照抄 CAN 手册。
    /// 生效后可用终端命令 `foc_state` 回读 `m_mit_*_set` 验证。
    @discardableResult public func setPidMit(
        pos: Double, rpm: Double, torque: Double, kp: Double, kd: Double
    ) -> Bool {
        guard wireProtocol == .v3 else { return false }
        func scaled(_ value: Double) -> UInt32 {
            UInt32(bitPattern: Int32(clamping: Int(
                (value * 1000).rounded()
            )))
        }
        var writer = BufWriter()
        writer.u8(RotorV3Comm.setPidMit.rawValue)
        writer.u32(scaled(pos))
        writer.u32(scaled(rpm))
        writer.u32(scaled(torque))
        writer.u32(scaled(kp))
        writer.u32(scaled(kd))
        guard writer.bytes.count == 21 else { return false }
        let packet = RotorV3Packet.encode(writer.bytes)
        wireTrace?("TX-V3", packet)
        return t.write(packet)
    }

    /// 发送 VESC 终端命令并收集设备回送的文本。
    ///
    /// 载荷是命令原文（不含结尾 0）；设备用 `COMM_PRINT` 回送，**一条命令可能
    /// 分多帧**，所以这里用“静默窗口”收口：收到第一帧后若连续 `quietUs` 没有
    /// 新帧，就认为输出结束。只读命令（如 `hw_status`）用它最合适。
    public func terminalCommand(_ text: String,
                                timeoutUs: UInt32 = 3_000_000,
                                quietUs: UInt32 = 400_000,
                                commandId: Int? = nil) -> [String] {
        guard wireProtocol == .v3, !text.isEmpty else { return [] }
        let payload = [UInt8(commandId ?? RotorV3Comm.terminalCmd.rawValue)] + Array(text.utf8)
        let packet = RotorV3Packet.encode(payload)
        wireTrace?("TX-V3", packet)
        guard t.write(packet) else { return [] }

        var lines: [String] = []
        let step: UInt32 = 2_000
        var elapsed: UInt32 = 0
        var sinceLastFrame: UInt32 = 0
        while elapsed < timeoutUs {
            let chunk = t.read(max: 8192)
            if !chunk.isEmpty { wireTrace?("RX-RAW", chunk) }
            var received = false
            for frame in v3Decoder.feed(chunk) {
                wireTrace?("RX-V3", frame)
                guard let first = frame.first,
                      Int(first) == RotorV3Comm.terminalPrint.rawValue else { continue }
                let body = Array(frame.dropFirst()).prefix { $0 != 0 }
                if let line = String(bytes: body, encoding: .utf8),
                   !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append(line)
                    received = true
                }
            }
            if received {
                sinceLastFrame = 0
            } else if !lines.isEmpty {
                sinceLastFrame += step
                if sinceLastFrame >= quietUs { break }
            }
            usleep(step)
            elapsed += step
        }
        return lines
    }

    /// 固件升级专用的 IAP 进入流程。V3 应用会在真正跳转前回一个 0x42 ACK；
    /// 只有收到这个 ACK 才能认为后续擦除命令可以安全发送。模式切换仍保留上面
    /// 的 fire-and-forget 行为，以兼容部分跳转后立即复位、来不及回 ACK 的旧固件。
    @discardableResult public func enterFirmwareBootloader() -> Bool {
        guard wireProtocol == .v3 else { return jumpToBootloader() }
        let command = RotorV3Comm.jumpToBootloader.rawValue
        return requestV3([UInt8(command)], expect: command,
                         retries: 2_500, delayUs: 2_000) != nil
    }

    /// V3 的 0x42 只完成应用层握手。ACK 之后还必须复刻官方 R-LINK 的
    /// 1200/7N1 关口与正常重开，Bootloader 才会接收 0x43/0x44。
    @discardableResult public func activateFirmwareBootloaderLink() -> Bool {
        wireProtocol != .v3 || t.enterV3FirmwareUploadLink()
    }

    @discardableResult public func jumpToServoMode() -> Bool {
        let command = wireProtocol == .v3
            ? RotorV3Comm.jumpToCmesc.rawValue
            : Comm.jumpToCmesc.rawValue
        let payload = [UInt8(command)]
        return wireProtocol == .v3
            ? t.write(RotorV3Packet.encode(payload))
            : t.write(Packet.encode(payload))
    }

    @discardableResult public func jumpToMitMode() -> Bool {
        let command = wireProtocol == .v3
            ? RotorV3Comm.jumpToMit.rawValue
            : Comm.jumpToMit.rawValue
        let payload = [UInt8(command)]
        return wireProtocol == .v3
            ? t.write(RotorV3Packet.encode(payload))
            : t.write(Packet.encode(payload))
    }

    /// 完整复刻 Windows V3.1.3 的“跳转应用”动作。
    ///
    /// 2026-07-31 全量 TX/RX 抓包确认它并不是外层 V3 `0x64`，而是两轮
    /// R-LINK/IAP 原始 A1 包；每轮 4 包且轮末改变线路状态并关闭串口。
    /// 第二轮后重开，再用外层 V3 `0x41` 回读确认应用实际启动。
    /// 该流程不发送擦除 `0x43` 或写入 `0x44`。
    @discardableResult public func recoverV3ServoApplication(
        enterBootloaderFirst: Bool = true,
        progress: ((Int) -> Void)? = nil
    ) -> Bool {
        guard wireProtocol == .v3 else { return false }
        if enterBootloaderFirst {
            guard enterFirmwareBootloader() else { return false }
            firmwareSleep(0.10)
        }
        progress?(1)
        guard t.performV3ApplicationReturn(
            startingSequence: v3IAPSequence, rounds: 2
        ) else { return false }
        v3IAPSequence &+= 8
        progress?(2)
        if fwVersionV3Only(retries: 1_000, delayUs: 2_000) != nil {
            return true
        }

        // macOS FTDI 真机首次运行中，两轮 A1 已让电机回到 APP，但同一个
        // 文件描述符上的 0x41 没有收到；关闭后由新句柄立即读到了 FW 与
        // 实时数据。只做两次有界的新句柄校验，不重发 A1、不等待 60 秒。
        for _ in 0..<2 {
            guard t.reopenNormalAfterIAP() else { return false }
            firmwareSleep(0.25)
            if fwVersionV3Only(retries: 1_000, delayUs: 2_000) != nil {
                return true
            }
        }
        return false
    }

    /// 上传固件。
    ///
    /// 选哪条策略由线路世代决定，之后的流程调用方不需要区分。
    /// V3 走 bootloader 的 IAP 原始帧；V1/V2 走擦除 + 分块的暂存区路径。
    ///
    /// 曾经这里有一条 V3 的 `0x66`/`0x2A` 擦除分支，出自一个后来被推翻的推断。
    /// 真机总线上那两个命令**一次都没出现**——那是从上游继承的死代码，
    /// V3 固件页从不走它。已随本次重构删除。
    public func uploadNewApp(
        image: [UInt8],
        progress: ((Double) -> Void)? = nil
    ) -> Result<FirmwareUploadReceipt, FirmwareUploadFailure> {
        firmwareUploadStrategy.upload(image: image, host: self, progress: progress)
    }

    /// 当前线路世代对应的上传策略。
    public var firmwareUploadStrategy: FirmwareUploadStrategy {
        profile.makeUploadStrategy()
    }

    /// 设备是否具备某项能力。上层判断的唯一入口。
    public func supports(_ capability: Capability) -> Bool {
        profile.supports(capability)
    }

    /// 握手成功后据身份选定档案。
    private func adoptProfile(hardwareName: String, major: Int, minor: Int) {
        profile = DeviceRegistry.profile(for: DeviceIdentity(
            hardwareName: hardwareName, firmwareMajor: major,
            firmwareMinor: minor, wireProtocol: wireProtocol))
    }

    /// 在 V3 IAP 重连失败后，按官方工具的关口状态释放串口。
    @discardableResult public func prepareForBootloaderTimeout() -> Bool {
        t.prepareForBootloaderTimeout()
    }

    public func close() { t.close() }
}

public struct FirmwareUploadReceipt: Equatable {
    public let imageSize: Int
    public let imageCRC16: UInt16
    public let transmittedSize: Int
    public let writtenChunks: Int
    public let skippedChunks: Int

    public init(imageSize: Int, imageCRC16: UInt16, transmittedSize: Int,
                writtenChunks: Int, skippedChunks: Int) {
        self.imageSize = imageSize
        self.imageCRC16 = imageCRC16
        self.transmittedSize = transmittedSize
        self.writtenChunks = writtenChunks
        self.skippedChunks = skippedChunks
    }
}

public enum FirmwareUploadFailure: Error, Equatable {
    case emptyImage
    case invalidImageSize(Int)
    case eraseRejected
    case chunkRejected(offset: Int, length: Int)
    /// R-LINK 上传：某一块连续多次未收到 ACK。官方工具在这种情况下会无限
    /// 重发（实测把第 0 块重发了 12114 次），本实现必须直接失败退出。
    case blockNotAcknowledged(block: Int, attempts: Int)
    /// 只有 V3 走 R-LINK 上传路径。
    case unsupportedProtocol
}

public struct MotorRLDetection: Equatable {
    public let resistance: Double
    /// 协议返回单位为 µH；写入 foc_motor_l 时需乘 1e-6。
    public let inductanceMicrohenry: Double
    public let differenceMicrohenry: Double

    public init(resistance: Double, inductanceMicrohenry: Double,
                differenceMicrohenry: Double) {
        self.resistance = resistance
        self.inductanceMicrohenry = inductanceMicrohenry
        self.differenceMicrohenry = differenceMicrohenry
    }
}

public enum MotorRLDetectionFailure: Error, Equatable {
    case noResponse
    case malformedResponse(length: Int)
    case invalidValues(
        resistance: Double,
        inductanceMicrohenry: Double,
        differenceMicrohenry: Double
    )
}

public struct EncoderDetection: Equatable {
    public let offset: Double
    public let ratio: Double
    public let inverted: Bool

    public init(offset: Double, ratio: Double, inverted: Bool) {
        self.offset = offset
        self.ratio = ratio
        self.inverted = inverted
    }
}

public enum EncoderDetectionFailure: Error, Equatable {
    /// 命令发送失败，或等待期限内没有收到 COMM_DETECT_ENCODER 返回包。
    case noResponse
    /// 收到了命令返回包，但不足以包含 Offset、Ratio 和方向。
    case malformedResponse(length: Int)
    /// 固件以 Offset=1001、Ratio=0 表示硬件层没有启用编码器。
    case encoderNotConfigured
    /// 固件返回了完整包，但数值无效。
    case invalidValues(offset: Double, ratio: Double)
}

// MARK: - FirmwareUploadHost

extension Client {
    public func uploadSendVesc(_ payload: [UInt8], expect: Int, retries: Int) -> [UInt8]? {
        requestVesc(payload, expect: expect, retries: retries)
    }

    @discardableResult public func uploadWriteRaw(_ bytes: [UInt8]) -> Bool {
        wireTrace?("TX-RAW", bytes)
        return t.write(bytes)
    }

    public func uploadReadRaw(max: Int) -> [UInt8] {
        t.read(max: max)
    }

    public func uploadNextIAPSequence() -> UInt8 {
        defer { v3IAPSequence &+= 1 }
        return v3IAPSequence
    }

    public var uploadTrace: ((String, [UInt8]) -> Void)? { wireTrace }
}
