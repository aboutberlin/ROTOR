import Foundation
import RotorKit

/// 工具对当前设备做出的全部判断，摊平成可展示的事实。
///
/// 存在的理由：握手只给出一个硬件字符串，**其余全是推导**——用哪条档案、
/// 用哪张参数表、固件怎么传。以前这些只写在日志里，界面上看不见，于是
/// "为什么参数页是灰的" 这种问题只能靠猜。这里把推导链摊开，并对每一环
/// 标出它是**确证的**还是**推出来的**。
struct DeviceReport {
    enum State { case confirmed, inferred, blocked, unknown }

    var hardwareName = ""
    var firmwareText = ""
    var protocolTitle = ""
    var modeTitle = ""
    var linkSummary = ""

    var profileID = ""
    var profileIsProvisional = false

    var schemaName = ""
    var parameterCount = 0
    var deviceSignatureHex = ""
    var expectedSignatureHex = ""
    var schemaState: State = .unknown

    var uploadStrategyName = ""
    var telemetryLayout = ""
    var capabilities: [String] = []

    var profileState: State { profileIsProvisional ? .inferred : .confirmed }

    /// 未登记，或参数表对不上——两种情况都还不足以放行写入。
    var needsPromotion: Bool { profileIsProvisional || schemaState == .blocked }

    static func make(session: DeviceSession,
                     connection: ConnectionModel,
                     config: ConfigModel) -> DeviceReport? {
        guard connection.connected, let profile = session.client?.profile else { return nil }
        var r = DeviceReport()
        r.hardwareName = connection.deviceHardwareName
        r.firmwareText = connection.fwText
        r.protocolTitle = connection.wireProtocol.title
        r.modeTitle = connection.firmwareMode.title
        r.linkSummary = "\(connection.selectedPort) · \(connection.baud) baud"

        r.profileID = profile.id
        r.profileIsProvisional = profile.isProvisional
        r.telemetryLayout = profile.telemetryLayout.rawValue
        r.schemaName = profile.configSchema.rawValue
        r.uploadStrategyName = profile.makeUploadStrategy().name
        r.capabilities = Capability.allCases
            .filter { profile.supports($0) }
            .map(\.rawValue)
            .sorted()

        r.parameterCount = config.mcconf.count
        r.deviceSignatureHex = config.deviceSchemaSignatureHex
        r.expectedSignatureHex = config.expectedSchemaSignatureHex
        // 没读过参数不等于参数表有问题：MIT 固件根本不开配置通道。
        r.schemaState = !config.configLoaded ? .unknown
            : (config.configSchemaTrusted ? .confirmed : .blocked)
        return r
    }
}
