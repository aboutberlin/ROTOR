import SwiftUI
import RotorKit

/// 与实时数据放在同一页的紧凑控制面板。
struct ControlPanelView: View {
    @EnvironmentObject var connection: ConnectionModel
    @EnvironmentObject var control: ControlModel

    enum Mode: String, CaseIterable, Identifiable {
        case duty = "Duty Cycle", current = "Current", rpm = "RPM", position = "Position"
        case handbrake = "Handbrake", sineTorque = "Sine Torque"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .duty: return L10n.t(L10n.Control.modeDutyCycle)
            case .current: return L10n.t(L10n.Control.modeCurrent)
            case .rpm: return L10n.t(L10n.Control.modeRpm)
            case .position: return L10n.t(L10n.Control.modePosition)
            case .handbrake: return L10n.t(L10n.Control.modeHandbrake)
            case .sineTorque: return L10n.t(L10n.Control.modeSineTorque)
            }
        }
        var isAvailable: Bool { self != .position }
        var range: ClosedRange<Double> {
            switch self {
            case .duty: return -1...1
            case .current: return -40...40
            case .rpm: return -30000...30000
            case .position: return 0...360
            case .handbrake: return 0...40
            case .sineTorque: return 0...22.804
            }
        }
        var unit: String {
            switch self {
            case .duty: return ""
            case .current, .handbrake: return L10n.t(L10n.Control.unitAmpere)
            case .rpm: return L10n.t(L10n.Control.unitErpm)
            case .position: return L10n.t(L10n.Control.unitDegree)
            case .sineTorque: return L10n.t(L10n.Control.unitNm)
            }
        }
    }

    @State private var mode: Mode = .rpm
    @State private var target = 0.0
    @State private var sineFrequencyHz = 1.0

    private let torqueConstant = 0.5701
    private let sineFrequencyRange = 0.05...5.0

    var body: some View {
        Card {
            firmwareModeRow
            Divider()
            servoControls
        }
    }

    private var firmwareModeRow: some View {
        HStack(spacing: 10) {
            Text(L10n.Control.firmwareMode).font(.headline).foregroundStyle(.secondary)
            Text(connection.firmwareMode.title)
                .font(.callout.bold())
                .foregroundStyle(firmwareModeColor)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(firmwareModeColor.opacity(0.12), in: Capsule())
            Text(L10n.Control.modeWriteNote)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if connection.modeSwitching {
                ProgressView().controlSize(.small)
                Text(L10n.Control.modeSwitching).font(.callout).foregroundStyle(.orange)
            } else if connection.connected && (connection.firmwareMode == .servo || connection.firmwareMode == .mit) {
                Button {
                    connection.switchFirmwareMode(to: connection.firmwareMode == .servo ? .mit : .servo)
                } label: {
                    Label(L10n.t(L10n.Control.modeSwitchTo, connection.firmwareMode == .servo ? "MIT" : "Servo"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(connection.simMode)
                .help(L10n.Control.modeSwitchWarning)
            }
        }
    }

    private var servoControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(L10n.Control.servoControl)
                modeSelector

                Spacer()

                if mode == .sineTorque {
                    Text(L10n.Control.amplitude).foregroundStyle(.secondary)
                    TextField(L10n.t(L10n.Control.torqueAmplitude), value: $target,
                              format: .number.precision(.fractionLength(0...3)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 86)
                        .onSubmit { send() }
                    Text(L10n.Control.unitNm).foregroundStyle(.secondary)
                    Text(L10n.Control.frequency).foregroundStyle(.secondary)
                    TextField(L10n.t(L10n.Control.frequency), value: $sineFrequencyHz,
                              format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .onSubmit { send() }
                        .onChange(of: sineFrequencyHz) { _ in updateActiveControl() }
                    Text("Hz").foregroundStyle(.secondary)
                } else {
                    TextField(L10n.t(L10n.Control.target), value: $target, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                        .onSubmit { send() }
                    Text(mode.unit)
                        .frame(width: 48, alignment: .leading)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Slider(value: $target, in: mode.range) { editing in
                    if !editing && mode != .sineTorque { send() }
                }
                .onChange(of: target) { _ in updateActiveControl() }

                Button(controlButtonTitle) { send() }
                    .buttonStyle(.borderedProminent)
                    .frame(width: 132)

                Button(role: .destructive) {
                    target = 0
                    control.stop()
                } label: {
                    Label(L10n.t(L10n.Control.eStop), systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            HStack(spacing: 7) {
                Image(systemName: statusIcon)
                Text(control.controlStatus)
                if control.controlActive {
                    if mode == .sineTorque {
                        Text("±\(target.f(2)) Nm · \(sineFrequencyHz.f(2)) Hz · Iq ±\((target / torqueConstant).f(2)) A")
                            .monospacedDigit()
                    } else {
                        Text(L10n.t(L10n.Control.targetDisplay, "\(target.f(mode == .duty ? 2 : 0)) \(mode.unit)"))
                            .monospacedDigit()
                    }
                }
                Spacer()
                Text(controlHelpText)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(control.controlActive ? .green : .secondary)
        }
        .disabled(!connection.connected || connection.firmwareMode != .servo || connection.modeSwitching)
        .overlay(alignment: .center) {
            if connection.connected && connection.firmwareMode == .mit {
                Text(L10n.Control.mitModeNote)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 1) {
            ForEach(Mode.allCases) { candidate in
                Button {
                    selectMode(candidate)
                } label: {
                    Text(verbatim: candidate.displayName)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(candidate.isAvailable ? .primary : .tertiary)
                .background {
                    if mode == candidate {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.38))
                    }
                }
                .disabled(!candidate.isAvailable)
                .help(candidate.isAvailable ? "" : L10n.t(L10n.Control.positionControlUnavailable))
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 650)
    }

    private func selectMode(_ newMode: Mode) {
        guard newMode.isAvailable else { return }
        if control.controlActive { control.stop() }
        mode = newMode
        target = 0
    }

    private var command: ServoControlCommand? {
        let value = min(max(target, mode.range.lowerBound), mode.range.upperBound)
        switch mode {
        case .duty: return .duty(value)
        case .current: return .current(value)
        case .rpm: return .rpm(value)
        case .position: return .position(value)
        case .handbrake: return .handbrake(value)
        case .sineTorque: return nil
        }
    }

    private func send() {
        guard mode.isAvailable else {
            target = 0
            mode = .rpm
            control.stop()
            return
        }
        target = min(max(target, mode.range.lowerBound), mode.range.upperBound)
        if mode == .sineTorque {
            sineFrequencyHz = min(max(sineFrequencyHz, sineFrequencyRange.lowerBound),
                                  sineFrequencyRange.upperBound)
            control.startSineTorque(amplitudeNm: target, frequencyHz: sineFrequencyHz)
        } else if let command {
            control.startServoControl(command)
        }
    }

    private func updateActiveControl() {
        guard control.controlActive else { return }
        if mode == .sineTorque {
            control.updateSineTorque(
                amplitudeNm: min(max(target, mode.range.lowerBound), mode.range.upperBound),
                frequencyHz: min(max(sineFrequencyHz, sineFrequencyRange.lowerBound),
                                 sineFrequencyRange.upperBound))
        } else if let command {
            control.updateServoControl(command)
        }
    }

    private var controlButtonTitle: String {
        if mode == .sineTorque {
            return control.controlActive ? L10n.t(L10n.Control.updateSineTorque) : L10n.t(L10n.Control.startSineTorque)
        }
        return control.controlActive ? L10n.t(L10n.Control.updateCommand) : L10n.t(L10n.Control.startContinuous)
    }

    private var controlHelpText: String {
        if mode == .sineTorque {
            return L10n.t(L10n.Control.frequencyRange)
        }
        return L10n.t(L10n.Control.sliderNote)
    }

    private var firmwareModeColor: Color {
        switch connection.firmwareMode {
        case .servo: return .blue
        case .mit: return .purple
        case .bootloader: return .orange
        case .unknown: return .secondary
        }
    }

    private var statusIcon: String {
        control.controlActive ? "checkmark.circle.fill" : "info.circle"
    }
}
