import SwiftUI
import RotorKit

/// 语言变更的发布者。
///
/// `L10n` 是静态存储，SwiftUI 不会因为它变化而重绘。与其给数百个 `Text`
/// 挂观察者，不如让根视图 `.id(language)` 整体重建——切换语言是低频操作，
/// 重建一次完全可以接受，而代价是零侵入：迁移界面时不必考虑刷新问题。
final class L10nStore: ObservableObject {
    @Published var language: L10n.Language = L10n.language {
        didSet {
            guard language != oldValue else { return }
            L10n.language = language
            L10n.resetCache()
        }
    }

    /// 只有真正打包进产物的语言才会出现在菜单里。
    var available: [L10n.Language] { L10n.availableLanguages }
}

extension Text {
    /// 用 `verbatim` 绕开 SwiftUI 自带的本地化机制——它会去 `Bundle.main`
    /// 按系统语言查找，与本方案的手动 bundle 选择冲突，导致切换语言不生效。
    init(_ key: L10nKey) {
        self.init(verbatim: L10n.t(key))
    }

    /// 与 `L10n.t` 一致：只收 String。此前是 `CVarArg...`，且把可变参数整个
    /// 当一个参数传了下去（`L10n.t(key, arguments)`），本身就是错的。
    init(_ key: L10nKey, _ arguments: String...) {
        self.init(verbatim: arguments.reduce(L10n.t(key)) { acc, arg in
            guard let r = acc.range(of: "%@") else { return acc }
            return acc.replacingCharacters(in: r, with: arg)
        })
    }
}

extension View {
    /// 给控件挂本地化 tooltip。
    func help(_ key: L10nKey) -> some View { help(L10n.t(key)) }
}
