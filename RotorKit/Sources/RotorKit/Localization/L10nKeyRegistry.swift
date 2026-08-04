import Foundation

/// 所有 key 的集中登记处。
///
/// 完整性测试遍历它来查漏翻和孤儿 key，所以**新增一屏就必须在这里挂上**，
/// 否则那一屏漏翻不会被任何测试发现。这是刻意的手工步骤：
/// Swift 没有可靠的编译期自动注册，与其搞运行时反射，不如让遗漏在
/// code review 里看得见。
public enum L10nKeyRegistry {
    public static let all: [L10nKey] =
        L10n.Tab.all
        + L10n.CANStatus.all
        + L10n.Connection.all
        + L10n.Control.all
        + L10n.Config.all
        + L10n.Dashboard.all
        + L10n.Device.all
        + L10n.Firmware.all
        + L10n.FirmwareCatalog.all
        + L10n.SerialPorts.all
        + L10n.Status.all
}
