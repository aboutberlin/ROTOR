import Foundation

/// 到 stderr 的带时间戳诊断日志。
///
/// `Start Rotor.command` 会把 stdout/stderr 一起 tee 进
/// `$TMPDIR/rotor-logs/rotor-<时间戳>.log`，所以出问题时有完整现场可看，
/// 不必去 Console.app 里翻，也不必让人复述"我点了啥"。
///
/// 只记**决策点**：握手在哪个波特率成功、匹配到哪条档案、参数签名是否对得上、
/// 写入是否通过回读。记流水账会把真正重要的三行淹掉。
///
/// 日志是开发者面向的诊断输出，不走 L10n——它不是界面文案。
enum Log {
    private static let started = Date()
    private static let lock = NSLock()

    static func line(_ tag: String, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        let t = String(format: "%8.3f", Date().timeIntervalSince(started))
        FileHandle.standardError.write("[\(t)] \(tag.padding(toLength: 10, withPad: " ", startingAt: 0)) \(message)\n"
            .data(using: .utf8)!)
    }

    static func conn(_ m: String) { line("conn", m) }
    static func config(_ m: String) { line("config", m) }
    static func firmware(_ m: String) { line("firmware", m) }
    static func detect(_ m: String) { line("detect", m) }
}
