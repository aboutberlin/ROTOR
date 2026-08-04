import Foundation
import RotorKit

/// 与设备的那条链路本身：串口客户端、串行 IO 队列、参数表编解码器。
///
/// 五个模型都要用到这三样，所以它们住在这里而不是复制五份。**所有设备 IO
/// 都在 `io` 上执行**——串行化即无竞态，这是本工程避免串口交错的唯一手段。
///
/// 本类不是 `ObservableObject`：它承载的是链路，不是界面状态。谁该被观察由
/// 各模型自己决定，避免任意一次 IO 都惊动整个界面重绘。
final class DeviceSession {
    let io = DispatchQueue(label: "rotor.io")

    /// 仅在 `io` 队列上写；主线程只读。
    var client: Client?

    let mcconfCodec: ConfigCodec
    let v3McconfCodec: ConfigCodec
    let appconfCodec: ConfigCodec

    init() {
        let url = Bundle.module.url(forResource: "mcconf", withExtension: "xml")!
        let v3URL = Bundle.module.url(forResource: "mcconf_v3", withExtension: "xml")!
        let appURL = Bundle.module.url(forResource: "appconf", withExtension: "xml")!
        mcconfCodec = ConfigCodec.load(path: url.path)!
        v3McconfCodec = ConfigCodec.load(path: v3URL.path)!
        appconfCodec = ConfigCodec.load(path: appURL.path)!
    }

    /// 设备是否具备某项能力。**上层判断一律走这里，不要判断协议世代**——
    /// 前者加设备不用改，后者每加一款都要回头找齐所有判断点。
    func supports(_ capability: Capability) -> Bool {
        client?.supports(capability) ?? false
    }

    /// 设备未登记（走兜底档案）时，参数一律只读。
    var isProvisionalDevice: Bool { client?.profile.isProvisional ?? false }

    /// 当前设备的配置 schema 对应的编解码器。
    var activeMotorCodec: ConfigCodec {
        (client?.profile.configSchema ?? .vesc) == .v3 ? v3McconfCodec : mcconfCodec
    }
}
