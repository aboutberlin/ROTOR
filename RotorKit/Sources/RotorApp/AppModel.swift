import Foundation
import Combine
import RotorKit

/// 组合根：持有五个职责模型与它们共享的链路，并把跨模型的因果接起来。
///
/// **本类不存业务状态。** 拆分前所有状态都堆在这里，`connect()` 顺手清曲线、
/// 重读配置、复位固件进度——一个方法同时是四个职责的实现，改哪一处都要
/// 通读一千行。现在因果写在这里，实现留在各自模型里。
///
/// 界面不订阅本类，而是分别订阅需要的子模型（见 `RotorApp`）。macOS 13 上
/// 嵌套的 `ObservableObject` 不会向外传播变更，各视图直接观察自己用的那个，
/// 顺带避免了任意一次遥测刷新导致整个界面重绘。
final class AppModel: ObservableObject {
    let session = DeviceSession()

    let connection: ConnectionModel
    let telemetry: TelemetryModel
    let config: ConfigModel
    let detection: DetectionModel
    let firmware: FirmwareModel
    let control: ControlModel

    init() {
        connection = ConnectionModel(session: session)
        telemetry = TelemetryModel(session: session)
        config = ConfigModel(session: session)
        detection = DetectionModel(session: session)
        firmware = FirmwareModel(session: session)
        control = ControlModel(session: session)

        config.connection = connection
        config.telemetry = telemetry

        detection.connection = connection
        detection.telemetry = telemetry
        detection.control = control
        detection.config = config

        control.connection = connection
        control.config = config

        firmware.connection = connection
        firmware.telemetry = telemetry
        firmware.control = control
        firmware.config = config

        connection.stopControlOnIO = { [control] in control.stopControlOnIO(sendStop: true) }
        telemetry.onLinkLost = { [weak self] in self?.connection.markDeviceStoppedResponding() }
        connection.onConnected = { [weak self] mode in self?.handleConnected(mode: mode) }
        connection.onDisconnected = { [weak self] in self?.handleDisconnected() }
        connection.onRecoveryOutcome = { [firmware] outcome in
            firmware.reportRecoveryOutcome(outcome)
        }
    }

    /// 设备是否具备某项能力。**上层判断一律走这里，不要判断协议世代。**
    func supports(_ capability: Capability) -> Bool { session.supports(capability) }

    private func handleConnected(mode: MotorFirmwareMode) {
        telemetry.reset()
        config.resetForNewConnection()
        detection.reset()
        guard mode == .servo else {
            config.configLoaded = false
            return
        }
        telemetry.startPolling()
        if session.client?.supportsConfiguration == true {
            config.loadConfig()
        }
    }

    private func handleDisconnected() {
        telemetry.stopPolling()
        // 必须连数值一起清。断开后瓦片若还显示断电瞬间的 25.0 V / -79.9 ℃，
        // 那是**已经不存在的设备的读数**，和换设备后残留上一台签名是同一类错误。
        telemetry.reset()
        config.resetForDisconnect()
        detection.detectionBusy = false
        detection.activeDetection = nil
        control.controlActive = false
        control.controlStatus = L10n.t(L10n.Status.controlNotSent)
    }
}
