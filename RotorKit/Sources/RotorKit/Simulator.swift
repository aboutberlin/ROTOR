import Foundation

/// AK80-9 模拟器：应答 VESC 请求，供无硬件端到端测试。
public final class MotorSimulator {
    public let codec: ConfigCodec
    public let appconfCodec: ConfigCodec?
    public var mcconf: [String: ParamValue]
    public var appconf: [String: ParamValue]
    public var fwMajor = 3, fwMinor = 66
    public var hwName = "60"
    public var controllerId = 0
    public var rpm = 0.0, duty = 0.0, vIn = 48.0, tempFet = 26.5, tempMotor = 24.0, fault = 0
    public var lastSetSignatureOk: Bool? = nil
    public private(set) var firmwareEraseSize: Int?
    public private(set) var firmwareWriteCount = 0
    public private(set) var lastUploadedFirmware: [UInt8]?
    /// lively=true 时给实时数据加入平滑动态（供 App 预览曲线）；默认 false 保证测试确定性。
    public var lively = false
    private var tick = 0

    private let dec = PacketDecoder()
    private var firmwareStaging: [UInt8] = []

    public init(codec: ConfigCodec, appconfCodec: ConfigCodec? = nil) {
        self.codec = codec
        self.appconfCodec = appconfCodec
        self.mcconf = codec.defaults()
        self.appconf = appconfCodec?.defaults() ?? [:]
        self.controllerId = self.appconf["controller_id"]?.intValue ?? 0
    }

    public func feed(_ data: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        for payload in dec.feed(data) {
            if let r = handle(payload) { out.append(Packet.encode(r)) }
        }
        return out
    }

    private func handle(_ payload: [UInt8]) -> [UInt8]? {
        guard let cmd = payload.first.map({ Int($0) }) else { return nil }
        let body = Array(payload.dropFirst())
        switch cmd {
        case Comm.fwVersion.rawValue: return fwVersion()
        case Comm.getValues.rawValue: return getValues()
        case Comm.getMcconf.rawValue: return [UInt8(Comm.getMcconf.rawValue)] + codec.pack(mcconf)
        case Comm.setMcconf.rawValue: return setMcconf(body)
        case Comm.getAppconf.rawValue:
            guard let appconfCodec else { return nil }
            return [UInt8(Comm.getAppconf.rawValue)] + appconfCodec.pack(appconf)
        case Comm.setAppconf.rawValue: return setAppconf(body)
        case Comm.setRpm.rawValue:
            var r = BufReader(body); rpm = Double(r.i32()); return nil
        case Comm.setDuty.rawValue:
            var r = BufReader(body); duty = Double(r.i32()) / 100000; return nil
        case Comm.detectMotorRL.rawValue:
            var w = BufWriter()
            w.u8(Comm.detectMotorRL.rawValue)
            w.f32(0.08583, 1e6)
            w.f32(15.0, 1e3)
            w.f32(1.2, 1e3)
            return w.bytes
        case Comm.detectMotorFluxLinkage.rawValue:
            var w = BufWriter()
            w.u8(Comm.detectMotorFluxLinkage.rawValue)
            w.f32(0.003264, 1e7)
            return w.bytes
        case Comm.detectEncoder.rawValue:
            var w = BufWriter()
            w.u8(Comm.detectEncoder.rawValue)
            w.f32(123.4, 1e6)
            w.f32(9.0, 1e6)
            w.i8(0)
            return w.bytes
        case Comm.eraseNewApp.rawValue:
            guard body.count >= 4 else { return [UInt8(Comm.eraseNewApp.rawValue), 0] }
            var reader = BufReader(body)
            let size = Int(reader.u32())
            guard size > 0, size < 4_000_000 else {
                return [UInt8(Comm.eraseNewApp.rawValue), 0]
            }
            firmwareEraseSize = size
            firmwareWriteCount = 0
            lastUploadedFirmware = nil
            // 线路内容在原始镜像前还有 size + CRC16 共 6 字节。
            firmwareStaging = [UInt8](repeating: 0xFF, count: size + 6)
            return [UInt8(Comm.eraseNewApp.rawValue), 1]
        case Comm.writeNewAppData.rawValue:
            guard body.count >= 5, !firmwareStaging.isEmpty else {
                return [UInt8(Comm.writeNewAppData.rawValue), 0]
            }
            var reader = BufReader(body)
            let offset = Int(reader.u32())
            let bytes = Array(body.dropFirst(4))
            guard offset >= 0, offset + bytes.count <= firmwareStaging.count else {
                return [UInt8(Comm.writeNewAppData.rawValue), 0]
            }
            firmwareStaging.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
            firmwareWriteCount += 1
            var response = BufWriter()
            response.u8(Comm.writeNewAppData.rawValue)
            response.u8(1)
            response.u32(UInt32(offset))
            return response.bytes
        case Comm.jumpToBootloader.rawValue:
            commitStagedFirmwareIfValid()
            hwName = "BOOT_60"; return nil
        case Comm.jumpToCmesc.rawValue:
            hwName = "CMESC_60"; return nil
        case Comm.jumpToMit.rawValue:
            hwName = "MIT_60"; return nil
        default: return nil
        }
    }

    private func commitStagedFirmwareIfValid() {
        guard let expectedSize = firmwareEraseSize,
              firmwareStaging.count >= expectedSize + 6 else { return }
        var reader = BufReader(Array(firmwareStaging.prefix(6)))
        let declaredSize = Int(reader.u32())
        let declaredCRC = UInt16(reader.u16())
        let image = Array(firmwareStaging.dropFirst(6).prefix(expectedSize))
        guard declaredSize == expectedSize, CRC.crc16(image) == declaredCRC else { return }
        lastUploadedFirmware = image
    }

    private func fwVersion() -> [UInt8] {
        var w = BufWriter()
        w.u8(Comm.fwVersion.rawValue); w.u8(fwMajor); w.u8(fwMinor)
        w.raw(Array(hwName.utf8) + [0])
        w.raw((0..<12).map { UInt8($0) })   // 假 UUID
        w.u8(0)                             // pairing
        return w.bytes
    }

    private func getValues() -> [UInt8] {
        tick += 1
        // 活力模式：温度/电流随时间平滑起伏，占空比随转速；vIn 与 rpm 保持精确（测试依赖）。
        let ph = Double(tick)
        let tFet = lively ? 30 + 6 * sin(ph * 0.06) : tempFet
        let tMot = lively ? 28 + 4 * sin(ph * 0.045 + 1) : tempMotor
        let iq   = lively ? (rpm / 600.0 + 1.5 * sin(ph * 0.12)) : 0.0
        let iIn  = lively ? iq * 0.55 : 0.0
        let dutyOut = lively ? max(-1, min(1, rpm / 25000.0 + 0.02 * sin(ph * 0.2))) : duty

        var w = BufWriter()
        w.u8(Comm.getValues.rawValue)
        w.i16(Int((tFet * 10).rounded())); w.i16(Int((tMot * 10).rounded()))
        w.i32(Int((iq * 100).rounded()))   // current_motor
        w.i32(Int((iIn * 100).rounded()))  // current_in
        w.i32(0)                            // id
        w.i32(Int((iq * 100).rounded()))   // iq
        w.i16(Int((dutyOut * 1000).rounded()))
        w.i32(Int(rpm.rounded()))
        w.i16(Int((vIn * 10).rounded()))
        w.i32(0); w.i32(0); w.i32(0); w.i32(0)
        w.i32(0); w.i32(0)
        w.u8(fault)
        w.i32(0)
        w.u8(controllerId)
        let t = Int((tFet * 10).rounded()); w.i16(t); w.i16(t); w.i16(t)
        w.i32(0); w.i32(0)
        return w.bytes
    }

    private func setMcconf(_ body: [UInt8]) -> [UInt8]? {
        var r = BufReader(body); let sig = r.u32()
        if sig != codec.signature { lastSetSignatureOk = false; return nil }
        let (_, values) = codec.unpack(body)
        for (k, v) in values { mcconf[k] = v }
        lastSetSignatureOk = true
        return [UInt8(Comm.setMcconf.rawValue)]
    }

    private func setAppconf(_ body: [UInt8]) -> [UInt8]? {
        guard let appconfCodec else { return nil }
        var r = BufReader(body)
        guard r.u32() == appconfCodec.signature else { return nil }
        let (_, values) = appconfCodec.unpack(body)
        for (key, value) in values { appconf[key] = value }
        controllerId = appconf["controller_id"]?.intValue ?? controllerId
        return [UInt8(Comm.setAppconf.rawValue)]
    }
}
