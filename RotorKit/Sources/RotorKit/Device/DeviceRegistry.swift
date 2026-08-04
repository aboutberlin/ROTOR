import Foundation

/// 已知设备档案的登记处。
///
/// **加一款设备就是往 `all` 里加一条数据**，不需要碰 `Client`、不需要碰任何视图。
/// 这是整个模块化的目的：让"支持新硬件"的改动面积收敛到一个文件。
///
/// 匹配不上时退到通用 VESC 档案而不是失败——一台没登记过的 VESC 控制器
/// 仍然能连上、读遥测、读写配置，只是不声称那些需要确证的能力。
/// 认不出来就拒绝服务，对用户毫无价值。
public enum DeviceRegistry {
    public static let all: [DeviceProfile] = [
        ak80_9_v3_4,
        ak80_9_v3_2,
        ak80_9_v2,
    ]

    /// 按登记顺序取第一个匹配的档案；都不匹配则用兜底。
    public static func profile(for identity: DeviceIdentity) -> DeviceProfile {
        all.first { $0.matches(identity) } ?? genericVesc(for: identity)
    }

    // MARK: - 已登记设备

    /// V3.4 起 MIT 五参数控制并入主固件，实时帧去掉了外置编码器角度（81 字节）。
    public static let ak80_9_v3_4 = DeviceProfile(
        id: "ak80-9.v3.4",
        displayName: "AK80-9 V3.4",
        wireProtocol: .v3,
        telemetryLayout: .v3,
        configSchema: .v3,
        capabilities: [
            .mitControl, .immediateConfigReadback, .terminalChannel, .canStatusLevels,
            .iapFirmwareUpload, .applicationSwitching,
            .positionSpeedControl, .parameterDetection,
        ],
        makeUploadStrategy: { IAPRawUpload() },
        matches: { $0.wireProtocol == .v3 && $0.hardwareName.contains("V3.4") }
    )

    /// V3.2 与 V3.4 共享封帧与上传路径；差别是遥测帧多 4 字节，
    /// 且 MIT 控制还在独立应用里，主固件不具备。
    public static let ak80_9_v3_2 = DeviceProfile(
        id: "ak80-9.v3.2",
        displayName: "AK80-9 V3.2",
        wireProtocol: .v3,
        telemetryLayout: .v3WithOuterEncoder,
        configSchema: .v3,
        capabilities: [
            .terminalChannel, .immediateConfigReadback, .canStatusLevels, .iapFirmwareUpload,
            .applicationSwitching, .positionSpeedControl, .parameterDetection,
        ],
        makeUploadStrategy: { IAPRawUpload() },
        matches: { $0.wireProtocol == .v3 && $0.hardwareName.contains("V3.2") }
    )

    /// V2 世代：旧 VESC 封帧，固件走擦除 + 分块的暂存区路径。
    public static let ak80_9_v2 = DeviceProfile(
        id: "ak80-9.v2",
        displayName: "AK80-9 V2",
        wireProtocol: .vesc,
        telemetryLayout: .vesc,
        configSchema: .vesc,
        capabilities: [.parameterDetection, .applicationSwitching],
        makeUploadStrategy: { VescStagingUpload() },
        matches: { $0.wireProtocol == .vesc && $0.hardwareName.contains("AK80_9") }
    )

    // MARK: - 兜底

    /// 未登记设备。只声称由握手本身即可确证的能力。
    public static func genericVesc(for identity: DeviceIdentity) -> DeviceProfile {
        let isV3 = identity.wireProtocol == .v3
        return DeviceProfile(
            id: isV3 ? "generic.v3" : "generic.vesc",
            displayName: identity.hardwareName.isEmpty
                ? "Unknown device" : identity.hardwareName,
            wireProtocol: identity.wireProtocol,
            // 未知 V3 设备按 81 字节解析：解码器接受 81 和 85 两种长度，
            // 按短的解可以读到共有字段；按长的解会把 81 字节的合法回包丢掉。
            telemetryLayout: isV3 ? .v3 : .vesc,
            configSchema: isV3 ? .v3 : .vesc,
            isProvisional: true,
            capabilities: isV3 ? [.iapFirmwareUpload, .parameterDetection, .immediateConfigReadback]
                               : [.parameterDetection],
            makeUploadStrategy: { isV3 ? IAPRawUpload() as FirmwareUploadStrategy
                                        : VescStagingUpload() as FirmwareUploadStrategy },
            matches: { _ in false }   // 兜底只能被显式取用，不参与匹配
        )
    }
}
