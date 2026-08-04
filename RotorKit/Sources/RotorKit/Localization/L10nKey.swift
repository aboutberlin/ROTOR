import Foundation

/// 一条可本地化文本。
///
/// 同时持有 key 和英文原文，这是整套方案的地基，带来三个性质：
/// - key 拼错是**编译错误**，而不是界面上冒出 `firmware.start_upgrade`
/// - 任何语言的 `.strings` 缺失、损坏或未被打包进产物时，界面**回落到英文**而不是显示 key
/// - 英文是单一真源，`en.lproj/Localizable.strings` 由它生成，不手工维护
public struct L10nKey: Hashable, Sendable {
    public let id: String
    public let en: String

    public init(_ id: String, _ en: String) {
        self.id = id
        self.en = en
    }
}
