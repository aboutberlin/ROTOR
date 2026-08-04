import Foundation
import AppKit

/// 同一时刻只允许一个 Rotor 在跑。
///
/// 两个实例会互相抢串口：macOS 的 `/dev/cu.*` 默认允许多进程打开，本项目虽然
/// 用 `TIOCEXCL` 独占，但先到的那个拿住端口后，后开的那个只会表现为"握手无
/// 反应"——用户看到的是"连不上电机"，而不是"你开了两个"。更糟的情况是两个
/// 实例各自以为自己在控制电机。
///
/// 用文件锁而不是查进程名：`flock` 由内核维护，进程被 kill -9 也会自动释放，
/// 不会留下需要手工清理的陈旧锁。
enum SingleInstance {
    private static var lockDescriptor: Int32 = -1

    /// 取不到锁就把已有窗口叫到前台，然后退出。
    static func acquireOrExit() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("Rotor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockPath = dir.appendingPathComponent("instance.lock").path

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return }   // 锁不上就放行，不能因为锁本身把工具卡死

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            FileHandle.standardError.write("""
                Rotor is already running.

                Only one instance may run at a time — two would fight over the
                same serial port, and the second one would simply look like
                "the motor is not responding".

                Bringing the existing window to the front.

                """.data(using: .utf8)!)
            activateRunningInstance()
            exit(0)
        }
        lockDescriptor = fd   // 持有到进程结束；退出时内核自动释放
    }

    private static func activateRunningInstance() {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != me
                && ($0.bundleIdentifier == "com.junchengzhou.rotor"
                    || $0.localizedName == "Rotor")
        }
        others.first?.activate(options: [.activateIgnoringOtherApps])
    }
}
