import Foundation
import Combine
import RotorKit

/// 持续控制：恒定指令与正弦扭矩。
///
/// 两者都必须周期重发并夹带 `COMM_ALIVE`——固件收不到心跳会自动停机，
/// 所以“发一次就不管”在真机上表现为电机走一下就停。
final class ControlModel: ObservableObject {
    @Published var controlActive = false
    @Published var controlStatus = L10n.t(L10n.Status.controlNotSent)

    private let session: DeviceSession
    /// 由组合根注入。控制要读连接状态与输出配置，但不该反过来拥有它们。
    weak var connection: ConnectionModel?
    weak var config: ConfigModel?

    private var controlTimer: DispatchSourceTimer?
    private var sineControlTimer: DispatchSourceTimer?
    private var activeControl: ServoControlCommand?
    private var activeSineTorque: SineTorqueControl?

    init(session: DeviceSession) {
        self.session = session
    }

    private var canDrive: Bool {
        connection?.connected == true && connection?.firmwareMode == .servo
    }

    /// 启动或更新持续控制。100 ms 重发目标并附带 COMM_ALIVE，避免固件超时后自动停机。
    func startServoControl(_ command: ServoControlCommand) {
        guard canDrive else {
            controlStatus = L10n.t(L10n.Status.notServoMode)
            return
        }
        guard config?.outputConfigurationHealth.isOutputEnabled == true else {
            controlStatus = config?.outputDisabledMessage(prefix: L10n.t(L10n.Status.stillAbnormal))
                ?? L10n.t(L10n.Status.stillAbnormal)
            return
        }
        session.io.async {
            self.cancelSineControlOnIO()
            self.activeControl = command
            let firstSendOK = self.sendControlOnIO(command)
                && (self.session.client?.alive() ?? false)
            if self.controlTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: self.session.io)
                timer.schedule(deadline: .now() + .milliseconds(100),
                               repeating: .milliseconds(100), leeway: .milliseconds(15))
                timer.setEventHandler { [weak self] in
                    guard let self, let command = self.activeControl,
                          let client = self.session.client else { return }
                    let ok = self.sendControlOnIO(command) && client.alive()
                    if !ok {
                        self.stopControlOnIO(sendStop: false)
                        DispatchQueue.main.async {
                            self.controlActive = false
                            self.controlStatus = L10n.t(L10n.Status.sendFailed)
                        }
                    }
                }
                self.controlTimer = timer
                timer.resume()
            }
            DispatchQueue.main.async {
                if firstSendOK {
                    self.controlActive = true
                    self.controlStatus = L10n.t(L10n.Status.controlActive)
                } else {
                    self.controlActive = false
                    self.controlStatus = L10n.t(L10n.Status.sendFailed)
                }
            }
        }
    }

    /// 以 100 Hz 生成对称正弦 Iq 指令。AK80-9 输出轴扭矩常数为 0.5701 Nm/A。
    func startSineTorque(amplitudeNm: Double, frequencyHz: Double) {
        guard canDrive else {
            controlStatus = L10n.t(L10n.Status.notServoMode)
            return
        }
        guard config?.outputConfigurationHealth.isOutputEnabled == true else {
            controlStatus = config?.outputDisabledMessage(prefix: L10n.t(L10n.Status.stillAbnormal))
                ?? L10n.t(L10n.Status.stillAbnormal)
            return
        }
        let (amplitude, frequency) = Self.clamp(amplitudeNm: amplitudeNm, frequencyHz: frequencyHz)

        session.io.async {
            self.cancelConstantControlOnIO()
            self.activeSineTorque = SineTorqueControl(
                amplitudeNm: amplitude,
                amplitudeCurrentA: amplitude / SineTorqueControl.torqueConstant,
                frequencyHz: frequency,
                phaseRadians: 0,
                lastTickNanoseconds: DispatchTime.now().uptimeNanoseconds,
                aliveDivider: 0)

            guard let client = self.session.client else { return }
            let firstSendOK = client.servoCurrent(0) && client.alive()
            if self.sineControlTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: self.session.io)
                timer.schedule(deadline: .now() + .milliseconds(10),
                               repeating: .milliseconds(10), leeway: .milliseconds(2))
                timer.setEventHandler { [weak self] in
                    guard let self, var wave = self.activeSineTorque,
                          let client = self.session.client else { return }

                    let now = DispatchTime.now().uptimeNanoseconds
                    let elapsedNanoseconds = now >= wave.lastTickNanoseconds
                        ? now - wave.lastTickNanoseconds : 0
                    let dt = min(Double(elapsedNanoseconds) / 1_000_000_000, 0.1)
                    wave.lastTickNanoseconds = now
                    wave.phaseRadians += 2 * Double.pi * wave.frequencyHz * dt
                    wave.phaseRadians.formTruncatingRemainder(dividingBy: 2 * Double.pi)
                    wave.aliveDivider = (wave.aliveDivider + 1) % 10

                    let iq = wave.amplitudeCurrentA * sin(wave.phaseRadians)
                    var ok = client.servoCurrent(iq)
                    if wave.aliveDivider == 0 {
                        ok = client.alive() && ok
                    }
                    self.activeSineTorque = wave

                    if !ok {
                        self.stopControlOnIO(sendStop: false)
                        DispatchQueue.main.async {
                            self.controlActive = false
                            self.controlStatus = L10n.t(L10n.Status.sendFailed)
                        }
                    }
                }
                self.sineControlTimer = timer
                timer.resume()
            }

            DispatchQueue.main.async {
                if firstSendOK {
                    self.controlActive = true
                    self.controlStatus = L10n.t(L10n.Status.sineTorqueActive)
                } else {
                    self.controlActive = false
                    self.controlStatus = L10n.t(L10n.Status.sendFailed)
                }
            }
        }
    }

    func updateServoControl(_ command: ServoControlCommand) {
        guard controlActive, canDrive else { return }
        session.io.async { self.activeControl = command }
    }

    func updateSineTorque(amplitudeNm: Double, frequencyHz: Double) {
        guard controlActive, canDrive else { return }
        let (amplitude, frequency) = Self.clamp(amplitudeNm: amplitudeNm, frequencyHz: frequencyHz)
        session.io.async {
            guard var wave = self.activeSineTorque else { return }
            wave.amplitudeNm = amplitude
            wave.amplitudeCurrentA = amplitude / SineTorqueControl.torqueConstant
            wave.frequencyHz = frequency
            self.activeSineTorque = wave
        }
    }

    func stop() {
        controlActive = false
        controlStatus = L10n.t(L10n.Status.stopSent)
        session.io.async { self.stopControlOnIO(sendStop: true) }
    }

    /// 断线、辨识、升级、模式切换都要先把控制停干净。
    /// **必须在 `io` 队列上调用**，与正在发送的控制帧串行化。
    func stopControlOnIO(sendStop: Bool) {
        cancelConstantControlOnIO()
        cancelSineControlOnIO()
        if sendStop, let client = session.client {
            _ = client.servoCurrent(0)
            _ = client.servoDuty(0)
            _ = client.alive()
        }
    }

    private static func clamp(amplitudeNm: Double,
                              frequencyHz: Double) -> (amplitude: Double, frequency: Double) {
        let requestedAmplitude = amplitudeNm.isFinite ? abs(amplitudeNm) : 0
        let requestedFrequency = frequencyHz.isFinite
            ? frequencyHz : SineTorqueControl.minFrequencyHz
        return (min(max(requestedAmplitude, 0), SineTorqueControl.maxTorqueNm),
                min(max(requestedFrequency, SineTorqueControl.minFrequencyHz),
                    SineTorqueControl.maxFrequencyHz))
    }

    private func sendControlOnIO(_ command: ServoControlCommand) -> Bool {
        guard let client = session.client else { return false }
        switch command {
        case .duty(let v): return client.servoDuty(v)
        case .current(let v): return client.servoCurrent(v)
        case .rpm(let v): return client.servoRpm(v)
        case .position(let v): return client.servoPos(v)
        case .handbrake(let v): return client.handbrake(v)
        }
    }

    private func cancelConstantControlOnIO() {
        controlTimer?.setEventHandler {}
        controlTimer?.cancel()
        controlTimer = nil
        activeControl = nil
    }

    private func cancelSineControlOnIO() {
        sineControlTimer?.setEventHandler {}
        sineControlTimer?.cancel()
        sineControlTimer = nil
        activeSineTorque = nil
    }
}

enum ServoControlCommand {
    case duty(Double)
    case current(Double)
    case rpm(Double)
    case position(Double)
    case handbrake(Double)
}

private struct SineTorqueControl {
    static let torqueConstant = 0.5701
    static let maxCurrentA = 40.0
    static let maxTorqueNm = maxCurrentA * torqueConstant
    static let minFrequencyHz = 0.05
    static let maxFrequencyHz = 5.0

    var amplitudeNm: Double
    var amplitudeCurrentA: Double
    var frequencyHz: Double
    var phaseRadians: Double
    var lastTickNanoseconds: UInt64
    var aliveDivider: Int
}
