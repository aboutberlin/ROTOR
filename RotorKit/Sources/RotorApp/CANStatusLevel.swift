import Foundation
import RotorKit

/// `send_can_status` 的取值。它决定电机在 CAN 上周期广播哪几组状态帧。
///
/// 枚举名与官方 `appconf.xml` 中 `send_can_status` 的 `enumNames` 一一对应。
/// 真机实测出厂值是 `1`——只发 STATUS_1，后面四组默认全部关闭。
/// 详见 `hardware-debug/2026-07-31-can-telemetry-expansion.md`。
///
/// **级别是累加的**：选 3 就等于同时开了 STATUS_1、2、3。UI 因此把它画成
/// 五个会连续点亮的格子，而不是一个只看得到当前值的下拉。
enum CANStatusLevel: Int, CaseIterable, Identifiable {
    case status1 = 1
    case status12 = 2
    case status123 = 3
    case status1234 = 4
    case status12345 = 5

    static let disabledRawValue = 0
    static let maxRawValue = 5
    var id: Int { rawValue }

    /// 格子里的短标题：这一级**新增**什么。
    var boxTitle: String {
        switch self {
        case .status1: return L10n.t(L10n.CANStatus.level1Title)
        case .status12: return L10n.t(L10n.CANStatus.level2Title)
        case .status123: return L10n.t(L10n.CANStatus.level3Title)
        case .status1234: return L10n.t(L10n.CANStatus.level4Title)
        case .status12345: return L10n.t(L10n.CANStatus.level5Title)
        }
    }

    /// 该级别新增的那一组帧的完整内容。
    var frameDetail: String {
        switch self {
        case .status1: return L10n.t(L10n.CANStatus.status1Detail)
        case .status12: return L10n.t(L10n.CANStatus.status2Detail)
        case .status123: return L10n.t(L10n.CANStatus.status3Detail)
        case .status1234: return L10n.t(L10n.CANStatus.status4Detail)
        case .status12345: return L10n.t(L10n.CANStatus.status5Detail)
        }
    }

    /// 单个格子的提示：说明选到这一级会得到哪些组。
    var boxTooltip: String {
        let included = CANStatusLevel.allCases
            .filter { $0.rawValue <= rawValue }
            .map { "· \($0.frameDetail)" }
            .joined(separator: "\n")
        let line1 = L10n.t(L10n.CANStatus.boxTooltipLevel, String(rawValue), String(rawValue))
        let line2 = L10n.t(L10n.CANStatus.boxTooltipCumulative)
        let line3 = L10n.t(L10n.CANStatus.boxTooltipWrite)
        return line1 + "\n" + included + "\n\n" + line2 + "\n" + line3
    }

    /// 整行的总说明，由各级别自身描述拼出，避免文案分头维护。
    static var tooltip: String {
        let lines = allCases.map { "\($0.rawValue) starts adding \($0.frameDetail)" }
        let intro = L10n.t(L10n.CANStatus.tooltipIntro)
        let off = L10n.t(L10n.CANStatus.tooltipOff)
        let defaults = L10n.t(L10n.CANStatus.tooltipDefault)
        let note = L10n.t(L10n.CANStatus.tooltipNote)
        return intro + "\n\n" + off + "\n" + lines.joined(separator: "\n") + "\n\n" + defaults + "\n" + note
    }
}
