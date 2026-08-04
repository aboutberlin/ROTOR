import Foundation
import Combine
import RotorKit

/// 实时值与历史曲线。
///
/// 采样约 6.7 Hz，保留两分钟以上，供曲线选择最长 120 s 窗口。
final class TelemetryModel: ObservableObject {
    @Published var values = MotorValues()
    @Published var history: [Sample] = []

    let historyLimit = 900

    /// 连续这么多次读不到实时值就判定链路已死。
    ///
    /// 轮询 0.15 s 一次，每次读失败还要耗掉传输层超时，所以 8 次大约是两三秒——
    /// 足够跨过一次慢配置写入，又不至于让"电机已断电"这件事拖上几十秒。
    /// 数的是**失败次数**而不是"多久没成功"：串口忙时是没机会发起读取，
    /// 不是读取失败，按时间判会误杀。
    private let failureLimitBeforeLinkLost = 8

    /// 链路判定为已死时调用。由组合根接到 ConnectionModel。
    var onLinkLost: (() -> Void)?

    private let session: DeviceSession
    private var pollTimer: Timer?
    private var sampleIndex = 0
    private var startTime = Date()
    private var consecutiveReadFailures = 0

    init(session: DeviceSession) {
        self.session = session
    }

    /// 新连接建立时清空曲线，否则上一台设备的历史会接在新设备前面。
    func reset() {
        history = []
        sampleIndex = 0
        startTime = Date()
        values = MotorValues()
        consecutiveReadFailures = 0
    }

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.refreshValues()
        }
    }

    /// 参数辨识、固件升级、模式切换期间必须停轮询——那些流程要独占串口。
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        consecutiveReadFailures = 0
    }

    func refreshValues() {
        session.io.async {
            guard let c = self.session.client else { return }
            guard let v = c.getValues() else {
                // 读失败不能静默吞掉。电机断电后固件不再回应，若只是 return，
                // 界面会一直显示 Connected 且数值停在断电瞬间，而 client 还
                // 攥着串口不放（TIOCEXCL 独占）——换上新电机也连不上。
                DispatchQueue.main.async {
                    self.consecutiveReadFailures += 1
                    if self.consecutiveReadFailures >= self.failureLimitBeforeLinkLost {
                        Log.conn("link lost: \(self.consecutiveReadFailures) consecutive telemetry read failures")
                        self.stopPolling()
                        self.onLinkLost?()
                    }
                }
                return
            }
            DispatchQueue.main.async {
                self.consecutiveReadFailures = 0
                self.values = v
                self.sampleIndex += 1
                let t = Date().timeIntervalSince(self.startTime)
                self.history.append(Sample(id: self.sampleIndex, t: t,
                    rpm: v.rpm, iq: v.iqCurr, currentIn: v.currentIn,
                    vIn: v.vIn, tempFet: v.tempFet, tempMotor: v.tempMotor, duty: v.duty))
                if self.history.count > self.historyLimit {
                    self.history.removeFirst(self.history.count - self.historyLimit)
                }
            }
        }
    }
}

/// 一条实时采样（供曲线）。
struct Sample: Identifiable {
    let id: Int
    let t: Double
    let rpm, iq, currentIn, vIn, tempFet, tempMotor, duty: Double
}
