import Foundation
import RotorKit

/// `RotorApp --acceptance` —— 真机验收。
///
/// 与 `--selftest` 的分工：自检连内置模拟器，只证明组合根的接线对；本命令连
/// **真电机**，证明重构没有改变串口时序与握手行为。模拟器是即答的，真设备
/// 有 Flash 写入延迟、Bootloader 超时、波特率协商——那些才是拆分可能撞坏的东西。
///
/// **本命令不发送任何会让电机产生输出的指令。** 唯一的写入目标是
/// `si_battery_ah`（电池容量），它只用于显示与续航估算，永远不进电流/扭矩回路；
/// 写完立刻回读核对再原值写回。写入前先做一次完整参数备份。
///
///     swift run RotorApp -- --acceptance                 只读：识别 + 遥测 + 读参数
///     swift run RotorApp -- --acceptance --write         额外做一次写入-回读-还原
///     swift run RotorApp -- --acceptance --port /dev/cu.usbserial-XXX --baud 921600
enum Acceptance {
    /// 惰性字段：只影响显示与续航估算，不进控制回路。两套 schema 里都有。
    private static let probeParameter = "si_battery_ah"

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--acceptance") else { return }
        exit(run() ? 0 : 1)
    }

    private static func value(after flag: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: flag),
              i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    private static func run() -> Bool {
        let model = AppModel()
        var report = Report()

        // ── 端口 ──────────────────────────────────────────────
        model.connection.refreshPorts()
        guard let port = value(after: "--port") ?? model.connection.ports.first else {
            print("ERROR: no serial port found. Is the adapter plugged in?")
            return false
        }
        model.connection.simMode = false
        model.connection.selectedPort = port
        if let baud = value(after: "--baud").flatMap(Int.init) {
            model.connection.baud = baud
        }
        print("Port \(port) · starting baud \(model.connection.baud)")
        print(String(repeating: "─", count: 60))

        // ── 1. 连接与识别 ──────────────────────────────────────
        model.connection.connect()
        guard wait(30, model, until: { $0.connection.connected || $0.connection.phase == .noResponse })
                && model.connection.connected else {
            print("FAILED to handshake: \(model.connection.status)")
            print("   Is the GUI still connected? The port is exclusive (TIOCEXCL); only one at a time.")
            return false
        }
        let profile = model.session.client?.profile
        report.hardware = model.connection.deviceHardwareName
        report.firmware = model.connection.fwText
        report.profileID = profile?.id ?? "(none)"
        report.matchedRegistry = profile.map { p in
            DeviceRegistry.all.contains { $0.id == p.id }
        } ?? false

        print("Hardware    \(report.hardware)")
        print("Firmware    \(report.firmware)")
        print("Protocol    \(model.connection.wireProtocol.title) · mode \(model.connection.firmwareMode.title)")
        print("Profile     \(report.profileID)  \(report.matchedRegistry ? "(registered)" : "(UNREGISTERED — generic fallback)")")
        if let p = profile {
            let caps = Capability.allCases.filter { p.supports($0) }.map(\.rawValue)
            print("Capability  \(caps.isEmpty ? "(none)" : caps.joined(separator: ", "))")
            print("Layout      telemetry=\(p.telemetryLayout.rawValue) · config schema=\(p.configSchema.rawValue)")
        }
        print(String(repeating: "─", count: 60))

        // ── 2. 遥测 ────────────────────────────────────────────
        let gotTelemetry = wait(15, model) { $0.telemetry.history.count >= 5 }
        let v = model.telemetry.values
        report.check("telemetry keeps arriving (\(model.telemetry.history.count) frames)", gotTelemetry)
        report.check("bus voltage is plausible (\(fmt(v.vIn)) V)", v.vIn > 5 && v.vIn < 100)
        report.check("FET temperature is plausible (\(fmt(v.tempFet)) C)", v.tempFet > -20 && v.tempFet < 120)
        print("Telemetry   \(fmt(v.vIn)) V · \(fmt(v.tempFet)) C · \(fmt(v.rpm)) ERPM · CAN ID \(v.controllerId)")

        // ── 3. 读参数 ──────────────────────────────────────────
        let gotConfig = wait(20, model) { $0.config.configLoaded && $0.config.appConfigLoaded }
        report.check("motor config read back (\(model.config.mcconf.count) params)",
                     gotConfig && !model.config.mcconf.isEmpty)
        report.check("app config read back (\(model.config.appconf.count) params)",
                     !model.config.appconf.isEmpty)
        report.check("parameter order table matches device schema (\(model.config.params.count) params)",
                     model.config.params.count == model.config.mcconf.count)
        print("Signature   mcconf 0x\(String(model.config.deviceSignature, radix: 16)) · appconf 0x\(String(model.config.deviceAppconfSignature, radix: 16))")
        report.check("parameter table matches this device (schema signature)",
                     model.config.configSchemaTrusted,
                     detail: "device \(model.config.deviceSchemaSignatureHex) vs bundled \(model.config.expectedSchemaSignatureHex)")
        let baudCode = model.config.appconf["can_baud_rate"]?.intValue
        print("CAN         ID \(model.config.canID) · status level \(model.config.canStatusLevel)"
              + " · \(model.config.canStatusRateHz) Hz · baud code \(baudCode.map(String.init) ?? "?")")

        let health = model.config.outputConfigurationHealth
        if !health.isOutputEnabled {
            print("WARNING: output is clamped to zero by: \(health.disabledFields.joined(separator: ", "))")
        }

        // ── 4. 写参数（可选）───────────────────────────────────
        if CommandLine.arguments.contains("--write") {
            print(String(repeating: "─", count: 60))
            runWriteProbe(model, &report)
        } else {
            print("(write probe skipped; pass --write to run it)")
        }

        // ── 5. 断开 ────────────────────────────────────────────
        print(String(repeating: "─", count: 60))
        model.connection.disconnect()
        let closed = wait(10, model) { !$0.connection.connected }
        report.check("disconnect took effect", closed)
        report.check("config state reset after disconnect", !model.config.configLoaded)
        report.check("control state reset after disconnect", !model.control.controlActive)

        return report.summarize()
    }

    /// 备份 → 改一个惰性字段 → 回读核对 → 原值写回 → 再核对。
    ///
    /// ACK 只代表固件收到，不代表存进去了，所以每一步都以**回读**为准。
    private static func runWriteProbe(_ model: AppModel, _ report: inout Report) {
        guard let original = model.config.mcconf[probeParameter] else {
            report.check("inert write target \(probeParameter) exists", false)
            return
        }

        model.firmware.backupFirmwareInfoAndParameters()
        let backedUp = wait(30, model) { !$0.firmware.firmwareBusy }
        report.check("parameter backup completed before writing", backedUp && model.firmware.lastFirmwareBackupURL != nil)
        if let url = model.firmware.lastFirmwareBackupURL {
            print("Backup      \(url.path)")
        }
        guard backedUp else {
            print("Backup did not complete — refusing to write, per project rule.")
            return
        }

        let originalValue = original.doubleValue
        let probeValue = (originalValue + 1).rounded()
        print("Write probe \(probeParameter): \(fmt(originalValue)) -> \(fmt(probeValue))  (inert field, never enters the control loop)")

        report.check("wrote and read back identical (\(fmt(probeValue)))",
                     write(model, probeValue), detail: model.config.configWriteStatus)

        let restored = write(model, originalValue)
        report.check("restored original and read back identical (\(fmt(originalValue)))",
                     restored, detail: model.config.configWriteStatus)
        if !restored {
            print("RESTORE FAILED — \(probeParameter) may still be \(fmt(probeValue)).")
            print("   It only affects the capacity display, never torque; still, set it back to \(fmt(originalValue)) in the GUI.")
        }
    }

    /// 写一个值并以设备回读为准判断成功。
    private static func write(_ model: AppModel, _ value: Double) -> Bool {
        model.config.setParam(probeParameter, .double(value))
        model.config.writeConfig()
        guard wait(30, model, until: { !$0.config.configWriting }) else { return false }
        // 以 deviceMcconf（设备实际回读）为准，不看 ACK，也不看本地编辑副本。
        guard let readback = model.config.deviceMcconf[probeParameter] else { return false }
        return abs(readback.doubleValue - value) < 0.51
    }

    private static func wait(_ seconds: TimeInterval, _ model: AppModel,
                             until done: (AppModel) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if done(model) { return true }
        }
        return done(model)
    }

    private static func fmt(_ d: Double) -> String {
        String(format: "%.2f", d)
    }

    private struct Report {
        var hardware = ""
        var firmware = ""
        var profileID = ""
        var matchedRegistry = false
        private var passed = 0
        private var failures: [String] = []

        mutating func check(_ label: String, _ ok: Bool, detail: String = "") {
            if ok {
                passed += 1
                print("  ✅ \(label)")
            } else {
                failures.append(detail.isEmpty ? label : "\(label) — \(detail)")
                print("  ❌ \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }

        func summarize() -> Bool {
            print(String(repeating: "═", count: 60))
            if failures.isEmpty {
                print("ACCEPTANCE PASSED  \(passed)/\(passed)  —  \(hardware)")
                if !matchedRegistry {
                    print("Note: this device used the generic fallback profile. It works, but to claim")
                    print("      MIT / firmware-upload capability it needs its own DeviceRegistry entry.")
                }
                return true
            }
            print("ACCEPTANCE FAILED  passed \(passed), failed \(failures.count)  —  \(hardware)")
            for f in failures { print("   · \(f)") }
            return false
        }
    }
}
