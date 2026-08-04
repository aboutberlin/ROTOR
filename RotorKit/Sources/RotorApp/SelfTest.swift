import Foundation
import RotorKit

/// `RotorApp --selftest`：不开窗口，直接驱动组合根跑一遍模拟设备。
///
/// 存在的理由：`AppModel` 与五个子模型住在可执行目标里，`kitcheck` 导入不到，
/// 于是“拆分后行为不变”长期只能靠人肉点界面确认——而人肉确认不留证据。
/// 这里把跨模型的因果做成一条可复现命令：连接成功后遥测必须自己开始滚动、
/// 参数必须自己被读回来。这两件事分别由 `TelemetryModel` 与 `ConfigModel` 完成，
/// 但**触发它们的是组合根**，也正是拆分中最容易接错的那根线。
enum SelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        exit(run() ? 0 : 1)
    }

    private static func run() -> Bool {
        let model = AppModel()
        model.connection.simMode = true
        model.connection.connect()

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if model.connection.connected,
               model.telemetry.history.count >= 3,
               model.config.configLoaded { break }
        }

        var failures: [String] = []
        check(model.connection.connected, "connection established", &failures)
        check(model.connection.firmwareMode == .servo, "identified as Servo mode", &failures)
        check(model.telemetry.history.count >= 3,
              "telemetry started on its own (history=\(model.telemetry.history.count))", &failures)
        check(model.config.configLoaded,
              "config read back on its own (\(model.config.mcconf.count) params)", &failures)
        check(model.config.params.isEmpty == false, "parameter order table is non-empty", &failures)

        // 断开必须把派生状态清干净，否则上一台设备的读数会留在界面上。
        model.connection.disconnect()
        let disconnectDeadline = Date().addingTimeInterval(5)
        while Date() < disconnectDeadline, model.connection.connected {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        check(!model.connection.connected, "disconnect took effect", &failures)
        check(!model.config.configLoaded, "config state reset after disconnect", &failures)
        check(!model.control.controlActive, "control state reset after disconnect", &failures)

        // 换设备时必须把上一台的痕迹清干净：漏清一个字段就等于把上一台电机的
        // 数据当成这台的。真机上撞到过——从 V3.4 换到 MIT 固件那台后，参数页
        // 在“Config not loaded”之下仍显示着 V3.4 的签名。
        let fresh = ConfigModel(session: DeviceSession())
        fresh.mcconf = ["x": .int(1)]
        fresh.deviceMcconf = ["x": .int(1)]
        fresh.appconf = ["y": .int(2)]
        fresh.deviceSignature = 0xDEAD_BEEF
        fresh.deviceAppconfSignature = 0xFEED_FACE
        fresh.configLoaded = true
        fresh.configDirty = true
        fresh.appConfigLoaded = true
        fresh.configSchemaTrusted = false
        fresh.resetForNewConnection()
        var stale: [String] = []
        if !fresh.mcconf.isEmpty { stale.append("mcconf") }
        if !fresh.deviceMcconf.isEmpty { stale.append("deviceMcconf") }
        if !fresh.appconf.isEmpty { stale.append("appconf") }
        if fresh.deviceSignature != 0 { stale.append("deviceSignature") }
        if fresh.deviceAppconfSignature != 0 { stale.append("deviceAppconfSignature") }
        if fresh.configLoaded { stale.append("configLoaded") }
        if fresh.configDirty { stale.append("configDirty") }
        if fresh.appConfigLoaded { stale.append("appConfigLoaded") }
        if !fresh.configSchemaTrusted { stale.append("configSchemaTrusted") }
        check(stale.isEmpty,
              "no stale state from the previous device\(stale.isEmpty ? "" : ": \(stale)")",
              &failures)

        // 未登记设备一律只读。签名对得上只说明"表的形状对"，不说明这些值
        // 适合这台电机——极对数、减速比、电流上限都还没确认过。
        let provisional = DeviceRegistry.genericVesc(for: DeviceIdentity(
            hardwareName: "SOME_NEW_MOTOR", firmwareMajor: 5, firmwareMinor: 1,
            wireProtocol: .vesc))
        check(provisional.isProvisional, "generic fallback profile is marked provisional", &failures)
        check(DeviceRegistry.all.allSatisfy { !$0.isProvisional },
              "every registered profile is non-provisional", &failures)

        if failures.isEmpty {
            print("self-test passed")
            return true
        }
        for failure in failures { print("  ❌ \(failure)") }
        print("\(failures.count) failed")
        return false
    }

    private static func check(_ condition: Bool, _ label: String, _ failures: inout [String]) {
        if condition {
            print("  ✅ \(label)")
        } else {
            failures.append(label)
        }
    }
}
