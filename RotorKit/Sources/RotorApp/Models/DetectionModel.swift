import Foundation
import Combine
import RotorKit

/// FOC 参数辨识。
///
/// 单独成模型不是为了让文件短一点：**这是应用里唯一会让电机自己动起来的路径**
/// （磁链与编码器辨识都会旋转转子）。把它与纯读写参数的 `ConfigModel` 分开，
/// 是为了让“会动”与“不会动”在代码结构上就是两回事，加参数编辑功能时不会
/// 顺手碰到会出力的代码。
final class DetectionModel: ObservableObject {
    @Published var detectionBusy = false
    @Published var activeDetection: ParameterDetectionKind?
    @Published var detectionStatus = L10n.t(L10n.Status.detectionNotRun)
    @Published var motorRLDetection: MotorRLDetection?
    @Published var motorRLDetectionFailure: String?
    @Published var detectedFluxLinkage: Double?
    @Published var encoderDetection: EncoderDetection?
    @Published var encoderDetectionFailure: String?

    private let session: DeviceSession
    /// 由组合根注入：辨识要独占串口，必须先停轮询与控制。
    weak var connection: ConnectionModel?
    weak var telemetry: TelemetryModel?
    weak var control: ControlModel?
    weak var config: ConfigModel?

    init(session: DeviceSession) {
        self.session = session
    }

    /// 新连接建立时清空上一台设备的辨识结果。
    func reset() {
        detectionBusy = false
        activeDetection = nil
        detectionStatus = L10n.t(L10n.Status.detectionNotRun)
        motorRLDetection = nil
        motorRLDetectionFailure = nil
        detectedFluxLinkage = nil
        encoderDetection = nil
        encoderDetectionFailure = nil
    }

    // MARK: - FOC 参数辨识

    /// R/L 辨识会给电机注入测试信号，通常只发出声音而不旋转。
    func detectMotorElectricalParameters() {
        guard prepareForDetection(.motorRL, L10n.t(L10n.Status.detectingRl)) else { return }
        motorRLDetection = nil
        motorRLDetectionFailure = nil
        session.io.async {
            self.control?.stopControlOnIO(sendStop: true)
            let outcome = self.session.client?.detectMotorRLDetailed()
                ?? .failure(.noResponse)
            DispatchQueue.main.async {
                switch outcome {
                case .success(let result):
                    self.motorRLDetection = result
                    self.motorRLDetectionFailure = nil
                    self.finishDetection(L10n.t(L10n.Status.rlDetectionComplete))
                case .failure(let failure):
                    self.motorRLDetection = nil
                    self.motorRLDetectionFailure = self.motorRLFailureMessage(failure)
                    self.finishDetection(L10n.t(L10n.Status.rlDetectionFailed, self.motorRLDetectionFailure ?? ""))
                }
            }
        }
    }

    /// 磁链辨识会开环旋转电机。必须由界面明确确认后调用。
    func detectMotorFluxLinkage(current: Double, minERPM: Double, lowDuty: Double) {
        guard let rl = motorRLDetection,
              prepareForDetection(.flux, L10n.t(L10n.Status.detectingFlux)) else { return }
        let safeCurrent = min(max(current, 0), 100)
        let safeERPM = min(max(minERPM, 1), 100_000)
        let safeDuty = min(max(lowDuty, 0.001), 0.95)
        session.io.async {
            self.control?.stopControlOnIO(sendStop: true)
            let result = self.session.client?.detectMotorFluxLinkage(
                current: safeCurrent, minERPM: safeERPM,
                lowDuty: safeDuty, resistance: rl.resistance)
            DispatchQueue.main.async {
                self.detectedFluxLinkage = result
                self.finishDetection(result == nil
                    ? L10n.t(L10n.Status.fluxDetectionFailed)
                    : L10n.t(L10n.Status.fluxDetectionComplete))
            }
        }
    }

    /// 编码器辨识会让电机缓慢旋转。必须由界面明确确认后调用。
    func detectEncoderParameters(current: Double) {
        guard prepareForDetection(
            .encoder, L10n.t(L10n.Status.detectingEncoder)) else { return }
        encoderDetection = nil
        encoderDetectionFailure = nil
        let safeCurrent = min(max(current, 0.1), 100)
        session.io.async {
            self.control?.stopControlOnIO(sendStop: true)
            let outcome = self.session.client?.detectEncoderDetailed(current: safeCurrent)
                ?? .failure(.noResponse)
            DispatchQueue.main.async {
                switch outcome {
                case .success(let result):
                    self.encoderDetection = result
                    self.encoderDetectionFailure = nil
                    self.finishDetection(
                        L10n.t(L10n.Status.encoderDetectionSuccess,
                                result.offset.formatted(.number.precision(.fractionLength(2))),
                                result.ratio.formatted(.number.precision(.fractionLength(2))),
                                result.inverted ? L10n.t(L10n.Status.reversed) : L10n.t(L10n.Status.forward))
                    )
                case .failure(let failure):
                    self.encoderDetection = nil
                    self.encoderDetectionFailure = self.encoderFailureMessage(failure)
                    self.finishDetection(L10n.t(L10n.Status.encoderDetectionFailed, self.encoderDetectionFailure ?? ""))
                }
            }
        }
    }

    /// 只更新页面中的待写参数，不直接写入电机。
    func applyMotorDetection(timeConstantMicroseconds: Double) {
        guard let result = motorRLDetection else { return }
        let inductance = result.inductanceMicrohenry * 1e-6
        setExistingParam("foc_motor_r", .double(result.resistance))
        setExistingParam("foc_motor_l", .double(inductance))
        if result.differenceMicrohenry > 0 {
            setExistingParam("foc_motor_ld_lq_diff",
                             .double(result.differenceMicrohenry * 1e-6))
        }

        let tc = max(timeConstantMicroseconds, 1) * 1e-6
        let bandwidth = 1 / tc
        setExistingParam("foc_current_kp", .double(inductance * bandwidth))
        setExistingParam("foc_current_ki", .double(result.resistance * bandwidth))

        if let flux = detectedFluxLinkage, flux > 0 {
            setExistingParam("foc_motor_flux_linkage", .double(flux))
            setExistingParam("foc_observer_gain", .double(1e3 / (flux * flux)))
        }
        detectionStatus = L10n.t(L10n.Status.motorDetectionApplied)
    }

    /// 只更新页面中的待写参数，不直接写入电机。
    func applyEncoderDetection() {
        guard let result = encoderDetection else { return }
        setExistingParam("foc_encoder_offset", .double(result.offset))
        setExistingParam("foc_encoder_ratio", .double(result.ratio))
        setExistingParam("foc_encoder_inverted", .int(result.inverted ? 1 : 0))
        detectionStatus = L10n.t(L10n.Status.encoderDetectionApplied)
    }

    private func prepareForDetection(_ kind: ParameterDetectionKind, _ message: String) -> Bool {
        guard let config, connection?.connected == true,
              connection?.firmwareMode == .servo,
              config.configLoaded, !detectionBusy else { return false }
        // 参数表对不上就不许起辨识：辨识的产物是要写回参数表的，
        // 而且磁链/编码器辨识会让电机转起来。
        guard config.isConfigWritable else {
            detectionStatus = config.writeBlockedReason(
                deviceName: connection?.deviceHardwareName ?? "this device")
            return false
        }
        // 输出被限制为零时不允许起辨识：磁链与编码器辨识都会转动转子，
        // 在一台“看起来没反应”的电机上反复重试才是真正危险的用法。
        guard config.outputConfigurationHealth.isOutputEnabled else {
            detectionStatus = config.outputDisabledMessage(
                prefix: L10n.t(L10n.Status.cannotStartDetection))
            return false
        }
        detectionBusy = true
        activeDetection = kind
        detectionStatus = message
        control?.controlActive = false
        telemetry?.stopPolling()
        return true
    }

    private func finishDetection(_ message: String) {
        detectionBusy = false
        activeDetection = nil
        detectionStatus = message
        if connection?.connected == true, connection?.firmwareMode == .servo {
            telemetry?.startPolling()
        }
    }

    private func encoderFailureMessage(_ failure: EncoderDetectionFailure) -> String {
        switch failure {
        case .noResponse:
            return L10n.t(L10n.Status.encoderTimeout)
        case .malformedResponse(let length):
            return L10n.t(L10n.Status.malforrmedResponseBytes, String(length))
        case .encoderNotConfigured:
            return L10n.t(L10n.Status.encoderNotConfigured)
        case .invalidValues(let offset, let ratio):
            return L10n.t(L10n.Status.invalidEncoderValues, decimals(offset), decimals(ratio))
        }
    }

    private func motorRLFailureMessage(_ failure: MotorRLDetectionFailure) -> String {
        switch failure {
        case .noResponse:
            return L10n.t(L10n.Status.rlTimeout)
        case .malformedResponse(let length):
            return L10n.t(L10n.Status.malforrmedResponseBytes, String(length))
        case .invalidValues(let resistance, let inductance, let difference):
            return L10n.t(L10n.Status.invalidRlValues, decimals(resistance), decimals(inductance), decimals(difference))
        }
    }

    /// 译文里不带小数位数——格式属于值不属于译文。
    private func decimals(_ v: Double, _ places: Int = 2) -> String {
        String(format: "%.\(places)f", v)
    }

    private func setExistingParam(_ name: String, _ value: ParamValue) {
        guard config?.mcconf[name] != nil else { return }
        config?.setParam(name, value)
    }
}

enum ParameterDetectionKind {
    case motorRL, flux, encoder
}
