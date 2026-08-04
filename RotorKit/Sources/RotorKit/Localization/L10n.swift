import Foundation

/// 本地化查找。英文不查表，直接用 key 内嵌的原文，因此英文永远可用。
///
/// 翻译文件**不是 SPM 资源**，而是 `.app/Contents/Resources/<lang>.lproj/` 下的独立文件。
/// 这样"发布时裁掉某语言"退化成一次文件拷贝决策，而不必去动编译产物——
/// 不拷贝就是不存在，二进制里搜不到那门语言的一个字。
public enum L10n {
    public enum Language: String, CaseIterable, Identifiable, Sendable {
        case english = "en"
        case simplifiedChinese = "zh-Hans"

        public var id: String { rawValue }

        /// 用该语言自身书写。语言菜单里不该出现"简体中文 (Simplified Chinese)"这种译名——
        /// 看不懂当前界面语言的人，正是要靠这一项找到自己的语言。
        public var displayName: String {
            switch self {
            case .english: return "English"
            case .simplifiedChinese: return "简体中文"
            }
        }
    }

    private static let defaultsKey = "RotorPreferredLanguage"
    private static var tables: [Language: [String: String]] = [:]

    public static var language: Language = resolveInitialLanguage() {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        }
    }

    /// 只列出真正找得到翻译文件的语言。发布时裁掉了某语言，
    /// 菜单里就不该还挂着一个选了也没反应的选项。
    public static var availableLanguages: [Language] {
        Language.allCases.filter { $0 == .english || table(for: $0) != nil }
    }

    public static func t(_ key: L10nKey) -> String {
        guard language != .english,
              let table = table(for: language),
              let value = table[key.id],
              !value.isEmpty
        else { return key.en }
        return value
    }

    /// 带参翻译。**参数只接受 `String`，占位符统一是 `%@`。**
    ///
    /// 此前签名是 `CVarArg...` + `String(format:)`，编译器于是放行任何类型：
    /// 把 `Int` 喂给 `%@` 会被当成对象指针解引用，直接段错误。真机上表现为
    /// “一点连接就崩”，而模拟器分支不走那行，测试永远是绿的。
    /// 现在类型由编译器兜住，且不再经过 `String(format:)`——这类崩溃在结构上
    /// 不可能再发生。需要小数位数请在调用点自己格式化，格式属于值不属于译文。
    public static func t(_ key: L10nKey, _ args: String...) -> String {
        var out = t(key)
        for arg in args {
            guard let r = out.range(of: "%@") else { break }
            out.replaceSubrange(r, with: arg)
        }
        // `%%` 是字面百分号的转义（"Writing firmware… 42%"）。在替换完占位符之后
        // 才还原，避免参数自身带的 % 被二次处理。
        return out.replacingOccurrences(of: "%%", with: "%")
    }

    /// 供 kitcheck 校验译文占位符用；正常代码路径不该直接读表。
    public static func translationTableForTesting(_ language: Language) -> [String: String]? {
        table(for: language)
    }

    /// 测试和语言切换后清缓存。
    public static func resetCache() { tables.removeAll() }

    /// 搜索顺序：`.app` 的 Resources（正式产物）→ 环境变量（开发与 CLI）。
    private static func searchRoots() -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        if let override = ProcessInfo.processInfo.environment["CUBEMARS_L10N_PATH"] {
            roots.append(URL(fileURLWithPath: override))
        }
        return roots
    }

    private static func table(for language: Language) -> [String: String]? {
        if let cached = tables[language] { return cached }
        for root in searchRoots() {
            let url = root.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")
            guard let dict = NSDictionary(contentsOf: url) as? [String: String] else { continue }
            tables[language] = dict
            return dict
        }
        return nil
    }

    private static func resolveInitialLanguage() -> Language {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey),
           let language = Language(rawValue: saved) {
            return language
        }
        for code in Locale.preferredLanguages {
            if code.hasPrefix("zh") { return .simplifiedChinese }
            if code.hasPrefix("en") { return .english }
        }
        return .english
    }
}
