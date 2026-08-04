import SwiftUI
import RotorKit

struct ConnectionBar: View {
    @EnvironmentObject var connection: ConnectionModel
    @EnvironmentObject var telemetry: TelemetryModel
    @EnvironmentObject var l10n: L10nStore

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundStyle(.tint)
                        .font(.title3)
                    Text(verbatim: "Rotor").font(.title3.bold())
                }
                Divider().frame(height: 22)

                Picker("", selection: $connection.simMode) {
                    Text(L10n.Connection.modeReal).tag(false)
                    Text(L10n.Connection.modeDemo).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                .disabled(connection.connected)
                .help(L10n.Connection.modeHelp)

                if !connection.simMode {
                    Picker(L10n.t(L10n.Connection.port), selection: $connection.selectedPort) {
                        ForEach(connection.ports, id: \.self) { port in
                            Text(verbatim: shortName(port)).tag(port)
                        }
                    }
                    .frame(width: 220).disabled(connection.connected)
                    Button { connection.refreshPorts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(connection.connected)
                    .help(L10n.Connection.refreshPorts)
                    // 不写死宽度：标签与控件共享同一个 frame，而"Baud rate"在
                    // 不同语言下长度不同——固定 130 pt 会把 921600 截成 "921…"。
                    // fixedSize 让它按内容取宽，任何语言下都完整。
                    Picker(L10n.t(L10n.Connection.baudRate), selection: $connection.baud) {
                        ForEach(connection.bauds, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    .fixedSize().disabled(connection.connected)
                }

                Spacer()

                // 只发英文的产物里不该出现一个只有一项的语言菜单。
                if l10n.available.count > 1 {
                    Picker("", selection: $l10n.language) {
                        ForEach(l10n.available) { language in
                            Text(verbatim: language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 116)
                    .help(L10n.Connection.languageHelp)
                }

                Button(L10n.t(connectionButtonTitle)) {
                    if connection.phase == .connecting {
                        connection.cancelConnection()
                    } else if connection.connected {
                        connection.disconnect()
                    } else {
                        connection.connect()
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(connection.phase == .connecting ? .orange : nil)
            }

            // 状态独占下面一行，避免长硬件名把连接栏撑成大胶囊。
            HStack(spacing: 7) {
                Circle().fill(phaseColor).frame(width: 8, height: 8)
                    .shadow(color: phaseColor.opacity(0.7), radius: 3)
                Text(verbatim: connection.status)
                    .font(.caption.weight(.semibold))
                if !connection.fwText.isEmpty {
                    Text(verbatim: "·").foregroundStyle(.secondary)
                    Text(verbatim: connection.fwText).font(.caption.monospaced())
                }
                Spacer()
                if connection.connected {
                    statusItem(L10n.t(L10n.Connection.fault), telemetry.values.faultStr,
                               tint: telemetry.values.faultCode == 0 ? .green : .red)
                    Divider().frame(height: 12)
                    statusItem(L10n.t(L10n.Connection.controllerID),
                               "\(telemetry.values.controllerId)")
                    Divider().frame(height: 12)
                    statusItem("VD / VQ",
                               "\(telemetry.values.vD.f(2)) / \(telemetry.values.vQ.f(2)) V")
                }
            }
            .foregroundStyle(phaseText)
            .lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func shortName(_ port: String) -> String {
        port.replacingOccurrences(of: "/dev/cu.", with: "") + " · " + SerialPorts.note(port)
    }

    private var phaseColor: Color {
        switch connection.phase {
        case .connected: return .green
        case .connecting: return .yellow
        case .noResponse: return .orange
        case .idle: return .gray
        }
    }
    private var phaseText: Color { connection.phase == .idle ? .secondary : phaseColor }

    private var connectionButtonTitle: L10nKey {
        if connection.phase == .connecting { return L10n.Connection.stopTrying }
        return connection.connected ? L10n.Connection.disconnect : L10n.Connection.connect
    }

    private func statusItem(_ label: String, _ value: String,
                            tint: Color = .primary) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: label).foregroundStyle(.secondary)
            Text(verbatim: value).font(.caption.monospacedDigit()).foregroundStyle(tint)
        }
        .font(.caption)
        .fixedSize()
    }
}
