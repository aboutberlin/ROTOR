import Foundation

/// 实时遥测帧的布局。世代之间只差尾部字段，不是两套结构。
public enum TelemetryLayout: String, Sendable {
    /// 旧世代 VESC 布局。
    case vesc
    /// V3，含末尾可选的外置编码器角度（85 字节）。
    case v3WithOuterEncoder
    /// V3，无外置编码器角度（81 字节）。
    case v3
}

/// 一款设备的完整描述。
///
/// **不按"三种设备"建模，按能力轴建模。** V3.2 与 V3.4 共享封帧、命令映射
/// 和上传策略，只在遥测布局与 MIT 能力上不同——如果按设备各写一个大类，
/// 那些共同部分就要抄三遍，而抄出来的三份会慢慢长歪。
///
/// 加一款新设备 = 在 `DeviceRegistry` 里加一条本结构，不改任何既有代码路径。
public struct DeviceProfile: Sendable {
    /// 稳定标识，用于日志与测试，不展示给用户。
    public let id: String
    public let displayName: String
    public let wireProtocol: RotorWireProtocol
    public let telemetryLayout: TelemetryLayout
    public let configSchema: ConfigSchema
    /// 这条档案是"暂定"的——设备没在注册表里登记，属性全是按协议族猜的。
    ///
    /// 猜对了协议族不等于猜对了这台电机：极对数、减速比、电流上限、编码器类型
    /// 都可能不同。**暂定档案一律只读**，因为参数写错是能烧电机的，而"能读"
    /// 已经足够用来认识一台新电机。
    public let isProvisional: Bool
    public let capabilities: Set<Capability>
    /// 固件上传策略的构造器。用闭包而不是存实例，是因为策略是值类型且
    /// 每次上传应当从干净状态开始。
    public let makeUploadStrategy: @Sendable () -> FirmwareUploadStrategy
    /// 依据握手回包判断这条档案是否适用。
    public let matches: @Sendable (_ identity: DeviceIdentity) -> Bool

    public init(
        id: String,
        displayName: String,
        wireProtocol: RotorWireProtocol,
        telemetryLayout: TelemetryLayout,
        configSchema: ConfigSchema,
        isProvisional: Bool = false,
        capabilities: Set<Capability>,
        makeUploadStrategy: @escaping @Sendable () -> FirmwareUploadStrategy,
        matches: @escaping @Sendable (DeviceIdentity) -> Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.wireProtocol = wireProtocol
        self.telemetryLayout = telemetryLayout
        self.configSchema = configSchema
        self.isProvisional = isProvisional
        self.capabilities = capabilities
        self.makeUploadStrategy = makeUploadStrategy
        self.matches = matches
    }

    public func supports(_ capability: Capability) -> Bool {
        capabilities.contains(capability)
    }
}

/// 握手拿到的设备身份，用于匹配档案。
public struct DeviceIdentity: Equatable, Sendable {
    /// 硬件字符串，例如 `CMESC_AK80_9_SW_V3.4`。
    public let hardwareName: String
    /// 底层固件版本。注意这是 VESC 基线版本，**不是**硬件字符串里的世代号——
    /// V3.2 升到 V3.4 之后这个数字不变，据它判断新旧会得到错误结论。
    public let firmwareMajor: Int
    public let firmwareMinor: Int
    public let wireProtocol: RotorWireProtocol

    public init(hardwareName: String, firmwareMajor: Int,
                firmwareMinor: Int, wireProtocol: RotorWireProtocol) {
        self.hardwareName = hardwareName
        self.firmwareMajor = firmwareMajor
        self.firmwareMinor = firmwareMinor
        self.wireProtocol = wireProtocol
    }
}
