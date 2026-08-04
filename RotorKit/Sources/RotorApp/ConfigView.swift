import SwiftUI
import RotorKit

struct ConfigView: View {
    @EnvironmentObject var connection: ConnectionModel
    @EnvironmentObject var config: ConfigModel
    @EnvironmentObject var detection: DetectionModel
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !config.configLoaded {
                ContentUnavailableViewCompat(L10n.t(L10n.Config.configNotLoaded), systemImage: "slider.horizontal.3",
                    description: L10n.t(L10n.Config.configLoadedDescription))
            } else if !config.configSchemaTrusted {
                // 参数表与设备对不上时不展示任何数值：那些数字是按错误偏移解出来的，
                // 显示出来只会诱使人去“修正”一个根本不存在的字段。
                ContentUnavailableViewCompat(
                    L10n.t(L10n.Config.schemaMismatchTitle),
                    systemImage: "exclamationmark.triangle.fill",
                    description: L10n.t(L10n.Config.schemaMismatchBody,
                                        config.deviceSchemaSignatureHex,
                                        config.expectedSchemaSignatureHex))
            } else {
                List {
                    if config.isProvisionalDevice {
                        // 只读而不是整块封锁：读取本身是安全的，而且认识一台新电机
                        // 靠的就是先读。挡住的是写入、编辑与辨识。
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.t(L10n.Config.unknownDeviceTitle)).font(.headline)
                                    Text(L10n.t(L10n.Config.unknownDeviceBody,
                                                connection.deviceHardwareName))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    if search.isEmpty {
                        Section(L10n.t(L10n.Config.commonAndDetection)) {
                            OutputConfigurationHealthView()
                            ParameterIdentificationView()
                        }
                        Section(L10n.t(L10n.Config.commonParams)) {
                            ForEach(commonParams, id: \.name) { p in ParamRow(param: p) }
                        }
                    }
                    ForEach(categories, id: \.0) { (cat, params) in
                        Section(cat) {
                            ForEach(params, id: \.name) { p in ParamRow(param: p) }
                        }
                    }
                }.listStyle(.inset)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L10n.t(L10n.Config.searchPlaceholder), text: $search).textFieldStyle(.roundedBorder).frame(width: 240)
            if config.deviceSignature != 0 {
                Text(String(format: L10n.t(L10n.Config.signatureFormat), String(format: "%08X", config.deviceSignature)))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if !config.configWriteStatus.isEmpty {
                Text(config.configWriteStatus)
                    .font(.caption)
                    .foregroundStyle(config.configWriteStatus.localizedCaseInsensitiveContains(L10n.t(L10n.Config.successMarker))
                                     ? .green : config.configWriting ? .orange : .red)
            }
            if config.hasPendingConfigurationChanges {
                Text(L10n.t(L10n.Config.pendingChanges)).font(.caption).foregroundStyle(.orange)
            }
            Button { config.loadConfig() } label: { Label(L10n.t(L10n.Config.refreshConfig), systemImage: "arrow.clockwise") }
                .disabled(!connection.connected || detection.detectionBusy)
            Button { config.writeConfig() } label: { Label(L10n.t(L10n.Config.writeToMotor), systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)
                .disabled(!connection.connected || !config.hasPendingConfigurationChanges
                          || detection.detectionBusy || config.configWriting
                          || !config.isConfigWritable)
        }.padding(12)
    }

    private let commonParamNames = [
        "motor_type", "foc_sensor_mode",
        "l_current_max", "l_current_min", "l_in_current_max", "l_in_current_min",
        "l_current_max_scale", "l_current_min_scale",
        "l_max_erpm", "l_min_erpm",
        "l_max_duty", "l_min_duty", "l_watt_max", "l_watt_min",
        "foc_motor_r", "foc_motor_l", "foc_motor_flux_linkage",
        "foc_current_kp", "foc_current_ki", "foc_observer_gain",
        "foc_encoder_offset", "foc_encoder_ratio",
        "s_pid_kp", "s_pid_ki", "s_pid_kd",
        "p_pid_kp", "p_pid_ki", "p_pid_kd"
    ]
    private let manuallyPromotedParamNames = ["foc_encoder_inverted", "m_invert_direction"]

    private var commonParams: [Param] {
        let byName = Dictionary(uniqueKeysWithValues: config.params.map { ($0.name, $0) })
        return commonParamNames.compactMap { byName[$0] }
    }

    // 按名字前缀分组
    private var categories: [(String, [Param])] {
        let filtered = config.params.filter {
            let matches = search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                || $0.longName.localizedCaseInsensitiveContains(search)
            let alreadyShownAsCommon = search.isEmpty
                && (commonParamNames.contains($0.name)
                    || manuallyPromotedParamNames.contains($0.name))
            return matches && !alreadyShownAsCommon
        }
        var groups: [String: [Param]] = [:]
        for p in filtered { groups[category(p.name), default: []].append(p) }
        return groups.sorted { $0.key < $1.key }
    }

    private func category(_ name: String) -> String {
        if name.hasPrefix("l_") { return L10n.t(L10n.Config.categoryLimits) }
        if name.hasPrefix("foc_") { return L10n.t(L10n.Config.categoryFOC) }
        if name.hasPrefix("si_") { return L10n.t(L10n.Config.categorySetup) }
        if name.hasPrefix("s_pid") || name.hasPrefix("p_pid") { return L10n.t(L10n.Config.categoryPID) }
        if name.hasPrefix("m_") { return L10n.t(L10n.Config.categoryMotor) }
        if name.hasPrefix("cc_") { return L10n.t(L10n.Config.categoryCurrent) }
        if name.hasPrefix("hall_") || name.hasPrefix("bldc_") { return L10n.t(L10n.Config.categoryBLDCHall) }
        return L10n.t(L10n.Config.categoryOther)
    }
}

private struct OutputConfigurationHealthView: View {
    @EnvironmentObject var config: ConfigModel

    var body: some View {
        let health = config.outputConfigurationHealth
        if !health.isOutputEnabled {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(L10n.Config.outputDisabled))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(L10n.t(L10n.Config.abnormalFields, health.disabledFields.joined(separator: L10n.t(L10n.Config.fieldSeparator))))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t(L10n.Config.restoreDefaults)) {
                    config.restoreCriticalOutputLimits()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(10)
            .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ParameterIdentificationView: View {
    @EnvironmentObject var config: ConfigModel
    @EnvironmentObject var detection: DetectionModel
    @State private var fluxCurrent = 5.0
    @State private var fluxERPM = 2000.0
    @State private var fluxDuty = 0.05
    @State private var timeConstantMicroseconds = 500.0
    @State private var encoderCurrent = 10.0
    @State private var pendingConfirmation: DetectionConfirmation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.t(L10n.Config.detectionWarning),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 12) {
                    GroupBox(L10n.t(L10n.Config.motorElectricalParams)) {
                        VStack(alignment: .leading, spacing: 10) {
                            motorResultRow
                            Divider()
                            HStack(spacing: 8) {
                                input(L10n.t(L10n.Config.detectionCurrent), value: $fluxCurrent, unit: "A")
                                input(L10n.t(L10n.Config.openLoopSlope), value: $fluxERPM, unit: "ERPM/s")
                                input(L10n.t(L10n.Config.lowDutyCycle), value: $fluxDuty, unit: "")
                                input(L10n.t(L10n.Config.currentLoopTimeConstant), value: $timeConstantMicroseconds, unit: "µs")
                            }
                            HStack {
                                Button(detectionTitle(.motorRL, idle: L10n.t(L10n.Config.detectRL))) {
                                    pendingConfirmation = .motorRL
                                }
                                .disabled(detection.detectionBusy)
                                Button(detectionTitle(.flux, idle: L10n.t(L10n.Config.detectFluxLinkage))) {
                                    pendingConfirmation = .flux
                                }
                                    .disabled(detection.detectionBusy || detection.motorRLDetection == nil)
                                Spacer()
                                Button(L10n.t(L10n.Config.applyToParams)) {
                                    detection.applyMotorDetection(
                                        timeConstantMicroseconds: timeConstantMicroseconds)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(detection.motorRLDetection == nil)
                            }
                        }
                    }

                    GroupBox(L10n.t(L10n.Config.commonCommSettings)) {
                        VStack(alignment: .leading, spacing: 10) {
                            canIDRow
                            Divider()
                            canStatusRow
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                GroupBox(L10n.t(L10n.Config.encoderParamDetection)) {
                    VStack(alignment: .leading, spacing: 10) {
                        encoderResultRow
                        Divider()
                        directionParameterControls
.help(L10n.t(L10n.Config.encoderInvertedHelp))
                        Divider()
                        input(L10n.t(L10n.Config.detectionCurrent), value: $encoderCurrent, unit: "A")
                        HStack {
                            Button(detectionTitle(.encoder, idle: L10n.t(L10n.Config.startEncoderDetection))) {
                                pendingConfirmation = .encoder
                            }
                            .disabled(detection.detectionBusy)
                            Spacer()
                            Button(L10n.t(L10n.Config.applyToParams)) { detection.applyEncoderDetection() }
                                .buttonStyle(.borderedProminent)
                                .disabled(detection.encoderDetection == nil)
                        }
                    }
                }
                .frame(minWidth: 330)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                if detection.detectionBusy { ProgressView().controlSize(.small) }
                Text(detection.detectionStatus)
                    .font(.caption)
                    .foregroundStyle(detection.detectionBusy ? .orange : .secondary)
                Spacer()
                Text(L10n.t(L10n.Config.detectionHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .disabled(detection.detectionBusy || !config.isConfigWritable)
        .alert(item: $pendingConfirmation) { item in
            switch item {
            case .motorRL:
                return Alert(
                    title: Text(L10n.t(L10n.Config.detectingRL)),
                    message: Text(L10n.t(L10n.Config.detectRLMessage)),
                    primaryButton: .default(Text(L10n.t(L10n.Config.startDetection))) {
                        detection.detectMotorElectricalParameters()
                    },
                    secondaryButton: .cancel())
            case .flux:
                return Alert(
                    title: Text(L10n.t(L10n.Config.detectingFlux)),
                    message: Text(L10n.t(L10n.Config.detectFluxMessage)),
                    primaryButton: .destructive(Text(L10n.t(L10n.Config.confirmAndStart))) {
                        detection.detectMotorFluxLinkage(
                            current: fluxCurrent, minERPM: fluxERPM, lowDuty: fluxDuty)
                    },
                    secondaryButton: .cancel())
            case .encoder:
                return Alert(
                    title: Text(L10n.t(L10n.Config.detectingEncoder)),
                    message: Text(L10n.t(L10n.Config.detectEncoderMessage)),
                    primaryButton: .destructive(Text(L10n.t(L10n.Config.confirmAndStart))) {
                        detection.detectEncoderParameters(current: encoderCurrent)
                    },
                    secondaryButton: .cancel())
            }
        }
    }

    private func detectionTitle(_ kind: ParameterDetectionKind, idle: String) -> String {
        detection.activeDetection == kind ? L10n.t(L10n.Config.detectionInProgress) : idle
    }

    private var canIDBinding: Binding<Int> {
        Binding(get: { config.canID }, set: { config.setCANID($0) })
    }

    private var canIDRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(L10n.Config.canID))
                    .font(.callout.weight(.medium))
                Text(L10n.t(L10n.Config.canIDDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if config.appConfigLoaded {
                TextField("", value: canIDBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Stepper("", value: canIDBinding, in: 0...255)
                    .labelsHidden()
            } else {
                Text(L10n.t(L10n.Config.configNotLoaded2))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
.help(L10n.t(L10n.Config.canIDHelp))
    }

    private var canStatusBinding: Binding<Int> {
        Binding(get: { config.canStatusLevel }, set: { config.setCANStatusLevel($0) })
    }

    private var canStatusRateBinding: Binding<Int> {
        Binding(get: { config.canStatusRateHz }, set: { config.setCANStatusRateHz($0) })
    }

    /// 级别累加，所以第 N 格被选中时，1..N 全部点亮——把“累加”画出来。
    private func canLevelBox(_ level: CANStatusLevel) -> some View {
        let selected = config.canStatusLevel
        let lit = selected >= level.rawValue
        let isEdge = selected == level.rawValue
        return Button {
            config.setCANStatusLevel(level.rawValue)
        } label: {
            VStack(spacing: 2) {
                Text("\(level.rawValue)")
                    .font(.headline)
                    .foregroundStyle(lit ? Color.accentColor : .secondary)
                Text(level.boxTitle)
                    .font(.caption2)
                    .foregroundStyle(lit ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 92, height: 46)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(lit ? Color.accentColor.opacity(0.14) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isEdge ? Color.accentColor : Color.gray.opacity(0.25),
                                  lineWidth: isEdge ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(level.boxTooltip)
    }

    private var canStatusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(L10n.Config.canStatusLevel))
                        .font(.callout.weight(.medium))
                    Text(L10n.t(L10n.Config.canStatusLevelDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !config.appConfigLoaded {
                    Text(L10n.t(L10n.Config.configNotLoaded2))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if config.appConfigLoaded {
                HStack(spacing: 6) {
                    ForEach(CANStatusLevel.allCases) { level in
                        canLevelBox(level)
                    }
                    Button(L10n.t(L10n.Config.disable)) {
                        config.setCANStatusLevel(CANStatusLevel.disabledRawValue)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(config.canStatusLevel == 0 ? Color.orange : .secondary)
                    .padding(.leading, 6)
                    .help(L10n.t(L10n.Config.canStatusLevelDisabledHelp))
                }
            }

            if config.appConfigLoaded {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(L10n.Config.canStatusRate))
                            .font(.callout.weight(.medium))
                        Text(L10n.t(L10n.Config.canStatusRateDescription))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("", value: canStatusRateBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                    Text("Hz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
.help(L10n.t(L10n.Config.canStatusRateHelp))
            }
        }
        .help(CANStatusLevel.tooltip)
    }

    private var motorResultRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.t(L10n.Config.motorReadValue))
                    .foregroundStyle(.secondary)
                Text("/")
                    .foregroundStyle(.secondary)
                Text(L10n.t(L10n.Config.newDetectedValue))
                    .foregroundStyle(.green)
            }
            .font(.caption)

            HStack(spacing: 22) {
                comparisonValue(
                    "R",
                    current: currentMotorParameter("foc_motor_r", scale: 1_000),
                    detected: detection.motorRLDetection.map { $0.resistance * 1_000 },
                    unit: "mΩ", decimals: 3)
                comparisonValue(
                    "L",
                    current: currentMotorParameter("foc_motor_l", scale: 1_000_000),
                    detected: detection.motorRLDetection?.inductanceMicrohenry,
                    unit: "µH", decimals: 2)
                comparisonValue(
                    "λ",
                    current: currentMotorParameter("foc_motor_flux_linkage", scale: 1_000),
                    detected: detection.detectedFluxLinkage.map { $0 * 1_000 },
                    unit: "mWb", decimals: 4)
                if let difference = detection.motorRLDetection?.differenceMicrohenry,
                   difference != 0 {
                    resultValue("Lq−Ld", difference, "µH", decimals: 2)
                }
            }

            if let failure = detection.motorRLDetectionFailure {
                Label(L10n.t(L10n.Config.detectionFailed, failure), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private func currentMotorParameter(_ name: String, scale: Double) -> Double? {
        let values = config.deviceMcconf.isEmpty ? config.mcconf : config.deviceMcconf
        guard let value = values[name]?.doubleValue, value.isFinite else { return nil }
        return value * scale
    }

    private func comparisonValue(
        _ label: String, current: Double?, detected: Double?, unit: String, decimals: Int
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text(current.map { formatted($0, decimals: decimals) } ?? "—")
            if detected != nil {
                Text("/").foregroundStyle(.secondary)
                Text(formatted(detected!, decimals: decimals))
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
            }
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func formatted(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    private var encoderResultRow: some View {
        HStack(spacing: 16) {
            if let result = detection.encoderDetection {
                resultValue("Offset", result.offset, "°", decimals: 2)
                resultValue("Ratio", result.ratio, "", decimals: 2)
                Label(result.inverted ? L10n.t(L10n.Config.reversed) : L10n.t(L10n.Config.forward),
                      systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else if let failure = detection.encoderDetectionFailure {
                Label(L10n.t(L10n.Config.identificationFailed, failure), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.t(L10n.Config.encoderResultHint)).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var directionParameterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            directionControlRow(
                title: L10n.t(L10n.Config.encoderCommutationDirection),
                parameter: "foc_encoder_inverted",
                detail: L10n.t(L10n.Config.encoderCommutationHelp),
                dangerous: true)
            Divider()
            directionControlRow(
                title: L10n.t(L10n.Config.userControlDirection),
                parameter: "m_invert_direction",
                detail: L10n.t(L10n.Config.userControlDirectionHelp),
                dangerous: false)
        }
    }

    private func directionControlRow(
        title: String, parameter: String, detail: String, dangerous: Bool
    ) -> some View {
        let deviceValue = config.deviceMcconf[parameter]?.intValue
        let pendingValue = config.mcconf[parameter]?.intValue
        let binding = Binding<Bool>(
            get: { config.mcconf[parameter]?.intValue != 0 },
            set: { config.setParam(parameter, .int($0 ? 1 : 0)) }
        )
        return Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(L10n.t(L10n.Config.directionState, parameter, deviceValue.map { String($0) } ?? "—", pendingValue.map { String($0) } ?? "—"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(dangerous ? .red : .secondary)
            }
        }
        .disabled(!config.isConfigWritable)
        .toggleStyle(.switch)
        .disabled(config.mcconf[parameter] == nil)
    }

    private func input(_ label: String, value: Binding<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 62)
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resultValue(_ label: String, _ value: Double, _ unit: String,
                             decimals: Int) -> some View {
        HStack(spacing: 3) {
            Text("\(label) \(value.formatted(.number.precision(.fractionLength(decimals))))")
                .monospacedDigit()
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

private enum DetectionConfirmation: String, Identifiable {
    case motorRL, flux, encoder
    var id: String { rawValue }
}

struct ParamRow: View {
    @EnvironmentObject var config: ConfigModel
    let param: Param

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(param.longName.isEmpty ? param.name : param.longName)
                Text(param.name).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            Spacer()
            editor.frame(width: 190)
        }.padding(.vertical, 2)
    }

    @ViewBuilder private var editor: some View {
        editorControl.disabled(!config.isConfigWritable)
    }

    @ViewBuilder private var editorControl: some View {
        switch param.type {
        case CfgT.enum.rawValue:
            Picker("", selection: intBinding) {
                ForEach(Array(param.enumNames.enumerated()), id: \.offset) { i, n in Text(n).tag(i) }
            }.labelsHidden()
        case CfgT.bool.rawValue:
            Toggle("", isOn: Binding(get: { intBinding.wrappedValue != 0 },
                                     set: { intBinding.wrappedValue = $0 ? 1 : 0 })).labelsHidden()
        case CfgT.double.rawValue:
            TextField("", value: doubleBinding, format: .number).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
        default:
            TextField("", value: intBinding, format: .number).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
        }
    }

    private var intBinding: Binding<Int> {
        Binding(get: { config.mcconf[param.name]?.intValue ?? 0 },
                set: { config.setParam(param.name, .int($0)) })
    }
    private var doubleBinding: Binding<Double> {
        Binding(get: { config.mcconf[param.name]?.doubleValue ?? 0 },
                set: { config.setParam(param.name, .double($0)) })
    }
}
