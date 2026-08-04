import Foundation
import Combine
import RotorKit

/// 电机与应用参数表的读写，以及 FOC 参数辨识。
final class ConfigModel: ObservableObject {
    @Published var mcconf: [String: ParamValue] = [:]
    /// 最近一次从电机实际读取到的配置。与 `mcconf`（包含尚未写入的编辑）分开保存，
    /// 供辨识区域显示“电机当前值 / 新辨识值”。
    @Published var deviceMcconf: [String: ParamValue] = [:]
    @Published var appconf: [String: ParamValue] = [:]
    @Published var deviceSignature: UInt32 = 0
    @Published var deviceAppconfSignature: UInt32 = 0
    @Published var configLoaded = false
    @Published var appConfigLoaded = false
    @Published var configDirty = false
    @Published var appConfigDirty = false
    @Published var configWriting = false
    @Published var configWriteStatus = ""
    /// 设备上报的参数布局签名是否与内置参数表一致。
    ///
    /// `unpack` 只按本地 XML 的顺序逐字段解码，**从不校验设备签名**——表对不上
    /// 时不会报错，会静默解析出垃圾值。把这类值写回电机是能烧东西的，
    /// 所以对不上就整体封锁编辑与写入，而不是让用户对着错位的数字操作。
    @Published var configSchemaTrusted = true
    @Published var deviceSchemaSignatureHex = ""
    @Published var expectedSchemaSignatureHex = ""

    private let session: DeviceSession
    /// 由组合根注入。
    weak var connection: ConnectionModel?
    weak var telemetry: TelemetryModel?

    init(session: DeviceSession) {
        self.session = session
    }

    var params: [Param] { session.activeMotorCodec.order }

    /// 应用配置的参数表。
    ///
    /// 此前界面只硬编码显示了 CAN ID / 状态等级 / 状态速率三项，其余一律看不见——
    /// 而 `can_mode`、`can_baud_rate` 这些**决定电机在总线上是否可见**的开关就在
    /// 里面。排查"电机在 CAN 上完全沉默"时，最该看的值恰好是翻不到的那些。
    var appParams: [Param] { session.appconfCodec.order }

    /// 写应用配置里的任意参数。与 setParam 走同一道闸门。
    func setAppParam(_ name: String, _ value: ParamValue) {
        guard isConfigWritable, appConfigLoaded else { return }
        appconf[name] = value
        appConfigDirty = true
    }

    /// 设备未登记（走兜底档案）——参数只读。
    var isProvisionalDevice: Bool { session.isProvisionalDevice }

    /// 允许编辑与写入的唯一判据。两道闸各挡一类错误：
    /// **签名**保证字段没有错位；**已登记**保证这台电机的量程与特性被确认过。
    /// 签名对得上只说明"表的形状对"，不说明"这些值适合这台电机"。
    var isConfigWritable: Bool { configSchemaTrusted && !isProvisionalDevice }

    /// 不可写时的原因，直接可展示。
    func writeBlockedReason(deviceName: String) -> String {
        if isProvisionalDevice {
            return L10n.t(L10n.Config.unknownDeviceWriteBlocked, deviceName)
        }
        return L10n.t(L10n.Config.schemaMismatchWriteBlocked,
                      deviceSchemaSignatureHex, expectedSchemaSignatureHex)
    }
    var hasPendingConfigurationChanges: Bool { configDirty || appConfigDirty }
    var outputConfigurationHealth: MotorOutputConfigurationHealth {
        MotorOutputConfigurationHealth(values: mcconf)
    }

    // MARK: - 读写

    func loadConfig() {
        session.io.async {
            guard let c = self.session.client else { return }
            let motorConfig = c.getMcconf()
            let appConfig = c.getAppconf()
            DispatchQueue.main.async {
                if let (sig, vals) = motorConfig {
                    let expected = self.session.activeMotorCodec.signature
                    self.deviceSignature = sig
                    self.deviceSchemaSignatureHex = Self.hex(sig)
                    self.expectedSchemaSignatureHex = Self.hex(expected)
                    self.configSchemaTrusted = (sig == expected)
                    self.mcconf = vals
                    self.deviceMcconf = vals
                    self.configLoaded = true
                    self.configDirty = false
                    Log.config(self.configSchemaTrusted
                        ? "mcconf: read \(vals.count) params, signature \(Self.hex(sig)) matches bundled table"
                        : "mcconf: SCHEMA MISMATCH device \(Self.hex(sig)) vs bundled \(Self.hex(expected)) — editing and writing disabled")
                } else {
                    Log.config("mcconf: read failed (no response, or unsupported by this firmware)")
                }
                if let (sig, vals) = appConfig {
                    self.deviceAppconfSignature = sig
                    self.appconf = vals
                    self.appConfigLoaded = true
                    self.appConfigDirty = false
                    // CAN 三项决定这台电机在总线上是否可见，且踩过坑：
                    // 波特率与接收端不一致时症状是"完全沉默"，跟没接线一模一样。
                    let baud = vals["can_baud_rate"]?.intValue
                    Log.config("appconf: read \(vals.count) params, signature \(Self.hex(sig))")
                    Log.config("CAN: id=\(vals["controller_id"]?.intValue ?? -1)"
                        + " status_level=\(vals["send_can_status"]?.intValue ?? -1)"
                        + " rate=\(vals["send_can_status_rate_hz"]?.intValue ?? -1)Hz"
                        + " baud_code=\(baud.map(String.init) ?? "?")"
                        + " (\(Self.canBaudLabel(baud)))"
                        + " mode=\(Self.canModeLabel(vals["can_mode"]?.intValue))"
                        + " uart_permanent=\(vals["permanent_uart_enabled"]?.intValue ?? -1)")
                }
            }
        }
    }

    func writeConfig() {
        let motorSnapshot = mcconf
        let appSnapshot = appconf
        let deviceMotorSnapshot = deviceMcconf
        let writeMotorConfig = configDirty
        let writeAppConfig = appConfigDirty
        let motorCodec = session.activeMotorCodec
        let expectedMotorSignature = deviceSignature
        let expectedAppSignature = deviceAppconfSignature
        let editedMotorNames = Set(motorCodec.changedParameterNames(
            expected: deviceMotorSnapshot, actual: motorSnapshot))
        guard (writeMotorConfig || writeAppConfig), !configWriting else { return }
        guard isConfigWritable else {
            configWriteStatus = writeBlockedReason(
                deviceName: connection?.deviceHardwareName ?? "this device")
            Log.config("write rejected: \(isProvisionalDevice ? "device not registered" : "schema signature mismatch")")
            return
        }
        if writeMotorConfig, !outputConfigurationHealth.isOutputEnabled {
            configWriteStatus = outputDisabledMessage(prefix: L10n.t(L10n.Status.stillAbnormal))
            return
        }
        configWriting = true
        configWriteStatus = L10n.t(L10n.Status.writing)
        session.io.async {
            let motorACK = !writeMotorConfig
                || (self.session.client?.setMcconf(motorSnapshot) ?? false)
            let appACK = !writeAppConfig
                || (self.session.client?.setAppconf(appSnapshot) ?? false)

            // ACK 只表示固件收到了 SET 命令，不代表每个字段都真正保存。
            // 写完立即 GET 回读并逐参数核对，避免把被固件忽略/钳制的字段误报为成功。
            let motorReadback = writeMotorConfig && motorACK
                ? self.readMotorConfigAfterWrite() : nil
            let appReadback = writeAppConfig && appACK
                ? self.readAppConfigAfterWrite() : nil
            // 固件可能在保存整包时归一化未编辑字段。只把用户实际修改、但回读不一致的
            // 字段判为写入失败；否则会出现目标字段已经保存却因旁支字段变化而误报失败。
            let motorMismatches = motorReadback.map {
                motorCodec.changedParameterNames(expected: motorSnapshot, actual: $0.1)
                    .filter { deviceMotorSnapshot.isEmpty || editedMotorNames.contains($0) }
            } ?? []
            let appMismatches = appReadback.map {
                self.session.appconfCodec.changedParameterNames(expected: appSnapshot, actual: $0.1)
            } ?? []
            let motorVerified = !writeMotorConfig || (motorACK
                && motorReadback?.0 == expectedMotorSignature && motorMismatches.isEmpty)
            let appVerified = !writeAppConfig || (appACK
                && appReadback?.0 == expectedAppSignature && appMismatches.isEmpty)
            DispatchQueue.main.async {
                self.configWriting = false
                if let readback = motorReadback {
                    self.deviceMcconf = readback.1
                }
                if motorVerified && appVerified {
                    if writeMotorConfig, self.mcconf == motorSnapshot,
                       let readback = motorReadback {
                        self.mcconf = readback.1
                        self.configDirty = false
                    }
                    if writeAppConfig, self.appconf == appSnapshot,
                       let readback = appReadback {
                        self.appconf = readback.1
                        self.appConfigDirty = false
                    }
                    self.configWriteStatus = L10n.t(L10n.Status.writeSuccess)
                } else {
                    self.configDirty = self.configDirty || writeMotorConfig
                    self.appConfigDirty = self.appConfigDirty || writeAppConfig
                    let rejected = motorMismatches + appMismatches
                    if !rejected.isEmpty {
                        let preview = rejected.prefix(3).joined(separator: "、")
                        let suffix = rejected.count > 3 ? L10n.t(L10n.Status.moreItems, String(rejected.count)) : ""
                        self.configWriteStatus = L10n.t(L10n.Status.readbackMismatch, preview, suffix)
                    } else if (writeMotorConfig && motorACK && motorReadback == nil)
                                || (writeAppConfig && appACK && appReadback == nil) {
                        self.configWriteStatus = L10n.t(L10n.Status.ackButReadbackFailed)
                    } else {
                        self.configWriteStatus = L10n.t(L10n.Status.writeFailedNoAck)
                    }
                }
            }
        }
    }

    /// 旧世代在 SET ACK 后仍可能短暂忙于写 Flash。立即 GET 只等待约 200 ms，
    /// 容易得到假失败；先留出写入时间，再以退避间隔重试。
    private func readMotorConfigAfterWrite() -> (UInt32, [String: ParamValue])? {
        guard let client = session.client else { return nil }
        if client.supports(.immediateConfigReadback) { return client.getMcconf() }
        usleep(350_000)
        for retry in 0..<4 {
            if let result = client.getMcconf() { return result }
            if retry < 3 { usleep(UInt32(250_000 * (retry + 1))) }
        }
        return nil
    }

    private func readAppConfigAfterWrite() -> (UInt32, [String: ParamValue])? {
        guard let client = session.client else { return nil }
        if client.supports(.immediateConfigReadback) { return client.getAppconf() }
        usleep(350_000)
        for retry in 0..<4 {
            if let result = client.getAppconf() { return result }
            if retry < 3 { usleep(UInt32(250_000 * (retry + 1))) }
        }
        return nil
    }

    // MARK: - 编辑

    func setParam(_ name: String, _ value: ParamValue) {
        // 表对不上时改的是错位字段；设备没登记时改的是没确认过量程的字段。
        guard isConfigWritable else { return }
        mcconf[name] = value; configDirty = true
    }

    /// VESC 的 can_baud_rate 是枚举下标，不是波特率数值本身。
    /// 对照表来自上游 CAN_BAUD_x 顺序；接收端与它不一致就一帧也收不到。
    private static func canBaudLabel(_ code: Int?) -> String {
        switch code {
        case 0: return "125 kbit"
        case 1: return "250 kbit"
        case 2: return "500 kbit"
        case 3: return "1 Mbit"
        case 4: return "10 kbit"
        case 5: return "20 kbit"
        case 6: return "50 kbit"
        case 7: return "75 kbit"
        case 8: return "100 kbit"
        default: return "unknown"
        }
    }

    /// can_mode 决定这块控制器在总线上说哪种"语言"。不是 VESC 模式时，
    /// 它照样通电、照样应答 UART，但一帧 VESC 格式的周期帧都不会发——
    /// 在接收端看就是彻底沉默，和没接线一模一样。
    private static func canModeLabel(_ code: Int?) -> String {
        switch code {
        case 0: return "VESC"
        case 1: return "UAVCAN"
        case 2: return "CommBridge"
        default: return "unknown(\(code.map(String.init) ?? "?"))"
        }
    }

    private static func hex(_ v: UInt32) -> String {
        "0x" + String(format: "%08X", v)
    }

    /// 应用配置里的 ID 为准；还没读到配置时退到实时帧里报的那个。
    var canID: Int {
        appconf["controller_id"]?.intValue ?? telemetry?.values.controllerId ?? 0
    }

    func setCANID(_ value: Int) {
        guard appConfigLoaded else { return }
        appconf["controller_id"] = .int(min(max(value, 0), 255))
        appConfigDirty = true
    }

    /// `send_can_status`：决定 CAN 上周期广播哪几组状态帧。
    /// 出厂默认是 1，也就是只发 STATUS_1，后面四组全是关的。
    var canStatusLevel: Int { appconf["send_can_status"]?.intValue ?? 0 }
    var canStatusRateHz: Int { appconf["send_can_status_rate_hz"]?.intValue ?? 0 }

    func setCANStatusLevel(_ value: Int) {
        guard appConfigLoaded else { return }
        appconf["send_can_status"] = .int(min(max(value, 0), CANStatusLevel.maxRawValue))
        appConfigDirty = true
    }

    func setCANStatusRateHz(_ value: Int) {
        guard appConfigLoaded else { return }
        appconf["send_can_status_rate_hz"] = .int(min(max(value, 1), 1_000))
        appConfigDirty = true
    }

    /// 把会把输出限制为零的关键字段恢复为当前设备 XML 的同签名默认值。
    /// 这里只更新待写参数，仍需用户点击“写入电机”。
    func restoreCriticalOutputLimits() {
        let defaults = session.activeMotorCodec.defaults()
        for name in MotorOutputConfigurationHealth(values: mcconf).disabledFields {
            guard let value = defaults[name] else { continue }
            setParam(name, value)
        }
        configWriteStatus = outputConfigurationHealth.isOutputEnabled
            ? L10n.t(L10n.Status.outputLimitsRestored)
            : outputDisabledMessage(prefix: L10n.t(L10n.Status.stillAbnormal))
    }

    /// 断线时清空派生状态，避免上一台设备的读数留在界面上。
    func resetForDisconnect() {
        configLoaded = false
        appConfigLoaded = false
        configWriting = false
        configWriteStatus = ""
    }

    /// 新连接建立时清空辨识结果与待写状态。
    /// 新连接建立时把上一台设备的痕迹清干净。
    ///
    /// 漏清一个字段的后果不是“少显示一点”，而是**把上一台电机的数据当成这台的**。
    /// 实测撞到过：从 V3.4 换到一台 MIT 固件的电机后，参数页在“Config not loaded”
    /// 之下仍然显示着 V3.4 的签名 0x6FE6775A。
    func resetForNewConnection() {
        configSchemaTrusted = true
        deviceSchemaSignatureHex = ""
        expectedSchemaSignatureHex = ""

        mcconf = [:]
        deviceMcconf = [:]
        appconf = [:]
        deviceSignature = 0
        deviceAppconfSignature = 0
        configLoaded = false
        configDirty = false
        appConfigLoaded = false
        appConfigDirty = false
        configWriting = false
        configWriteStatus = ""
    }

    func outputDisabledMessage(prefix: String) -> String {
        let fields = outputConfigurationHealth.disabledFields.joined(separator: "、")
        return "\(prefix): " + L10n.t(L10n.Status.outputDisabledReason, fields)
    }
}
