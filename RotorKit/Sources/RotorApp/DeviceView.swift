import SwiftUI
import RotorKit

/// 设备页：把"工具凭什么这样对待这台电机"摊开。
///
/// 握手只交出一个硬件字符串，之后**三个旋钮**决定了一切行为——用哪条档案、
/// 用哪张参数表、固件怎么传。这三件事各自独立，正是为了应付不同厂商在
/// 同一套 VESC 协议上各改各的。把它们并排显示，插上一台陌生电机时
/// 就能一眼看出：哪些是确证的，哪些是推出来的，还差什么。
struct DeviceView: View {
    @EnvironmentObject var connection: ConnectionModel
    @EnvironmentObject var config: ConfigModel
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let report = DeviceReport.make(session: model.session,
                                              connection: connection, config: config) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        identityCard(report)
                        knobCard(report)
                        if report.needsPromotion { promotionCard }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableViewCompat(
                    L10n.t(L10n.Device.notConnected),
                    systemImage: "cpu",
                    description: L10n.t(L10n.Device.notConnectedDetail))
            }
        }
    }

    // MARK: - 身份：唯一由设备直接告知的事实

    private func identityCard(_ r: DeviceReport) -> some View {
        card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.hardwareName.isEmpty ? "—" : r.hardwareName)
                    .font(.system(.title3, design: .monospaced)).bold()
                badge(r.profileIsProvisional ? .inferred : .confirmed)
                Spacer()
            }
            Text(r.firmwareText).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                fact(L10n.t(L10n.Device.link), r.linkSummary)
                fact(L10n.t(L10n.Device.telemetryLayout), r.telemetryLayout)
                fact(L10n.t(L10n.Control.firmwareMode), r.modeTitle)
            }
            Text(L10n.t(L10n.Device.identityDetail))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - 三个旋钮

    private func knobCard(_ r: DeviceReport) -> some View {
        card {
            knob(title: L10n.t(L10n.Device.profile),
                 value: r.profileID,
                 state: r.profileState,
                 detail: r.profileIsProvisional
                     ? L10n.t(L10n.Device.profileDetailProvisional)
                     : L10n.t(L10n.Device.profileDetailRegistered))
            Divider()
            knob(title: L10n.t(L10n.Device.schema),
                 value: schemaValue(r),
                 state: r.schemaState,
                 detail: schemaDetail(r))
            Divider()
            knob(title: L10n.t(L10n.Device.upload),
                 value: r.uploadStrategyName,
                 state: r.profileState,
                 detail: L10n.t(L10n.Device.uploadDetail))
            Divider()
            knob(title: L10n.t(L10n.Device.capabilities),
                 value: r.capabilities.isEmpty
                     ? L10n.t(L10n.Device.capabilitiesNone)
                     : r.capabilities.joined(separator: ", "),
                 state: r.profileState,
                 detail: L10n.t(L10n.Device.capabilitiesDetail))
        }
    }

    private func schemaValue(_ r: DeviceReport) -> String {
        switch r.schemaState {
        case .confirmed:
            return "\(r.schemaName) · \(r.parameterCount) · \(r.deviceSignatureHex)"
        case .blocked:
            return "\(r.deviceSignatureHex) ≠ \(r.expectedSignatureHex)"
        default:
            return r.schemaName
        }
    }

    private func schemaDetail(_ r: DeviceReport) -> String {
        switch r.schemaState {
        case .confirmed: return L10n.t(L10n.Device.schemaDetailMatch)
        case .blocked: return L10n.t(L10n.Device.schemaDetailMismatch)
        default: return L10n.t(L10n.Device.schemaDetailUnread)
        }
    }

    // MARK: - 还差什么

    private var promotionCard: some View {
        card {
            Label(L10n.t(L10n.Device.whatIsMissing), systemImage: "list.bullet.clipboard")
                .font(.headline)
            Text(L10n.t(L10n.Device.whatIsMissingDetail))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 零件

    private func knob(title: String, value: String,
                      state: DeviceReport.State, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.subheadline).bold()
                badge(state)
                Spacer()
                Text(value)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(state == .blocked ? Color.orange : .primary)
                    .textSelection(.enabled)
            }
            Text(detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced))
        }
    }

    private func badge(_ state: DeviceReport.State) -> some View {
        let (text, tint): (String, Color) = {
            switch state {
            case .confirmed: return (L10n.t(L10n.Device.stateConfirmed), .green)
            case .inferred: return (L10n.t(L10n.Device.stateInferred), .orange)
            case .blocked: return (L10n.t(L10n.Device.stateBlocked), .red)
            case .unknown: return (L10n.t(L10n.Device.stateUnknown), .secondary)
            }
        }()
        return Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
