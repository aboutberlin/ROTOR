import SwiftUI
import Charts
import RotorKit

struct DashboardView: View {
    @EnvironmentObject var connection: ConnectionModel
    @EnvironmentObject var telemetry: TelemetryModel
    @State private var metric: Metric = .rpm
    @AppStorage("chartWindowSeconds") private var chartWindowSeconds = 20
    private let chartWindows = [5, 10, 20, 30, 60, 120]

    /// 未连接时不显示数字。0.0 V 和 25.0 V 一样是"读数"——它会被当成真的
    /// 测量值。没有设备时唯一诚实的显示是"没有值"。
    private func shown(_ text: String) -> String {
        connection.connected ? text : "—"
    }

    var body: some View {
        ScrollView {
            let v = telemetry.values
            HStack(spacing: 8) {
                CompactStatTile(label: L10n.t(L10n.Dashboard.speed), value: shown("\(Int(v.rpm))"), unit: L10n.t(L10n.Dashboard.unitErpm),
                                systemImage: "speedometer", tint: .blue)
                CompactStatTile(label: L10n.t(L10n.Dashboard.voltage), value: shown(v.vIn.f(1)), unit: L10n.t(L10n.Dashboard.unitVolt),
                                systemImage: "bolt.fill", tint: .yellow)
                CompactStatTile(label: L10n.t(L10n.Dashboard.phaseCurrent), value: shown(v.iqCurr.f(2)), unit: L10n.t(L10n.Dashboard.unitAmpere),
                                systemImage: "waveform.path.ecg", tint: .orange,
                                tooltip: L10n.t(L10n.Dashboard.currentFieldTooltip))
                CompactStatTile(label: L10n.t(L10n.Dashboard.busCurrent), value: shown(v.currentIn.f(2)), unit: L10n.t(L10n.Dashboard.unitAmpere),
                                systemImage: "arrow.down.to.line", tint: .orange,
                                tooltip: L10n.t(L10n.Dashboard.currentFieldTooltip))
                CompactStatTile(label: L10n.t(L10n.Dashboard.dutyCycle), value: shown(v.duty.f(2)),
                                systemImage: "percent", tint: .green)
                CompactStatTile(label: L10n.t(L10n.Dashboard.temperatureFet), value: shown(v.tempFet.f(1)), unit: L10n.t(L10n.Dashboard.unitCelsius),
                                systemImage: "thermometer.medium", tint: tempTint(v.tempFet))
                CompactStatTile(label: L10n.t(L10n.Dashboard.temperatureMotor),
                                value: !connection.connected ? "—"
                                    : motorTemperatureAvailable(v.tempMotor)
                                    ? v.tempMotor.f(1) : L10n.t(L10n.Dashboard.temperatureNotConnected),
                                unit: motorTemperatureAvailable(v.tempMotor) ? L10n.t(L10n.Dashboard.unitCelsius) : "",
                                systemImage: "thermometer.medium",
                                tint: motorTemperatureAvailable(v.tempMotor)
                                    ? tempTint(v.tempMotor) : .secondary,
                                tooltip: L10n.t(L10n.Dashboard.temperatureMotorNote))
                CompactStatTile(label: L10n.t(L10n.Dashboard.position), value: shown(v.pidPos.f(1)), unit: L10n.t(L10n.Dashboard.unitDegree),
                                systemImage: "location.north.line", tint: .purple)
            }
            .padding(.bottom, 8)

            ControlPanelView()
            chartCard

            if !connection.connected {
                ContentUnavailableViewCompat(
                    L10n.t(L10n.Dashboard.notConnected),
                    systemImage: "cable.connector",
                    description: L10n.t(L10n.Dashboard.connectionInstructions))
                    .padding(.top, 12)
            }
        }
    }

    private var chartCard: some View {
        Card {
            HStack {
                Text(L10n.Dashboard.liveChart).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(Metric.allCases) { Text(verbatim: $0.displayName).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                Divider().frame(height: 20)
                Text(L10n.Dashboard.window).font(.callout).foregroundStyle(.secondary)
                Picker(L10n.t(L10n.Dashboard.windowLength), selection: $chartWindowSeconds) {
                    ForEach(chartWindows, id: \.self) { seconds in
                        Text(L10n.t(L10n.Dashboard.windowOption, String(seconds))).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 80)
            }
            if telemetry.history.isEmpty {
                Text(L10n.Dashboard.chartEmpty).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let latestTime = telemetry.history.last?.t ?? 0
                let window = Double(chartWindowSeconds)
                let visibleHistory = telemetry.history.filter { $0.t >= latestTime - window }
                Chart(visibleHistory) { s in
                    let relativeTime = s.t - latestTime
                    LineMark(x: .value(L10n.t(L10n.Dashboard.relativeTime), relativeTime),
                             y: .value(metric.displayName, metric.value(s)))
                        .foregroundStyle(metric.tint)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value(L10n.t(L10n.Dashboard.relativeTime), relativeTime),
                             y: .value(metric.displayName, metric.value(s)))
                        .foregroundStyle(.linearGradient(colors: [metric.tint.opacity(0.28), .clear],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                .chartXScale(domain: -window...0)
                .chartXAxisLabel(L10n.t(L10n.Dashboard.chartXAxis))
                .chartYAxisLabel(metric.unit)
                .frame(height: 180)
            }
        }
    }

    private func tempTint(_ t: Double) -> Color { t > 80 ? .red : (t > 60 ? .orange : .teal) }
    private func motorTemperatureAvailable(_ t: Double) -> Bool {
        t.isFinite && t > -80
    }

}

enum Metric: String, CaseIterable, Identifiable {
    case rpm = "Speed", iq = "Phase Current", currentIn = "Bus Current", vIn = "Voltage", tempFet = "Temperature", duty = "Duty Cycle"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .rpm: return L10n.t(L10n.Dashboard.speed)
        case .iq: return L10n.t(L10n.Dashboard.phaseCurrent)
        case .currentIn: return L10n.t(L10n.Dashboard.busCurrent)
        case .vIn: return L10n.t(L10n.Dashboard.voltage)
        case .tempFet: return L10n.t(L10n.Dashboard.temperatureFet)
        case .duty: return L10n.t(L10n.Dashboard.dutyCycle)
        }
    }
    func value(_ s: Sample) -> Double {
        switch self {
        case .rpm: return s.rpm; case .iq: return s.iq; case .currentIn: return s.currentIn
        case .vIn: return s.vIn; case .tempFet: return s.tempFet; case .duty: return s.duty
        }
    }
    var unit: String {
        switch self {
        case .rpm: return L10n.t(L10n.Dashboard.unitErpm); case .iq, .currentIn: return L10n.t(L10n.Dashboard.unitAmpere)
        case .vIn: return L10n.t(L10n.Dashboard.unitVolt); case .tempFet: return L10n.t(L10n.Dashboard.unitCelsius); case .duty: return ""
        }
    }
    var tint: Color {
        switch self {
        case .rpm: return .blue; case .iq: return .orange; case .currentIn: return .pink
        case .vIn: return .yellow; case .tempFet: return .teal; case .duty: return .green
        }
    }
}

/// 兼容旧系统的占位视图
struct ContentUnavailableViewCompat: View {
    let title: String; let systemImage: String; let description: String
    init(_ t: String, systemImage: String, description: String) {
        title = t; self.systemImage = systemImage; self.description = description
    }
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(description).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}
