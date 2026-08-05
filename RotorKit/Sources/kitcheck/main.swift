import CryptoKit
import Foundation
import RotorKit

// 与 Python 核心一致的黄金向量交叉验证（CLT 无 XCTest，用可执行断言）。
var failures = 0
func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { print("  ✅ \(name)") }
    else { print("  ❌ \(name)  \(detail)"); failures += 1 }
}

/// `usleep` 会被 PTY 的 SIGWINCH 等信号提前中断。长时序验证必须
/// 以绝对截止时间为准，否则终端轮询本身会缩短 Bootloader 等待。
func sleepAtLeast(_ seconds: TimeInterval) {
    guard seconds > 0 else { return }
    let whole = floor(seconds)
    var requested = timespec(
        tv_sec: Int(whole),
        tv_nsec: Int((seconds - whole) * 1_000_000_000)
    )
    var remaining = timespec()
    while nanosleep(&requested, &remaining) == -1 && errno == EINTR {
        requested = remaining
    }
}
func bytesFromHex(_ value: String) -> [UInt8] {
    let chars = Array(value)
    return stride(from: 0, to: chars.count, by: 2).compactMap { index in
        guard index + 1 < chars.count else { return nil }
        return UInt8(String(chars[index...index + 1]), radix: 16)
    }
}

/// 按 2026-07-31 真机成功升级抓包建模的 V3 bootloader 设备。
///
/// 刻意复现三个决定成败的真实行为，任何一条被实现忽略都会让测试失败：
/// 1. 未收到 `0x42` 之前，对任何 IAP 原始包**一律不回应**（真机就是这样，
///    官方工具因此把第 0 块重发了 12114 次）；
/// 2. 首包接受初始令牌 `00 00 00 01`，并在 ACK 中下发真正的会话令牌；
/// 3. 此后携带错误令牌的包被忽略且不回 ACK，逼迫实现真正采纳设备令牌。
final class V3FirmwareTransport: Transport {
    private let decoder = RotorV3PacketDecoder()
    private var rx: [UInt8] = []
    private var pending: [UInt8] = []
    private var inBootloader = false
    private var blocks: [Int: [UInt8]] = [:]
    private var expectedNext = 0
    private(set) var controlPacketCount = 0
    private(set) var rejectedTokenPackets = 0
    private(set) var packetsIgnoredBeforeBootloader = 0
    let sessionToken: [UInt8] = [0x00, 0x00, 0x04, 0x05]

    /// 设备实际落盘的内容（按块号顺序拼接）。
    var receivedImage: [UInt8] {
        blocks.keys.sorted().compactMap { blocks[$0] }.flatMap { $0 }
    }

    @discardableResult func write(_ data: [UInt8]) -> Bool {
        // 应用层 AA…BB 帧与 bootloader 的 IAP 原始帧是两条不同的通道。
        if data.first == 0xAA || data.first == 0xAB {
            for payload in decoder.feed(data) {
                guard let command = payload.first else { continue }
                switch Int(command) {
                case RotorV3Comm.fwVersion.rawValue:
                    rx.append(contentsOf: RotorV3Packet.encode(
                        [command, 5, 1, 1] + Array("CMESC_AK80_9_SW_V3.4".utf8) + [0]))
                case RotorV3Comm.jumpToBootloader.rawValue:
                    inBootloader = true
                    rx.append(contentsOf: RotorV3Packet.encode([command]))
                default:
                    break
                }
            }
            return true
        }
        pending.append(contentsOf: data)
        consumeIAPFrames()
        return true
    }

    private func consumeIAPFrames() {
        var i = 0
        while i + 6 <= pending.count {
            guard pending[i] == 0xEC, pending[i + 1] == 0x96 else { i += 1; continue }
            let length = Int(pending[i + 5])
            guard length >= 7, length <= 200 else { i += 1; continue }
            guard i + length <= pending.count else { break } // 帧未收全
            handleIAPFrame(Array(pending[i..<(i + length)]))
            i += length
        }
        if i > 0 { pending.removeFirst(Swift.min(i, pending.count)) }
    }

    private func handleIAPFrame(_ frame: [UInt8]) {
        guard frame.dropLast().reduce(UInt8(0), &+) == frame.last else { return }
        // 真机行为：没进 bootloader 就什么都不回。
        guard inBootloader else {
            packetsIgnoredBeforeBootloader += 1
            return
        }
        switch frame[2] {
        case RotorV3IAP.typeControl:
            controlPacketCount += 1
        case RotorV3IAP.typeData:
            guard frame.count == 144 else { return }
            let token = Array(frame[6..<10])
            let blockIndex = (Int(frame[12]) << 8) | Int(frame[13])
            let tokenOK = token == sessionToken
                || (blocks.isEmpty && token == RotorV3IAP.initialSessionToken)
            guard tokenOK else {
                rejectedTokenPackets += 1
                return // 令牌不对：静默丢弃，不回 ACK
            }
            if blockIndex == expectedNext {
                blocks[blockIndex] = Array(frame[15..<143])
                expectedNext += 1
            }
            var ack: [UInt8] = [
                0x7B, 0x8C, RotorV3IAP.typeDataAck, frame[3], RotorV3IAP.target, 0x0D
            ]
            ack.append(contentsOf: sessionToken)
            ack.append(UInt8(expectedNext >> 8))
            ack.append(UInt8(expectedNext & 0xFF))
            ack.append(ack.reduce(UInt8(0), &+))
            rx.append(contentsOf: ack)
        default:
            break
        }
    }

    func read(max: Int) -> [UInt8] {
        let count = min(max, rx.count)
        let output = Array(rx.prefix(count))
        rx.removeFirst(count)
        return output
    }

    func close() {}
}

if let probeIndex = CommandLine.arguments.firstIndex(of: "--probe"),
   CommandLine.arguments.indices.contains(probeIndex + 1) {
    let port = CommandLine.arguments[probeIndex + 1]
    let baud = CommandLine.arguments.indices.contains(probeIndex + 2)
        ? Int(CommandLine.arguments[probeIndex + 2]) ?? 921600 : 921600
    print("== Read-only hardware probe ==")
    guard let transport = SerialTransport(port: port, baud: baud) else {
        // 端口被别的进程占着时，如果还硬着头皮握手，症状会是“无响应”，
        // 把矛头错误地指向电机。这里必须说清真正的原因。
        if SerialTransport.isPortBusy(port) {
            print("  ❌ \(port) 已被另一个进程独占（多半是 Rotor.app 正连着）")
            print("     先在 App 里点“断开”，或用 lsof \(port) 看是谁占着。")
        } else {
            print("  ❌ 无法打开 \(port)（用 lsof \(port) 确认是否有别的进程在用）")
        }
        exit(2)
    }
    if CommandLine.arguments.contains("--iap-lines-only") {
        guard transport.prepareForBootloaderTimeout() else {
            print("  ❌ 无法设置 1200 7N1 + RTS/DTR")
            exit(54)
        }
        transport.close()
        print("  ✅ 仅恢复官方 IAP 关口线路状态；未发送协议命令")
        exit(0)
    }
    if CommandLine.arguments.contains("--recover-v3-servo") {
        print("  ℹ️ 完整复刻官方 V3 两轮 A1 的 IAP → Servo/APP 序列；不擦除、不写固件")
        let recoveryClient = Client(transport)
        guard recoveryClient.fwVersion() != nil,
              recoveryClient.wireProtocol == .v3 else {
            print("  ❌ 当前设备不是可响应的 V3 UART 应用；未发送 IAP 命令")
            exit(32)
        }
        guard recoveryClient.recoverV3ServoApplication(progress: { round in
            print("  → A1 原始跳转轮次 \(round)/2")
        }) else {
            print("  ❌ 两轮 A1 或最终 0x41 回读失败；未擦除 Flash")
            exit(34)
        }
        print("  ✅ 两轮 A1 与最终 0x41 回读均通过；APP 已恢复")
    }
    if CommandLine.arguments.contains("--force-recover-v3-servo") {
        print("  ℹ️ 设备当前可无应用握手；直接执行官方两轮 A1，未擦除、未写固件")
        guard transport.performV3ApplicationReturn(startingSequence: 0x40, rounds: 2) else {
            print("  ❌ 两轮 A1 原始序列发送失败")
            exit(56)
        }
        let recoveryClient = Client(transport)
        guard let recovered = recoveryClient.fwVersion(),
              recoveryClient.wireProtocol == .v3 else {
            print("  ❌ A1 已发送，但 V3 应用层仍无 0x41 回包")
            exit(57)
        }
        print("  ✅ APP 已恢复：FW \(recovered.major).\(recovered.minor) HW \(recovered.hw)")
    }
    if CommandLine.arguments.contains("--recover-v3-reboot") {
        print("  ℹ️ 发送 V3 IAP 复位命令 0x5E；不擦除、不写固件")
        guard transport.write(RotorV3Packet.encodeCmd(.reboot)) else {
            print("  ❌ 0x5E 未写入串口")
            exit(31)
        }
        print("  ℹ️ 等待 APP 启动…")
        sleepAtLeast(5)
    }
    let v2Codec = ConfigCodec.load(
        path: "../../reverse-engineering/extracted-config/v1/mcconf_150params.xml")
    let v3Codec = ConfigCodec.load(
        path: "../../reverse-engineering/extracted-config/v3/xml_022_off01376270_PWM_Mode.xml")
    let appCodec = ConfigCodec.load(
        path: "../../reverse-engineering/extracted-config/v1/appconf_132params.xml")
    let client = Client(transport, codec: v2Codec, v3Codec: v3Codec,
                        appconfCodec: appCodec)
    defer { client.close() }
    guard let fw = client.fwVersion() else {
        print("  ❌ VESC 与 V3 握手都无响应")
        exit(3)
    }
    print("  ✅ \(client.wireProtocol.title) FW \(fw.major).\(fw.minor) HW \(fw.hw)")
    if CommandLine.arguments.contains("--raw-get-values"),
       client.wireProtocol == .v3 {
        print("  ℹ️ V3 实时数据原始探测：发送 0x45，抓取 3 秒内全部 RX 字节")
        let decoder = RotorV3PacketDecoder()
        guard transport.write(RotorV3Packet.encodeCmd(.getValues)) else {
            print("  ❌ 0x45 写入串口失败")
            exit(28)
        }
        let startedAt = Date()
        var receivedByteCount = 0
        var frameCount = 0
        while Date().timeIntervalSince(startedAt) < 3 {
            let chunk = transport.read(max: 8192)
            if !chunk.isEmpty {
                receivedByteCount += chunk.count
                print(String(format: "  RAW +%.3f s (%d bytes): %@",
                             Date().timeIntervalSince(startedAt),
                             chunk.count, chunk.hex))
                for frame in decoder.feed(chunk) {
                    frameCount += 1
                    print("  FRAME \(frameCount): \(frame.hex)")
                }
            }
            usleep(2_000)
        }
        if receivedByteCount == 0 {
            print("  ❌ 3 秒内 RX 为 0 字节")
        } else if frameCount == 0 {
            print("  ❌ 收到 \(receivedByteCount) 字节，但没有通过 V3 帧校验")
        } else {
            print("  ✅ 收到 \(receivedByteCount) 字节、\(frameCount) 个有效 V3 帧")
        }
        exit(0)
    }
    guard let values = client.getValues() else {
        print("  ❌ 握手成功，但实时数据无响应")
        exit(4)
    }
    print(String(format:
        "  ✅ 实时数据：%.1f V, %.0f ERPM, Iq %.2f A, MOS %.1f °C, ID %d，"
        + "故障 %@，VD/VQ %.3f/%.3f V，控制模式 %d",
        values.vIn, values.rpm, values.iqCurr, values.tempFet, values.controllerId,
        values.faultStr, values.vD, values.vQ, values.currentControlMode))
    if CommandLine.arguments.contains("--iap-roundtrip")
        || CommandLine.arguments.contains("--iap66-roundtrip") {
        guard client.wireProtocol == .v3 else {
            print("  ❌ IAP 往返探测只适用于 V3 UART")
            exit(50)
        }
        _ = client.servoCurrent(0)
        _ = client.servoDuty(0)
        _ = client.alive()
        print("  ℹ️ 仅验证 IAP 往返；不会发送擦除或固件数据")
        guard client.enterFirmwareBootloader() else {
            print("  ❌ 5 秒内未收到 0x42 IAP ACK；未发送其他命令")
            exit(51)
        }
        if CommandLine.arguments.contains("--iap66-roundtrip") {
            print("  ℹ️ 历史诊断：再发送一次 0x42")
            guard client.jumpToBootloader() else { exit(52) }
        }
        print("  ℹ️ 执行官方两轮 A1 原始跳转应用序列…")
        guard client.recoverV3ServoApplication(
            enterBootloaderFirst: false,
            progress: { round in print("  → A1 \(round)/2") }
        ) else {
            _ = client.prepareForBootloaderTimeout()
            client.close()
            print("  ❌ 两轮 A1 后应用层仍未恢复；未擦除 Flash")
            exit(53)
        }
        guard let afterValues = client.getValues() else {
            print("  ❌ 0x41 已恢复，但实时数据 0x45 没有回包")
            exit(55)
        }
        print(String(format: "  ✅ IAP 往返成功，实时数据 %.1f V", afterValues.vIn))
        exit(0)
    }
    if let upgradeIndex = CommandLine.arguments.firstIndex(of: "--firmware-upgrade"),
       CommandLine.arguments.indices.contains(upgradeIndex + 1) {
        let imageURL = URL(fileURLWithPath: CommandLine.arguments[upgradeIndex + 1])
        let image: Data
        do {
            image = try Data(contentsOf: imageURL)
        } catch {
            print("  ❌ 无法读取固件：\(error.localizedDescription)")
            exit(40)
        }
        let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
        let officialV34SHA = "5dbda5eac4743854b2b26f55f5ade37cfd95497e727048f46c96426cf0a8bbd1"
        // 自改镜像走单独一条通道：官方 SHA 那道闸是给"我以为在刷官方固件"的人用的，
        // 不该为了自改而拆掉。这里要求显式声明，并加一组自改镜像专属的检查。
        let isModified = CommandLine.arguments.contains("--accept-modified-image")
        if isModified {
            print("  ⚠️ 自改镜像模式：跳过官方 SHA 校验，改用结构与槽尾约束")
            print("     SHA-256 \(digest)")
            guard image.count == 393_208 else {
                print("  ❌ 拒绝刷写：长度 \(image.count) ≠ 393208（Servo 槽 APP_MAX_SIZE）")
                exit(41)
            }
            // 固件在 main() 里对整份镜像做 CRC-32 自校验，失败即闪灯死循环、应用永不启动。
            // 它靠"标志字为擦除态"自愈，所以这 8 字节必须原样保持 0xFF。
            let tail = Array(image[0x5FFF0..<0x5FFF8])
            guard tail.allSatisfy({ $0 == 0xFF }) else {
                print("  ❌ 拒绝刷写：槽尾记账位 [0x5FFF0,0x5FFF8) 不是 0xFF —— "
                      + "CRC 自愈会失效，刷完必然闪灯死循环")
                print("     实际 \(tail.map { String(format: "%02X", $0) }.joined(separator: " "))")
                exit(41)
            }
            // Cortex-M 向量表结构：SP 落在 SRAM，复位向量落在本槽内且带 Thumb 位。
            let sp = image.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
            let reset = image.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            guard (0x2000_0000...0x2003_0000).contains(sp),
                  (0x0806_0000...0x080B_FFFF).contains(reset & ~1), (reset & 1) == 1 else {
                print("  ❌ 拒绝刷写：向量表不合理 SP=\(String(format: "0x%08X", sp)) "
                      + "Reset=\(String(format: "0x%08X", reset))")
                exit(41)
            }
            print("  ✅ 结构检查通过：SP=\(String(format: "0x%08X", sp)) "
                  + "Reset=\(String(format: "0x%08X", reset)) 槽尾 0xFF")
        } else {
            guard image.count == 393_208, digest == officialV34SHA else {
                print("  ❌ 拒绝刷写：不是已登记的 AK80-9 V3.4 官方镜像")
                print("     size \(image.count), SHA-256 \(digest)")
                print("     若这是你自己改的镜像，加 --accept-modified-image")
                exit(41)
            }
        }
        let hardware = fw.hw.uppercased()
        guard client.wireProtocol == .v3,
              // 自制固件把身份串等长改成了 `…_SC_V3.4`（SW → SC），两者都要认。
              hardware.contains("CMESC_AK80_9_SW_V3")
                || hardware.contains("CMESC_AK80_9_SC_V3") else {
            print("  ❌ 拒绝刷写：当前不是 AK80-9 V3 Servo 分支（\(fw.hw)）")
            exit(42)
        }

        print(isModified ? "  ⚠️ 将刷入自改镜像到 \(fw.hw)"
                          : "  ✅ 精确匹配：\(fw.hw) → 官方 AK80-9 V3.4")
        client.wireTrace = { direction, bytes in
            // 固件路径只打印短控制帧；固件分块 TX 很长，保留首尾和总长度。
            let hex: String
            if bytes.count <= 64 {
                hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            } else {
                let head = bytes.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " ")
                let tail = bytes.suffix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                hex = "\(head) … \(tail) [\(bytes.count) bytes]"
            }
            print("  [\(direction)] \(hex)")
        }
        print("  ℹ️ 擦除前读取并备份 mcconf/appconf")
        guard let (motorSignature, motorValues) = client.getMcconf(),
              let motorCodec = client.configurationCodec,
              let (appSignature, appValues) = client.getAppconf(),
              let appCodec = client.appconfCodec else {
            print("  ❌ 参数备份读取失败；未进入 IAP、未擦除")
            exit(43)
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Rotor/Backups")
            .appendingPathComponent("firmware-upgrade-\(timestamp)")
        do {
            try FileManager.default.createDirectory(at: backupURL,
                                                    withIntermediateDirectories: true)
            try Data(motorCodec.pack(motorValues, signature: motorSignature))
                .write(to: backupURL.appendingPathComponent("mcconf.bin"), options: .atomic)
            try Data(appCodec.pack(appValues, signature: appSignature))
                .write(to: backupURL.appendingPathComponent("appconf.bin"), options: .atomic)
            let metadata: [String: Any] = [
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "hardware_before": fw.hw,
                "fw_before": "\(fw.major).\(fw.minor)",
                "image": imageURL.lastPathComponent,
                "image_sha256": digest,
                "image_size": image.count,
                "port": port,
                "baud": baud
            ]
            let json = try JSONSerialization.data(withJSONObject: metadata,
                                                   options: [.prettyPrinted, .sortedKeys])
            try json.write(to: backupURL.appendingPathComponent("firmware-info.json"),
                           options: .atomic)
        } catch {
            print("  ❌ 参数备份落盘失败：\(error.localizedDescription)；未擦除")
            exit(44)
        }
        print("  ✅ 参数备份：\(backupURL.path)")
        _ = client.servoCurrent(0)
        _ = client.servoDuty(0)
        _ = client.alive()

        print("  ℹ️ 进入 V3 IAP，并切换 R-LINK 到固件上传链路…")
        guard client.enterFirmwareBootloader() else {
            print("  ❌ 5 秒内未收到 0x42 IAP ACK；未擦除")
            exit(45)
        }
        guard client.activateFirmwareBootloaderLink() else {
            print("  ❌ 已收到 IAP ACK，但 R-LINK 关口/重开失败；未擦除")
            exit(45)
        }
        // 真机抓包显示官方在重开串口后 ~0 延迟就开始发控制包；此处只留一点
        // 余量。此前的 5 秒等待来自“先擦除再写”的旧理论，该理论已被推翻。
        sleepAtLeast(1)

        print("  ℹ️ 通过 IAP 原始帧上传官方整包（128 字节/块）…")
        var lastPrintedPercent = -10
        let upload = client.uploadNewApp(image: Array(image)) { progress in
            let percent = Int(progress * 100)
            if percent >= lastPrintedPercent + 10 || percent == 100 {
                lastPrintedPercent = percent
                print("  … 上传 \(percent)%")
            }
        }
        switch upload {
        case .failure(let failure):
            print("  ❌ 上传失败：\(failure)")
            exit(46)
        case .success(let receipt):
            print("  ✅ 上传完成：\(receipt.writtenChunks) 个写入块，"
                  + "\(receipt.skippedChunks) 个擦除态块，CRC16 "
                  + String(format: "0x%04X", receipt.imageCRC16))
        }

        print("  ℹ️ 暂存区写入完成，启动应用并校验新镜像…")
        guard client.recoverV3ServoApplication(
            enterBootloaderFirst: false,
            progress: { round in print("  → 启动应用 A1 \(round)/2") }
        ) else {
            print("  ❌ 两轮 A1 跳转或 0x41 回读失败")
            exit(47)
        }
        print("  ℹ️ Servo 应用已回读确认；关闭串口并重新核对版本…")
        client.close()
        var reconnected: (major: Int, minor: Int, hw: String)?
        for attempt in 1...12 where reconnected == nil {
            usleep(attempt == 1 ? 2_000_000 : 4_000_000)
            guard let retryTransport = SerialTransport(port: port, baud: baud) else {
                print("  → 重连 \(attempt)/12：串口尚不可用")
                continue
            }
            let retryClient = Client(retryTransport, codec: v2Codec,
                                     v3Codec: v3Codec, appconfCodec: appCodec)
            reconnected = retryClient.fwVersion()
            retryClient.close()
            if reconnected == nil {
                print("  → 重连 \(attempt)/12：Bootloader 尚未返回")
            }
        }
        guard let after = reconnected else {
            print("  ❌ 镜像已写入，但约 46 秒内重连握手失败")
            exit(48)
        }
        print("  ✅ 重连：FW \(after.major).\(after.minor) HW \(after.hw)")
        let hwAfter = after.hw.uppercased()
        guard hwAfter.contains("CMESC_AK80_9_SW_V3.4")
                || hwAfter.contains("CMESC_AK80_9_SC_V3.4") else {
            print("  ❌ 重连成功，但硬件字符串不是 V3.4")
            exit(49)
        }
        print("  ✅ 真机固件升级与版本校验全部通过")
        exit(0)
    }
    if CommandLine.arguments.contains("--reboot") {
        _ = client.servoCurrent(0)
        _ = client.servoDuty(0)
        guard client.reboot() else {
            print("  ❌ 重启命令写入串口失败")
            exit(16)
        }
        print("  ✅ 已发送固件重启命令")
        exit(0)
    }
    if CommandLine.arguments.contains("--raw-detect-rl"),
       client.wireProtocol == .v3 {
        print("  ℹ️ V3 R/L 原始回包探测：发送 0x5A，最长等待 30 秒")
        let decoder = RotorV3PacketDecoder()
        let startedAt = Date()
        var nextAliveAt = startedAt.addingTimeInterval(1)
        var response: [UInt8]?
        guard transport.write(RotorV3Packet.encodeCmd(.detectMotorRL)) else {
            print("  ❌ 0x5A 写入串口失败")
            exit(9)
        }
        while Date().timeIntervalSince(startedAt) < 30, response == nil {
            for frame in decoder.feed(transport.read(max: 8192)) {
                let elapsed = Date().timeIntervalSince(startedAt)
                print(String(format: "  RX +%.3f s: %@", elapsed, frame.hex))
                if frame.first == UInt8(RotorV3Comm.detectMotorRL.rawValue) {
                    response = frame
                }
            }
            if Date() >= nextAliveAt {
                _ = transport.write(RotorV3Packet.encodeCmd(.alive))
                nextAliveAt = Date().addingTimeInterval(1)
            }
            usleep(2_000)
        }
        if let response {
            if response.count >= 9 {
                var reader = BufReader(response.dropFirst())
                let resistance = reader.f32(1e6)
                let inductance = reader.f32(1e3)
                let difference = reader.remaining >= 4 ? reader.f32(1e3) : 0
                print(String(format:
                    "  ✅ 0x5A 回包：R %.9f Ω，L %.6f µH，Lq−Ld %.6f µH",
                    resistance, inductance, difference))
            } else {
                print("  ❌ 0x5A 回包长度不足：\(response.count) bytes")
            }
        } else {
            print("  ❌ 30 秒内没有 0x5A 回包")
        }
        exit(0)
    }
    if let encoderIndex = CommandLine.arguments.firstIndex(of: "--raw-detect-encoder"),
       client.wireProtocol == .v3 {
        let requestedCurrent = CommandLine.arguments.indices.contains(encoderIndex + 1)
            ? Double(CommandLine.arguments[encoderIndex + 1]) ?? 5 : 5
        let current = min(max(abs(requestedCurrent), 0.1), 10)
        print(String(format:
            "  ℹ️ V3 编码器原始回包探测：发送 0x5C，检测电流 %.2f A，最长等待 180 秒",
            current))
        let decoder = RotorV3PacketDecoder()
        let startedAt = Date()
        var nextAliveAt = startedAt.addingTimeInterval(1)
        var response: [UInt8]?
        var writer = BufWriter()
        writer.u8(RotorV3Comm.detectEncoder.rawValue)
        writer.f32(current, 1e3)
        defer {
            _ = client.servoCurrent(0)
            _ = client.servoDuty(0)
            _ = client.alive()
        }
        guard transport.write(RotorV3Packet.encode(writer.bytes)) else {
            print("  ❌ 0x5C 写入串口失败")
            exit(27)
        }
        while Date().timeIntervalSince(startedAt) < 180, response == nil {
            for frame in decoder.feed(transport.read(max: 8192)) {
                let elapsed = Date().timeIntervalSince(startedAt)
                print(String(format: "  RX +%.3f s: %@", elapsed, frame.hex))
                if frame.first == UInt8(RotorV3Comm.detectEncoder.rawValue) {
                    response = frame
                }
            }
            if Date() >= nextAliveAt {
                _ = transport.write(RotorV3Packet.encodeCmd(.alive))
                nextAliveAt = Date().addingTimeInterval(1)
            }
            usleep(2_000)
        }
        if let response, response.count >= 10 {
            var reader = BufReader(response.dropFirst())
            let offset = reader.f32(1e6)
            let ratio = reader.f32(1e6)
            let inverted = reader.i8() != 0
            print(String(format:
                "  ✅ 0x5C 回包：Offset %.6f°，Ratio %.6f，方向 %@",
                offset, ratio, inverted ? "反向" : "正向"))
        } else if let response {
            print("  ❌ 0x5C 回包长度不足：\(response.count) bytes")
        } else {
            print("  ❌ 180 秒内没有 0x5C 回包")
        }
        exit(0)
    }
    if let smokeIndex = CommandLine.arguments.firstIndex(of: "--control-smoke"),
       client.wireProtocol == .v3 {
        let requestedCurrent = CommandLine.arguments.indices.contains(smokeIndex + 1)
            ? Double(CommandLine.arguments[smokeIndex + 1]) ?? 0.2 : 0.2
        let current = min(max(abs(requestedCurrent), 0.05), 3.0)
        defer {
            _ = client.servoCurrent(0)
            _ = client.servoDuty(0)
            _ = client.alive()
        }
        print(String(format:
            "  ℹ️ V3 低电流探测：发送 %.2f A，持续不超过 0.4 秒", current))
        var peakIq = 0.0
        var peakMotorCurrent = 0.0
        var peakId = 0.0
        var peakInputCurrent = 0.0
        var currentControlMode = 0
        var writeOK = true
        let immediateAlive = CommandLine.arguments.contains("--control-smoke-alive")
        for _ in 0..<4 {
            // 官方工具的控制按钮只发送控制帧；Alive 由独立定时器稍后发送。
            // 这里刻意避免把 0x47 与 0x5F 紧邻写入，以核对 V3 固件时序。
            writeOK = client.servoCurrent(current) && writeOK
            if immediateAlive {
                writeOK = client.alive() && writeOK
            }
            usleep(80_000)
            if let sample = client.getValues() {
                peakIq = max(peakIq, abs(sample.iqCurr))
                peakMotorCurrent = max(peakMotorCurrent, abs(sample.currentMotor))
                peakId = max(peakId, abs(sample.idCurr))
                peakInputCurrent = max(peakInputCurrent, abs(sample.currentIn))
                currentControlMode = sample.currentControlMode
            }
        }
        print(String(format:
            "  %@ 控制写入；峰值 Motor %.2f A / Id %.2f A / Iq %.2f A / Bus %.2f A，模式 %d",
            writeOK ? "✅" : "❌", peakMotorCurrent, peakId, peakIq,
            peakInputCurrent, currentControlMode))
    }
    // CAN 周期状态帧的开关在 appconf 里，不需要改固件。
    // send_can_status 是枚举：0=DISABLED, 1=STATUS_1, …, 5=STATUS_1..5。
    // 只开 STATUS_1 时 CAN 上只有 ERPM/电流/占空比；开到 5 才有 MOS 温度、
    // 电机温度、输入电流、PID 位置、里程计、输入电压。
    if let canIndex = CommandLine.arguments.firstIndex(of: "--set-can-status") {
        guard CommandLine.arguments.indices.contains(canIndex + 1),
              let requested = Int(CommandLine.arguments[canIndex + 1]),
              (0...5).contains(requested) else {
            print("  ❌ 用法：--set-can-status 0..5 [--set-can-rate <hz>]")
            exit(50)
        }
        var requestedRate: Int? = nil
        if let rateIndex = CommandLine.arguments.firstIndex(of: "--set-can-rate") {
            guard CommandLine.arguments.indices.contains(rateIndex + 1),
                  let hz = Int(CommandLine.arguments[rateIndex + 1]),
                  (1...1000).contains(hz) else {
                print("  ❌ 用法：--set-can-rate 1..1000")
                exit(50)
            }
            requestedRate = hz
        }
        guard client.wireProtocol == .v3, let appCodecActive = client.appconfCodec else {
            print("  ❌ 仅支持 V3 且需要 appconf 参数定义")
            exit(51)
        }
        guard let (appSignature, appConfig) = client.getAppconf() else {
            print("  ❌ 无法读取 appconf")
            exit(52)
        }
        let before = appConfig["send_can_status"]?.intValue ?? -1
        let beforeRate = appConfig["send_can_status_rate_hz"]?.intValue ?? -1
        print("  ℹ️ 当前 send_can_status=\(before) rate=\(beforeRate) Hz "
              + "signature=0x\(String(appSignature, radix: 16, uppercase: true))")

        let backupDirectory = URL(fileURLWithPath: "../../hardware-debug", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: backupDirectory, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = backupDirectory.appendingPathComponent(
            "ak80-9-appconf-before-can-status-\(stamp.string(from: Date())).bin")
        do {
            try Data(appCodecActive.pack(appConfig, signature: appSignature))
                .write(to: backupURL, options: .atomic)
        } catch {
            print("  ❌ 无法保存 appconf 备份：\(error)")
            exit(53)
        }

        var updated = appConfig
        updated["send_can_status"] = .int(requested)
        if let hz = requestedRate { updated["send_can_status_rate_hz"] = .int(hz) }
        guard client.setAppconf(updated, signature: appSignature) else {
            print("  ❌ 写入未收到设备 ACK；备份：\(backupURL.path)")
            exit(54)
        }
        usleep(250_000)
        guard let (verifySignature, verified) = client.getAppconf() else {
            print("  ❌ 收到 ACK，但写后无法回读；备份：\(backupURL.path)")
            exit(55)
        }
        let exactMatch = verifySignature == appSignature
            && appCodecActive.pack(verified, signature: verifySignature)
                == appCodecActive.pack(updated, signature: appSignature)
        let after = verified["send_can_status"]?.intValue ?? -1
        let afterRate = verified["send_can_status_rate_hz"]?.intValue ?? -1
        if exactMatch {
            print("  ✅ send_can_status \(before) → \(after)，rate \(beforeRate) → \(afterRate) Hz")
            print("  ✅ ACK 后回读逐字节一致；写入前备份：\(backupURL.path)")
            exit(0)
        }
        print("  ❌ 收到 ACK 但回读不一致：send_can_status=\(after) rate=\(afterRate)")
        print("     备份：\(backupURL.path)")
        exit(56)
    }

    // 只读终端命令。hw_status 会打印 OPTR/RDPROT，是判断能否用 SWD 救砖的前提。
    // 读单个 appconf 字段。排查 CAN 可见性时反复需要——决定电机在总线上
    // 是否可见的那几个开关都在 appconf 里，而它们此前只能靠整包读回来自己数偏移。
    if let i = CommandLine.arguments.firstIndex(of: "--appconf-get"),
       CommandLine.arguments.indices.contains(i + 1) {
        let name = CommandLine.arguments[i + 1]
        guard let (sig, values) = client.getAppconf() else {
            print("  ❌ appconf 读取失败"); exit(46)
        }
        print("  appconf 签名 0x\(String(format: "%08X", sig))，\(values.count) 项")
        let matches = values.keys.filter { $0.localizedCaseInsensitiveContains(name) }.sorted()
        if matches.isEmpty { print("  ❌ 没有匹配 \"\(name)\" 的字段"); exit(46) }
        for k in matches {
            let v = values[k]!
            print("  \(k) = \(v.intValue)  (0x\(String(format: "%X", v.intValue)))  double=\(v.doubleValue)")
        }
        exit(0)
    }

    if let termIndex = CommandLine.arguments.firstIndex(of: "--terminal") {
        guard CommandLine.arguments.indices.contains(termIndex + 1) else {
            print("  ❌ 用法：--terminal \"<命令>\"    例：--terminal hw_status")
            exit(60)
        }
        let text = CommandLine.arguments[termIndex + 1]
        guard client.wireProtocol == .v3 else {
            print("  ❌ 终端命令目前只实现了 V3 分支")
            exit(61)
        }
        print("  ℹ️ 发送终端命令：\(text)")
        var overrideId: Int? = nil
        if let i = CommandLine.arguments.firstIndex(of: "--terminal-id"),
           CommandLine.arguments.indices.contains(i + 1) {
            overrideId = Int(CommandLine.arguments[i + 1])
            print("  ℹ️ 用命令号 \(overrideId.map { "0x" + String($0, radix: 16) } ?? "?") 覆盖默认 0x55")
        }
        let lines = client.terminalCommand(text, commandId: overrideId)
        if lines.isEmpty {
            print("  ❌ 未收到任何 COMM_PRINT 回应（命令名可能不存在，或该固件未启用终端）")
            exit(62)
        }
        for line in lines {
            for sub in line.split(separator: "\n", omittingEmptySubsequences: false) {
                print("  │ \(sub)")
            }
        }
        print("  ✅ 终端命令返回 \(lines.count) 帧")
        exit(0)
    }

    // MIT 0x60 安全探针：全零参数不产生任何输出（kp=kd=力矩=0），
    // 只验证线格式是否被固件接受。用 foc_state 回读 m_mit_*_set 作为证据。
    if CommandLine.arguments.contains("--mit-probe") {
        guard client.wireProtocol == .v3 else {
            print("  ❌ 仅 V3 支持 0x60"); exit(70)
        }
        func readBack() -> [String] {
            client.terminalCommand("foc_state").flatMap { line in
                line.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            }.filter { $0.contains("m_mit_") }
        }
        print("  ℹ️ 下发前 foc_state：")
        for l in readBack() { print("  │ \(l)") }

        // 位置给非零、增益与前馈力矩全给 0：
        // tau = kp*posErr + kd*velErr + ff = 0，输出恒为零，电机不动，
        // 但 m_mit_pos_set 应回读出该值——这才能区分“被接受”和“被无视”。
        let probePos = 1.234
        let probeRpm = 5.678
        print("  ℹ️ 发送 0x60（pos=\(probePos) rpm=\(probeRpm)，kp=kd=力矩=0 → 输出恒为零）…")
        guard client.setPidMit(pos: probePos, rpm: probeRpm, torque: 0, kp: 0, kd: 0) else {
            print("  ❌ 写串口失败"); exit(71)
        }
        usleep(150_000)
        if let v = client.getValues() {
            let iq = abs(v.currentMotor)
            print("  ℹ️ 下发后电流 Iq = \(String(format: "%.3f", v.currentMotor)) A")
            if iq > 0.15 {
                print("  ⛔️ 电流非零，立即停机并中止")
                _ = client.servoCurrent(0)
                exit(73)
            }
        }
        usleep(400_000)
        let after = readBack()
        print("  ℹ️ 下发后 foc_state：")
        for l in after { print("  │ \(l)") }
        if after.isEmpty {
            print("  ❌ 回读不到 m_mit_* —— 命令可能未被接受"); exit(72)
        }
        print("  ✅ 0x60 已发送且 foc_state 可回读（全零参数，未产生输出）")
        exit(0)
    }

    if CommandLine.arguments.contains("--config") {
        guard let (motorSignature, motorConfig) = client.getMcconf(),
              let activeCodec = client.configurationCodec else {
            print("  ❌ 电机参数读取失败")
            exit(5)
        }
        let motorBlob = activeCodec.pack(motorConfig, signature: motorSignature)
        print(String(format:
            "  ✅ 电机参数：%d 项，%d bytes，设备/定义签名 0x%08X/0x%08X，R %.6f Ω，L %.3f µH",
            activeCodec.order.count, motorBlob.count, motorSignature, activeCodec.signature,
            motorConfig["foc_motor_r"]?.doubleValue ?? 0,
            (motorConfig["foc_motor_l"]?.doubleValue ?? 0) * 1e6))
        guard let (appSignature, appConfig) = client.getAppconf(),
              let appCodec = client.appconfCodec else {
            print("  ❌ 应用参数读取失败")
            exit(6)
        }
        let appBlob = appCodec.pack(appConfig, signature: appSignature)
        print(String(format:
            "  ✅ 应用参数：%d 项，%d bytes，签名 0x%08X，CAN ID %d",
            appCodec.order.count, appBlob.count, appSignature,
            appConfig["controller_id"]?.intValue ?? -1))
        if CommandLine.arguments.contains("--dump-relevant-config") {
            let motorNames = [
                "motor_type", "l_current_max", "l_current_min", "l_abs_current_max",
                "l_current_max_scale", "l_current_min_scale",
                "l_in_current_max", "l_in_current_min", "l_min_erpm", "l_max_erpm",
                "l_min_vin", "l_max_vin", "l_min_duty", "l_max_duty",
                "l_watt_max", "l_watt_min", "l_duty_start",
                "foc_sensor_mode", "m_sensor_port_mode", "m_encoder_counts",
                "m_motor_temp_sens_type", "foc_encoder_offset", "foc_encoder_ratio",
                "foc_encoder_inverted", "m_invert_direction",
                "foc_current_kp", "foc_current_ki",
                "foc_motor_r", "foc_motor_l", "foc_motor_flux_linkage",
                "foc_observer_gain", "foc_openloop_rpm", "foc_sl_openloop_hyst",
                "foc_sl_openloop_time", "foc_sample_v0_v7"
            ]
            let appNames = appConfig.keys.filter {
                let name = $0.lowercased()
                return name.contains("uart") || name.contains("timeout")
                    || name.contains("app_to_use") || name.contains("can_mode")
            }.sorted()
            print("  -- 关键电机配置 --")
            for name in motorNames where motorConfig[name] != nil {
                print("    \(name) = \(motorConfig[name]!)")
            }
            print("  -- 关键应用配置 --")
            for name in appNames {
                print("    \(name) = \(appConfig[name]!)")
            }
        }
        if CommandLine.arguments.contains("--inspect-invert-direction") {
            guard let current = motorConfig["m_invert_direction"] else {
                print("  ❌ 参数表中没有 m_invert_direction")
                exit(29)
            }
            var toggled = motorConfig
            toggled["m_invert_direction"] = .int(current.intValue == 0 ? 1 : 0)
            let toggledBlob = activeCodec.pack(toggled, signature: motorSignature)
            let changedOffsets = zip(motorBlob.indices, zip(motorBlob, toggledBlob))
                .compactMap { index, pair in pair.0 == pair.1 ? nil : index }
            print("  ℹ️ m_invert_direction 当前 = \(current.intValue)，切换后仅改变配置体偏移：\(changedOffsets)")
            for index in changedOffsets {
                print(String(format: "    byte[%d]: 0x%02X -> 0x%02X",
                             index, motorBlob[index], toggledBlob[index]))
            }
        }
        if let setIndex = CommandLine.arguments.firstIndex(of: "--set-invert-direction") {
            guard CommandLine.arguments.indices.contains(setIndex + 1),
                  let requested = Int(CommandLine.arguments[setIndex + 1]),
                  requested == 0 || requested == 1 else {
                print("  ❌ 用法：--set-invert-direction 0|1")
                exit(30)
            }
            guard client.wireProtocol == .v3,
                  motorSignature == activeCodec.signature else {
                print("  ❌ 仅允许在 V3 且设备签名与参数定义完全一致时写入")
                exit(31)
            }
            let backupDirectory = URL(fileURLWithPath: "../../hardware-debug",
                                      isDirectory: true)
            try? FileManager.default.createDirectory(
                at: backupDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backupURL = backupDirectory.appendingPathComponent(
                "ak80-9-v3-mcconf-before-invert-direction-\(formatter.string(from: Date())).bin")
            do {
                try Data(motorBlob).write(to: backupURL, options: .atomic)
            } catch {
                print("  ❌ 无法保存参数备份：\(error)")
                exit(32)
            }
            var updated = motorConfig
            updated["m_invert_direction"] = .int(requested)
            guard client.setMcconf(updated, signature: motorSignature) else {
                print("  ❌ 写入未收到设备 ACK；备份：\(backupURL.path)")
                exit(33)
            }
            usleep(250_000)
            guard let (verifySignature, verified) = client.getMcconf() else {
                print("  ❌ 收到 ACK，但写后无法回读；备份：\(backupURL.path)")
                exit(34)
            }
            let verifiedValue = verified["m_invert_direction"]?.intValue ?? -1
            var expected = motorConfig
            expected["m_invert_direction"] = .int(requested)
            let exactMatch = verifySignature == motorSignature
                && activeCodec.pack(verified, signature: verifySignature)
                    == activeCodec.pack(expected, signature: motorSignature)
            if exactMatch {
                print("  ✅ 反转电机方向已写为 \(requested)，ACK 后回读逐字节一致")
                print("  ✅ 写入前备份：\(backupURL.path)")
                exit(0)
            }
            print("  ❌ 固件收到 ACK，但回读值为 \(verifiedValue)，目标值为 \(requested)")
            print("  ℹ️ 说明 SET 帧已送达，但该字段被固件拒绝、钳制或另有保存机制")
            print("  ℹ️ 写入前备份：\(backupURL.path)")
            exit(35)
        }
        if let restoreIndex = CommandLine.arguments.firstIndex(
            of: "--restore-encoder-calibration") {
            guard CommandLine.arguments.indices.contains(restoreIndex + 1) else {
                print("  ❌ 用法：--restore-encoder-calibration <mcconf-backup.bin>")
                exit(36)
            }
            guard motorSignature == activeCodec.signature else {
                print("  ❌ 设备签名与参数定义不一致，拒绝恢复")
                exit(37)
            }

            let sourcePath = CommandLine.arguments[restoreIndex + 1]
            let sourceData: Data
            do {
                sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
            } catch {
                print("  ❌ 无法读取校准备份：\(error)")
                exit(38)
            }
            let (sourceSignature, sourceConfig) = activeCodec.unpack(Array(sourceData))
            guard sourceSignature == motorSignature else {
                print("  ❌ 校准备份签名与当前电机不一致，拒绝恢复")
                exit(39)
            }

            let calibrationFields = [
                "foc_encoder_offset", "foc_encoder_ratio", "foc_encoder_inverted"
            ]
            guard calibrationFields.allSatisfy({ sourceConfig[$0] != nil }) else {
                print("  ❌ 校准备份缺少 Offset / Ratio / Direction")
                exit(40)
            }

            let protocolName = client.wireProtocol == .v3 ? "v3" : "v2"
            let backupDirectory = URL(fileURLWithPath: "../../hardware-debug",
                                      isDirectory: true)
            try? FileManager.default.createDirectory(
                at: backupDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backupURL = backupDirectory.appendingPathComponent(
                "ak80-9-\(protocolName)-mcconf-before-encoder-calibration-restore-\(formatter.string(from: Date())).bin")
            do {
                try Data(motorBlob).write(to: backupURL, options: .atomic)
            } catch {
                print("  ❌ 无法保存恢复前参数：\(error)")
                exit(41)
            }

            var expected = motorConfig
            for name in calibrationFields { expected[name] = sourceConfig[name] }
            guard client.setMcconf(expected, signature: motorSignature) else {
                print("  ❌ 恢复写入未收到设备 ACK；当前参数备份：\(backupURL.path)")
                exit(42)
            }

            usleep(350_000)
            var verification: (UInt32, [String: ParamValue])?
            for _ in 0..<4 {
                if let readback = client.getMcconf() {
                    verification = readback
                    break
                }
                usleep(250_000)
            }
            guard let (verifySignature, verified) = verification else {
                print("  ❌ 收到 ACK，但恢复后无法回读；当前参数备份：\(backupURL.path)")
                exit(43)
            }

            let rejected = activeCodec.changedParameterNames(
                expected: expected, actual: verified)
                .filter { calibrationFields.contains($0) }
            guard verifySignature == motorSignature, rejected.isEmpty else {
                print("  ❌ 编码器校准回读不一致：\(rejected.joined(separator: "、"))")
                print("  ℹ️ 当前参数备份：\(backupURL.path)")
                exit(44)
            }
            print("  ✅ 已只恢复编码器 Offset / Ratio / Direction，ACK 与回读均通过")
            for name in calibrationFields {
                print("    \(name) = \(verified[name]!)")
            }
            print("  ✅ 恢复前参数备份：\(backupURL.path)")
            exit(0)
        }
        if CommandLine.arguments.contains("--dump-zero-overrides") {
            let defaults = activeCodec.defaults()
            print("  -- 设备为 0、但同签名定义默认值非 0 的电机参数 --")
            for parameter in activeCodec.order {
                guard let actual = motorConfig[parameter.name],
                      let defaultValue = defaults[parameter.name] else { continue }
                let actualNumber = actual.doubleValue
                let defaultNumber = defaultValue.doubleValue
                if actualNumber == 0, defaultNumber != 0 {
                    print("    \(parameter.name): 设备 0，默认 \(defaultNumber)")
                }
            }
        }
        if CommandLine.arguments.contains("--repair-current-scales") {
            guard client.wireProtocol == .v3,
                  motorSignature == activeCodec.signature else {
                print("  ❌ 仅允许在 V3 且设备签名与参数定义完全一致时修复")
                exit(10)
            }
            let oldMaxScale = motorConfig["l_current_max_scale"]?.doubleValue ?? .nan
            let oldMinScale = motorConfig["l_current_min_scale"]?.doubleValue ?? .nan
            guard oldMaxScale.isFinite, oldMinScale.isFinite,
                  oldMaxScale == 0, oldMinScale == 0 else {
                print(String(format:
                    "  ❌ 当前缩放不是预期的 0/0（实际 %.6f/%.6f），拒绝自动修改",
                    oldMaxScale, oldMinScale))
                exit(11)
            }

            let backupDirectory = URL(fileURLWithPath: "../../hardware-debug",
                                      isDirectory: true)
            try? FileManager.default.createDirectory(
                at: backupDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backupURL = backupDirectory.appendingPathComponent(
                "ak80-9-v3-mcconf-before-current-scale-\(formatter.string(from: Date())).bin")
            do {
                try Data(motorBlob).write(to: backupURL, options: .atomic)
            } catch {
                print("  ❌ 无法保存参数备份：\(error)")
                exit(12)
            }

            var repaired = motorConfig
            repaired["l_current_max_scale"] = .double(1)
            repaired["l_current_min_scale"] = .double(1)
            _ = client.servoCurrent(0)
            _ = client.servoDuty(0)
            _ = client.alive()
            guard client.setMcconf(repaired, signature: motorSignature) else {
                print("  ❌ 修复参数写入没有收到设备 ACK；备份：\(backupURL.path)")
                exit(13)
            }
            usleep(250_000)
            guard let (verifySignature, verified) = client.getMcconf(),
                  verifySignature == motorSignature,
                  verified["l_current_max_scale"]?.doubleValue == 1,
                  verified["l_current_min_scale"]?.doubleValue == 1 else {
                print("  ❌ 写入后重读校验失败；备份：\(backupURL.path)")
                exit(14)
            }
            var expected = motorConfig
            expected["l_current_max_scale"] = .double(1)
            expected["l_current_min_scale"] = .double(1)
            guard activeCodec.pack(verified, signature: verifySignature)
                    == activeCodec.pack(expected, signature: motorSignature) else {
                print("  ❌ 重读发现除两个缩放值外还有其他变化；备份：\(backupURL.path)")
                exit(15)
            }
            print("  ✅ 电流正/负缩放已由 0/0 恢复为 1/1，其他参数逐字节一致")
            print("  ✅ 写入前备份：\(backupURL.path)")
            exit(0)
        }
        if CommandLine.arguments.contains("--repair-zero-limits") {
            guard client.wireProtocol == .v3,
                  motorSignature == activeCodec.signature else {
                print("  ❌ 仅允许在 V3 且设备签名与参数定义完全一致时修复")
                exit(17)
            }
            let replacements: [String: ParamValue] = [
                "l_min_erpm": .double(-100_000),
                "l_max_erpm": .double(100_000),
                "l_min_duty": .double(0.005),
                "l_max_duty": .double(0.95),
                "l_watt_max": .double(1_500_000),
                "l_watt_min": .double(-1_500_000),
            ]
            let backupDirectory = URL(fileURLWithPath: "../../hardware-debug",
                                      isDirectory: true)
            let isClose: (Double, Double) -> Bool = { actual, expected in
                abs(actual - expected) <= max(1e-7, abs(expected) * 1e-6)
            }
            let alreadyRepaired = replacements.allSatisfy {
                guard let actual = motorConfig[$0.key]?.doubleValue else { return false }
                return isClose(actual, $0.value.doubleValue)
            }
            if alreadyRepaired {
                let candidates = (try? FileManager.default.contentsOfDirectory(
                    at: backupDirectory, includingPropertiesForKeys: nil))?
                    .filter {
                        $0.lastPathComponent.hasPrefix(
                            "ak80-9-v3-mcconf-before-limit-repair-")
                    }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
                guard let backupURL = candidates.last,
                      let backupData = try? Data(contentsOf: backupURL) else {
                    print("  ❌ 参数已显示为修复值，但找不到写入前备份，未执行重启")
                    exit(24)
                }
                let (backupSignature, backupValues) =
                    activeCodec.unpack(Array(backupData))
                var expected = backupValues
                for (name, value) in replacements { expected[name] = value }
                guard backupSignature == motorSignature,
                      activeCodec.pack(expected, signature: backupSignature) == motorBlob else {
                    print("  ❌ 当前参数与“备份 + 六项修复”的逐字节结果不一致，未执行重启")
                    exit(25)
                }
                guard client.reboot() else {
                    print("  ❌ 六项修复已逐字节核对，但固件重启命令发送失败")
                    exit(26)
                }
                print("  ✅ 六项修复与写入前备份逐字节核对一致，已发送固件重启")
                print("  ✅ 写入前备份：\(backupURL.path)")
                exit(0)
            }
            guard replacements.keys.allSatisfy({
                motorConfig[$0]?.doubleValue == 0
            }) else {
                print("  ❌ 六个主限制字段不再全部为 0，拒绝自动修改")
                exit(18)
            }

            try? FileManager.default.createDirectory(
                at: backupDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backupURL = backupDirectory.appendingPathComponent(
                "ak80-9-v3-mcconf-before-limit-repair-\(formatter.string(from: Date())).bin")
            do {
                try Data(motorBlob).write(to: backupURL, options: .atomic)
            } catch {
                print("  ❌ 无法保存参数备份：\(error)")
                exit(19)
            }

            var repaired = motorConfig
            for (name, value) in replacements { repaired[name] = value }
            _ = client.servoCurrent(0)
            _ = client.servoDuty(0)
            _ = client.alive()
            guard client.setMcconf(repaired, signature: motorSignature) else {
                print("  ❌ 主限制修复写入没有收到设备 ACK；备份：\(backupURL.path)")
                exit(20)
            }
            usleep(250_000)
            guard let (verifySignature, verified) = client.getMcconf(),
                  verifySignature == motorSignature,
                  replacements.allSatisfy({
                      guard let actual = verified[$0.key]?.doubleValue else { return false }
                      return isClose(actual, $0.value.doubleValue)
                  }) else {
                print("  ❌ 写入后重读校验失败；备份：\(backupURL.path)")
                exit(21)
            }
            var expected = motorConfig
            for (name, value) in replacements { expected[name] = value }
            guard activeCodec.pack(verified, signature: verifySignature)
                    == activeCodec.pack(expected, signature: motorSignature) else {
                print("  ❌ 重读发现除六个主限制外还有其他变化；备份：\(backupURL.path)")
                exit(22)
            }
            guard client.reboot() else {
                print("  ❌ 参数已写入并校验，但固件重启命令发送失败；备份：\(backupURL.path)")
                exit(23)
            }
            print("  ✅ 六个被清零的 ERPM/占空比/功率主限制已恢复并逐字节核对")
            print("  ✅ 已发送固件重启；写入前备份：\(backupURL.path)")
            exit(0)
        }
        if CommandLine.arguments.contains("--write-identical") {
            guard client.setMcconf(motorConfig, signature: motorSignature),
                  client.setAppconf(appConfig, signature: appSignature) else {
                print("  ❌ 原样写回没有收到设备 ACK")
                exit(7)
            }
            guard let (motorSignatureAfter, motorAfter) = client.getMcconf(),
                  let (appSignatureAfter, appAfter) = client.getAppconf(),
                  activeCodec.pack(motorAfter, signature: motorSignatureAfter) == motorBlob,
                  appCodec.pack(appAfter, signature: appSignatureAfter) == appBlob else {
                print("  ❌ 原样写回后的配置与写入前不同")
                exit(8)
            }
            print("  ✅ 电机/应用参数原样写回收到 ACK，重读逐字节一致")
        }
    }
    exit(0)
}

print("== CRC ==")
check("crc16(123456789)==0x31C3", CRC.crc16(Array("123456789".utf8)) == 0x31C3)
check("crc16(hello)==50018", CRC.crc16(Array("hello".utf8)) == 50018,
      "got \(CRC.crc16(Array("hello".utf8)))")
check("crc32c(123456789)==0xE3069283", CRC.crc32c(Array("123456789".utf8)) == 0xE3069283,
      String(format: "got %08x", CRC.crc32c(Array("123456789".utf8))))

print("== Packet ==")
check("fw frame == 020100000003", Packet.encodeCmd(.fwVersion).hex == "020100000003",
      Packet.encodeCmd(.fwVersion).hex)
check("encode(hello) == 020568656c6c6fc36203", Packet.encode(Array("hello".utf8)).hex == "020568656c6c6fc36203",
      Packet.encode(Array("hello".utf8)).hex)
// 长帧 + 解码往返
let big = (0..<300).map { UInt8($0 % 256) }
let dec = PacketDecoder()
let frames = dec.feed(Packet.encode(big))
check("long frame roundtrip", frames.count == 1 && frames[0] == big)
// 流式：逐字节喂两帧
let dec2 = PacketDecoder()
var got: [[UInt8]] = []
for b in Packet.encodeCmd(.getValues) + Packet.encode(big) { got += dec2.feed([b]) }
check("streaming split -> 2 frames", got.count == 2 && got[0] == [4] && got[1] == big)

print("== Rotor V3 Packet ==")
check("V3 FW frame == aa014158e5bb",
      RotorV3Packet.encodeCmd(.fwVersion).hex == "aa014158e5bb",
      RotorV3Packet.encodeCmd(.fwVersion).hex)
check("V3 IAP A1 seq 0x30 == Windows capture",
      RotorV3IAP.jumpApplication(sequence: 0x30).hex == "ec960e30a10768",
      RotorV3IAP.jumpApplication(sequence: 0x30).hex)
check("V3 IAP A1 seq 0x37 == Windows capture",
      RotorV3IAP.jumpApplication(sequence: 0x37).hex == "ec960e37a1076f",
      RotorV3IAP.jumpApplication(sequence: 0x37).hex)
check("V3 IAP A1 additive checksum wraps at UInt8",
      RotorV3IAP.jumpApplication(sequence: 0xFF).hex == "ec960effa10737",
      RotorV3IAP.jumpApplication(sequence: 0xFF).hex)

// 以下黄金向量是官方 Windows 工具真机升级时实际写入串口的原始字节，取自
// reverse-engineering/captures/capture-SUCCESSFUL-UPLOAD-ak80-9-241122.jsonl。
func hexBytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = hex.startIndex
    while i < hex.endIndex {
        let j = hex.index(i, offsetBy: 2)
        out.append(UInt8(hex[i..<j], radix: 16)!)
        i = j
    }
    return out
}
let capturedBlock1 = hexBytes(
    "a1270708d1270708c1500708812d0708f12d0708512e0708b12e0708e1500708" +
    "4146070831090708310907083109070831510708015107082146070831090708" +
    "31090708e1340708d13507083109070831090708814907083109070831090708" +
    "a1490708310907083109070831090708310907083109070831090708 0128 0708"
        .filter { !$0.isWhitespace }
)
// 0x60 MIT：真机验证过 pos/rpm 两个字段（发 1.234 / 5.678，foc_state 回读 1.23 / 5.68）。
check("V3 setPidMit 载荷恰好 21 字节且字段按 pos/rpm/torque/kp/kd 排列", {
    var w = BufWriter()
    w.u8(96)
    for v in [1.234, 5.678, 0.0, 0.0, 0.0] {
        w.u32(UInt32(bitPattern: Int32((v * 1000).rounded())))
    }
    return w.bytes.count == 21
        && w.bytes.hex == "60000004d20000162e000000000000000000000000"
}(), "载荷编码不符")

check("V3 IAP firmware block payload is 128 bytes",
      capturedBlock1.count == RotorV3IAP.blockSize,
      "\(capturedBlock1.count)")
let capturedPacket = RotorV3IAP.dataPacket(
    sequence: 0x05, sessionToken: [0x00, 0x00, 0x04, 0x05],
    blockIndex: 1, data: capturedBlock1
)
check("V3 IAP data packet == Windows capture (seq 0x05, block 1)",
      capturedPacket?.hex == "ec962d05a190000004050c00000180" + capturedBlock1.hex + "a7",
      capturedPacket?.hex ?? "nil")
let paddedTail = RotorV3IAP.dataPacket(
    sequence: 0x10, sessionToken: [0, 0, 4, 5], blockIndex: 0x0C01, data: [0xAB, 0xCD]
)
check("V3 IAP short final block padded to 128 with 0xFF",
      paddedTail?.count == 144
        && Array(paddedTail![12...14]).hex == "0c0180"
        && Array(paddedTail![17..<143]) == [UInt8](repeating: 0xFF, count: 126)
        && paddedTail?.last == paddedTail!.dropLast().reduce(UInt8(0), &+),
      "\(paddedTail?.count ?? -1)")
let gluedAcks = hexBytes(
    "7b8c2e00a10d000004050001ed" +
    "7b8c2e01a10d000004050001ee" +
    "7b8c2e02a10d000004050001ef"
)
let ackResult = RotorV3IAP.parseAcks(gluedAcks + hexBytes("7b8c2e03a10d0000"))
check("V3 IAP parses glued ACKs and keeps partial trailing frame",
      ackResult.acks.count == 3
        && ackResult.consumed == gluedAcks.count
        && ackResult.acks[0].sessionToken == [0x00, 0x00, 0x04, 0x05]
        && ackResult.acks[0].nextBlock == 1
        && ackResult.acks[2].sequence == 0x02,
      "acks=\(ackResult.acks.count) consumed=\(ackResult.consumed)")
check("V3 IAP rejects ACK with bad checksum",
      RotorV3IAP.parseAcks(hexBytes("7b8c2e00a10d000004050001ee")).acks.isEmpty,
      "accepted a corrupted ACK")
let v3Payload = [UInt8(RotorV3Comm.fwVersion.rawValue), 5, 1, 6]
    + Array("CMESC_AK80_9_SW_V3.2".utf8) + [0]
let v3Encoded = RotorV3Packet.encode(v3Payload)
let v3Decoder = RotorV3PacketDecoder()
check("V3 streaming first half incomplete",
      v3Decoder.feed(Array(v3Encoded.prefix(5))).isEmpty)
check("V3 streaming roundtrip",
      v3Decoder.feed(Array(v3Encoded.dropFirst(5))) == [v3Payload])
let v34ValuesPayload = bytesFromHex(
    "45018afcda0000000000000000000000000000000000000000000000ee0000000300000000000000510000000f00000c22000039500044897dfd6800000000000000000001000000000000000a43715ea0")
let v34Values = MotorValues.parseRotorV3(v34ValuesPayload)
check("V3.4 81-byte values accepted", v34Values != nil)
check("V3.4 values fields decoded",
      abs((v34Values?.tempFet ?? 0) - 39.4) < 0.001
        && abs((v34Values?.tempMotor ?? 0) + 80.6) < 0.001
        && abs((v34Values?.vIn ?? 0) - 23.8) < 0.001
        && v34Values?.controllerId == 104
        && v34Values?.currentControlMode == 10
        && abs((v34Values?.encoderAngle ?? 0) - 241.36963) < 0.001)

print("== Buffers ==")
var w = BufWriter(); w.f32auto(3.14159)
check("f32auto(3.14159)==40490fcf", w.bytes.hex == "40490fcf", w.bytes.hex)
var w2 = BufWriter(); w2.f32auto(-0.001234)
check("f32auto(-0.001234)==baa1be2b", w2.bytes.hex == "baa1be2b", w2.bytes.hex)
var w3 = BufWriter(); w3.f32(3.141, 1000)
check("f32(3.141,1000)==00000c45", w3.bytes.hex == "00000c45", w3.bytes.hex)
// int 往返
var w4 = BufWriter(); w4.u16(0x1234); w4.i16(-2); w4.u32(0x01020304); w4.i32(-1)
check("int big-endian layout", w4.bytes.hex == "1234fffe01020304ffffffff", w4.bytes.hex)
var r = BufReader([0x12,0x34,0xFF,0xFE]); let a = r.u16(); let b2 = r.i16()
check("read u16/i16", a == 0x1234 && b2 == -2)
// f32auto 往返
for v in [0.0, 1.0, -1.0, 3.14159265, 123456.75, -98765.5] {
    var ww = BufWriter(); ww.f32auto(v)
    var rr = BufReader(ww.bytes); let back = rr.f32auto()
    check("f32auto roundtrip \(v)", abs(back - v) < 1e-4, "got \(back)")
}

print("== Control ==")
check("set_rpm(5000)==0800001388", Control.setRpm(5000).hex == "0800001388", Control.setRpm(5000).hex)
check("set_duty(0.5)==050000c350", Control.setDuty(0.5).hex == "050000c350", Control.setDuty(0.5).hex)
check("set_pos(90)==09055d4a80", Control.setPos(90).hex == "09055d4a80", Control.setPos(90).hex)
check("V3 set_rpm(5000)==4900001388",
      RotorV3Control.setRpm(5000).hex == "4900001388",
      RotorV3Control.setRpm(5000).hex)
check("V3 set_pos(90)==4a055d4a80",
      RotorV3Control.setPos(90).hex == "4a055d4a80",
      RotorV3Control.setPos(90).hex)
check("V3 alive == 5f",
      RotorV3Packet.encodeCmd(.alive).hex == "aa015fab1abb",
      RotorV3Packet.encodeCmd(.alive).hex)
check("V3 reboot == 5e",
      RotorV3Packet.encodeCmd(.reboot).hex == "aa015ebb3bbb",
      RotorV3Packet.encodeCmd(.reboot).hex)
check("jump servo cmd == 100", Packet.encodeCmd(.jumpToCmesc).hex == "0201642c2203",
      Packet.encodeCmd(.jumpToCmesc).hex)
check("jump MIT cmd == 101", Packet.encodeCmd(.jumpToMit).hex == "0201653c0303",
      Packet.encodeCmd(.jumpToMit).hex)

print("== Config（等价于 Python 核心）==")
let xmlPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "../../reverse-engineering/extracted-config/v1/mcconf_150params.xml"
if let codec = ConfigCodec.load(path: xmlPath) {
    let appXmlPath = "../../reverse-engineering/extracted-config/v1/appconf_132params.xml"
    let appCodec = ConfigCodec.load(path: appXmlPath)
    check("signature == 0xdc733ebd", codec.signature == 0xdc733ebd, String(format: "%08x", codec.signature))
    check("transmittable == 139", codec.order.count == 139, "\(codec.order.count)")
    let blob = codec.pack(codec.defaults())
    check("pack len == 437", blob.count == 437, "\(blob.count)")
    check("pack crc16 == 5819", CRC.crc16(blob) == 5819, "\(CRC.crc16(blob))")
    let (sig, vals) = codec.unpack(blob)
    check("unpack sig == signature", sig == codec.signature)
    check("byte-stable repack", codec.pack(vals) == blob)
    var electricalValues = vals
    electricalValues["foc_motor_r"] = .double(0.088048)
    electricalValues["foc_motor_l"] = .double(0.00001645)
    electricalValues["foc_motor_flux_linkage"] = .double(0.0026701)
    let electricalReadback = codec.unpack(codec.pack(electricalValues)).1
    check("quantized electrical parameters verify without false mismatch",
          codec.changedParameterNames(expected: electricalValues,
                                      actual: electricalReadback).isEmpty)
    var changedElectricalReadback = electricalReadback
    changedElectricalReadback["foc_motor_r"] = .double(0.1)
    check("real parameter mismatch is detected",
          codec.changedParameterNames(expected: electricalValues,
                                      actual: changedElectricalReadback)
            .contains("foc_motor_r"))
    let disabledOutputValues: [String: ParamValue] = [
        "l_current_max_scale": .double(0),
        "l_current_min_scale": .double(1),
        "l_max_erpm": .double(100_000),
        "l_min_erpm": .double(-100_000),
        "l_max_duty": .double(0.95),
        "l_min_duty": .double(0.005),
        "l_watt_max": .double(1_500_000),
        "l_watt_min": .double(-1_500_000)
    ]
    check("zero output scale detected",
          MotorOutputConfigurationHealth(values: disabledOutputValues).disabledFields
            == ["l_current_max_scale"])
    let healthyOutputValues = disabledOutputValues.merging(
        ["l_current_max_scale": .double(1)]) { _, replacement in replacement }
    check("healthy output limits accepted",
          MotorOutputConfigurationHealth(values: healthyOutputValues).isOutputEnabled)
    let v34HealthyOutputValues = healthyOutputValues.merging(
        ["l_min_duty": .double(0)]) { _, replacement in replacement }
    check("V3.4 zero minimum duty accepted",
          MotorOutputConfigurationHealth(values: v34HealthyOutputValues).isOutputEnabled)

    print("== End-to-end（客户端↔模拟器）==")
    let sim = MotorSimulator(codec: codec, appconfCodec: appCodec)
    let client = Client(LoopbackTransport(sim), codec: codec, appconfCodec: appCodec)
    if let fw = client.fwVersion() {
        check("fw 3.66 / hw '60'", fw.major == 3 && fw.minor == 66 && fw.hw == "60", "\(fw)")
    } else { check("fwVersion", false, "nil") }
    client.servoRpm(5000)
    if let v = client.getValues() {
        check("rpm reflects 5000", abs(v.rpm - 5000) < 1, "\(v.rpm)")
        check("v_in == 48", abs(v.vIn - 48) < 0.05, "\(v.vIn)")
    } else { check("getValues", false) }
    if let (gsig, gvals) = client.getMcconf() {
        check("device sig == codec sig", gsig == codec.signature)
        var m = gvals
        let orig = m["pwm_mode"]!.intValue
        m["pwm_mode"] = .int(orig != 2 ? 2 : 1)
        client.setMcconf(m)
        check("set_mcconf 签名通过", sim.lastSetSignatureOk == true)
        if let (_, v2) = client.getMcconf() {
            check("写回生效", v2["pwm_mode"]!.intValue == m["pwm_mode"]!.intValue)
        }
        client.setMcconf(m, signature: 0xDEADBEEF)
        check("错误签名被拒", sim.lastSetSignatureOk == false)
    } else { check("getMcconf", false) }
    if let (_, values) = client.getAppconf() {
        var updated = values
        updated["controller_id"] = .int(104)
        check("写入 appconf", client.setAppconf(updated))
        check("CAN ID 写回生效",
              client.getAppconf()?.1["controller_id"]?.intValue == 104
                && sim.controllerId == 104)
    } else {
        check("getAppconf", false, "nil")
    }
    var firmwareImage = (0..<1_000).map { UInt8(($0 * 37 + 11) & 0xFF) }
    // 上传流的第二个 384-byte 分块正好对应 image[378..<762]；保持为擦除态，
    // 验证客户端会跳过全 0xFF 块而 bootloader 仍能按 size+CRC16 正确提交。
    firmwareImage.replaceSubrange(378..<762,
                                  with: [UInt8](repeating: 0xFF, count: 384))
    var reportedProgress = 0.0
    let uploadResult = client.uploadNewApp(image: firmwareImage) {
        reportedProgress = $0
    }
    switch uploadResult {
    case .success(let receipt):
        check("固件擦除长度使用原始镜像长度", sim.firmwareEraseSize == firmwareImage.count)
        check("固件上传头含 size/CRC 且传输完成",
              receipt.transmittedSize == firmwareImage.count + 6
                && receipt.imageCRC16 == CRC.crc16(firmwareImage)
                && reportedProgress == 1)
        check("全 0xFF 分块被跳过", receipt.skippedChunks == 1)
    case .failure(let failure):
        check("固件上传", false, "\(failure)")
    }
    client.jumpToBootloader()
    check("Bootloader 按 size/CRC 提交原始镜像",
          sim.lastUploadedFirmware == firmwareImage)
    check("进入 Bootloader 命令生效", client.fwVersion()?.hw == "BOOT_60")
    client.jumpToMitMode()
    check("MIT 模式切换命令生效", client.fwVersion()?.hw == "MIT_60")
    client.jumpToBootloader()
    client.jumpToServoMode()
    check("Servo 模式切换命令生效", client.fwVersion()?.hw == "CMESC_60")
    if let rl = client.detectMotorRL() {
        check("R/L 辨识回包",
              abs(rl.resistance - 0.08583) < 0.000001
                && abs(rl.inductanceMicrohenry - 15) < 0.001)
    } else {
        check("R/L 辨识回包", false, "nil")
    }
    check("磁链辨识回包",
          abs((client.detectMotorFluxLinkage(current: 5, minERPM: 2000,
                                             lowDuty: 0.05, resistance: 0.08583) ?? 0)
              - 0.003264) < 0.0000001)
    if let encoder = client.detectEncoder(current: 10) {
        check("编码器辨识回包",
              abs(encoder.offset - 123.4) < 0.001
                && abs(encoder.ratio - 9) < 0.001 && !encoder.inverted)
    } else {
        check("编码器辨识回包", false, "nil")
    }

    print("== 设备档案与自动识别 ==")
func identity(_ hw: String, _ proto: RotorWireProtocol) -> DeviceIdentity {
    DeviceIdentity(hardwareName: hw, firmwareMajor: 5, firmwareMinor: 1, wireProtocol: proto)
}
check("V3.4 硬件串匹配到 V3.4 档案",
      DeviceRegistry.profile(for: identity("CMESC_AK80_9_SW_V3.4", .v3)).id == "ak80-9.v3.4",
      DeviceRegistry.profile(for: identity("CMESC_AK80_9_SW_V3.4", .v3)).id)
check("V3.2 硬件串匹配到 V3.2 档案",
      DeviceRegistry.profile(for: identity("CMESC_AK80_9_SW_V3.2", .v3)).id == "ak80-9.v3.2",
      DeviceRegistry.profile(for: identity("CMESC_AK80_9_SW_V3.2", .v3)).id)
check("V2 硬件串匹配到 V2 档案",
      DeviceRegistry.profile(for: identity("CMESC_AK80_9_SW_V2.1", .vesc)).id == "ak80-9.v2",
      DeviceRegistry.profile(for: identity("CMESC_AK80_9_SW_V2.1", .vesc)).id)
// 认不出就退到兜底而不是失败——未登记的 VESC 控制器仍应能连上用起来。
check("未知设备退到通用档案而非失败",
      DeviceRegistry.profile(for: identity("SOME_OTHER_ESC_V9", .v3)).id == "generic.v3",
      DeviceRegistry.profile(for: identity("SOME_OTHER_ESC_V9", .v3)).id)
// V3.4 把 MIT 控制并进了主固件，V3.2 还在独立应用里——这是两者能力的实际差别。
check("只有 V3.4 声称具备 MIT 控制",
      DeviceRegistry.ak80_9_v3_4.supports(.mitControl)
        && !DeviceRegistry.ak80_9_v3_2.supports(.mitControl),
      "V3.4=\(DeviceRegistry.ak80_9_v3_4.supports(.mitControl)) V3.2=\(DeviceRegistry.ak80_9_v3_2.supports(.mitControl))")
// 遥测布局差 4 字节，按错的解会把合法回包整条丢掉。
check("V3.2 与 V3.4 遥测布局不同",
      DeviceRegistry.ak80_9_v3_2.telemetryLayout == .v3WithOuterEncoder
        && DeviceRegistry.ak80_9_v3_4.telemetryLayout == .v3,
      "")
check("V3 档案用 IAP 上传，V2 用暂存区上传",
      DeviceRegistry.ak80_9_v3_4.makeUploadStrategy().name == "IAP raw"
        && DeviceRegistry.ak80_9_v2.makeUploadStrategy().name == "VESC staging",
      "")
check("档案 id 唯一",
      Set(DeviceRegistry.all.map(\.id)).count == DeviceRegistry.all.count, "")

// 上层判断设备行为必须走能力查询。判断世代的写法每加一款设备就要回头
// 找齐所有点，正是本次重构要消除的模式；用测试把它钉住，防止悄悄长回来。
// 递归扫描整个应用层，而不是写死文件名——文件一改名就不再被扫到，
// 那种“漏扫即通过”正是本断言要防的东西。
let appRoot = "Sources/RotorApp"
let appSources: [String] = {
    guard let e = FileManager.default.enumerator(atPath: appRoot) else { return [] }
    return e.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.sorted()
}()
var behaviouralBranches: [String] = []
var unreadableSources: [String] = []
for name in appSources {
    let url = URL(fileURLWithPath: "\(appRoot)/\(name)")
    // 读不到就必须报错。静默跳过会让本断言在错误的工作目录下变成
    // “没扫到任何东西所以全过”——假绿比没有断言更危险。
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        unreadableSources.append(name); continue
    }
    for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        // 显示协议名、把协议传给按协议索引的固件目录，都不是行为分支。
        guard line.contains("wireProtocol ==") || line.contains("wireProtocol !=") else { continue }
        behaviouralBranches.append("\(name):\(index + 1)")
    }
}
check("应用层源码可扫（防止断言在错误工作目录下假绿）",
      !appSources.isEmpty && unreadableSources.isEmpty,
      "读不到: \(unreadableSources.joined(separator: ", "))；请在 src/RotorKit 下运行")
check("应用层不再按协议世代分支（改为能力查询）",
      unreadableSources.isEmpty && behaviouralBranches.isEmpty,
      behaviouralBranches.joined(separator: ", "))
check("V2 需要写后沉降，V3 可立即回读",
      !DeviceRegistry.ak80_9_v2.supports(.immediateConfigReadback)
        && DeviceRegistry.ak80_9_v3_4.supports(.immediateConfigReadback), "")
check("配置 schema 由档案决定",
      DeviceRegistry.ak80_9_v2.configSchema == .vesc
        && DeviceRegistry.ak80_9_v3_2.configSchema == .v3, "")

// 格式化崩溃防线。真机上曾因 `L10n.t(handshakingBaud, b)` 把 Int 喂给 %@ 直接
// 段错误——模拟器分支不走那行，测试一路绿到用户点“连接”。现在 t(_:_:) 只收
// String，编译器兜住了类型；这里再钉住两条静态不变量：
//   1) 占位符只能是 %@（其它 specifier 不会被替换，会原样显示给用户）；
//   2) 每份译文的占位符数量必须与英文一致（译文自带一份格式串，漂了就错位）。
var badSpecifierKeys: [String] = []
for key in L10nKeyRegistry.all {
    var rest = Substring(key.en)
    while let r = rest.range(of: "%") {
        let after = rest[r.upperBound...]
        guard let c = after.first else { badSpecifierKeys.append(key.id); break }
        // %@ 是占位符，%% 是字面百分号；其余 specifier 不会被替换，会原样显示。
        if c != "@" && c != "%" { badSpecifierKeys.append("\(key.id) (%\(c))") }
        rest = after.dropFirst()
    }
}
check("翻译 key 的占位符只用 %@", badSpecifierKeys.isEmpty,
      badSpecifierKeys.prefix(4).joined(separator: ", "))

var drifted: [String] = []
for language in L10n.Language.allCases where language != .english {
    guard let table = L10n.translationTableForTesting(language) else { continue }
    for key in L10nKeyRegistry.all {
        guard let translated = table[key.id], !translated.isEmpty else { continue }
        let en = key.en.components(separatedBy: "%@").count - 1
        let zh = translated.components(separatedBy: "%@").count - 1
        if en != zh { drifted.append("\(key.id) [\(language.rawValue)] \(en)≠\(zh)") }
    }
}
check("各语言译文的占位符数量与英文一致", drifted.isEmpty,
      drifted.prefix(4).joined(separator: ", "))

// 自制固件的档案必须排在官方 V3.4 之前：注册表取第一个匹配，而 "V3.4C" 同样
// 包含 "V3.4"。顺序写反了，刷了自制固件的电机会被认成官方的——而那正是加这条
// 档案要解决的问题。
let customIdentity = DeviceIdentity(hardwareName: "CMESC_AK80_9_SC_V3.4",
                                    firmwareMajor: 5, firmwareMinor: 1, wireProtocol: .v3)
let stockIdentity = DeviceIdentity(hardwareName: "CMESC_AK80_9_SW_V3.4",
                                   firmwareMajor: 5, firmwareMinor: 1, wireProtocol: .v3)
check("自制固件识别为 v3.4custom",
      DeviceRegistry.profile(for: customIdentity).id == "ak80-9.v3.4custom",
      DeviceRegistry.profile(for: customIdentity).id)
check("官方固件仍识别为 v3.4",
      DeviceRegistry.profile(for: stockIdentity).id == "ak80-9.v3.4",
      DeviceRegistry.profile(for: stockIdentity).id)
// 顺序**必须**无关紧要。之前的实现是"第一个匹配的胜"，于是正确性寄托在数组
// 顺序上——而顺序会被人无意改动，且改动后不报错，只是默默认错设备。
// 现在按最长模式选，这条断言把"顺序无关"变成可执行的性质：把注册表反过来，
// 每一条身份的识别结果必须逐条不变。
let identities = DeviceRegistry.all.map {
    DeviceIdentity(hardwareName: "CMESC_AK80_9_SW_\($0.hardwareMatch)",
                   firmwareMajor: 5, firmwareMinor: 1, wireProtocol: $0.wireProtocol)
} + [customIdentity, stockIdentity]
func pick(_ pool: [DeviceProfile], _ id: DeviceIdentity) -> String {
    let hits = pool.filter { $0.matches(id) }
    return (hits.max { $0.hardwareMatch.count < $1.hardwareMatch.count })?.id ?? "(fallback)"
}
let forward = identities.map { pick(DeviceRegistry.all, $0) }
let reversed = identities.map { pick(DeviceRegistry.all.reversed(), $0) }
check("识别结果与注册表顺序无关（正序 vs 逆序逐条一致）",
      forward == reversed, "\(forward) vs \(reversed)")
check("每条已登记档案都能认出自己",
      DeviceRegistry.all.allSatisfy { p in
          !p.hardwareMatch.isEmpty && pick(DeviceRegistry.all,
              DeviceIdentity(hardwareName: "CMESC_AK80_9_SW_\(p.hardwareMatch)",
                             firmwareMajor: 5, firmwareMinor: 1,
                             wireProtocol: p.wireProtocol)) == p.id
      }, "")

print("== 本地化完整性 ==")
// 翻译文件不是 SPM 资源，测试直接读仓库里的源文件。
let l10nRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Localization")
let l10nKeys = L10nKeyRegistry.all
check("key id 无重复",
      Set(l10nKeys.map(\.id)).count == l10nKeys.count,
      "重复：\(Dictionary(grouping: l10nKeys, by: \.id).filter { $0.value.count > 1 }.keys.sorted())")
check("英文原文全部非空", l10nKeys.allSatisfy { !$0.en.isEmpty }, "存在空英文原文")
func placeholderCount(_ text: String) -> Int {
    // "%%" 是转义的百分号，不是占位符。
    text.replacingOccurrences(of: "%%", with: "").components(separatedBy: "%").count - 1
}
for language in L10n.Language.allCases where language != .english {
    let url = l10nRoot.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")
    guard let table = NSDictionary(contentsOf: url) as? [String: String] else {
        check("\(language.rawValue) 翻译文件可解析", false, url.path)
        continue
    }
    check("\(language.rawValue) 翻译文件可解析", true, "\(table.count) 条")
    let missing = l10nKeys.map(\.id).filter { table[$0] == nil }
    check("\(language.rawValue) 无漏翻", missing.isEmpty,
          "缺 \(missing.count) 条，例如 \(missing.prefix(5))")
    let orphans = Set(table.keys).subtracting(l10nKeys.map(\.id))
    check("\(language.rawValue) 无孤儿 key", orphans.isEmpty,
          "多 \(orphans.count) 条，例如 \(orphans.sorted().prefix(5))")
    let mismatched = l10nKeys.filter {
        guard let translated = table[$0.id] else { return false }
        return placeholderCount($0.en) != placeholderCount(translated)
    }
    check("\(language.rawValue) 格式占位符数量一致", mismatched.isEmpty,
          "不一致：\(mismatched.map(\.id).prefix(5))")
}

print("== V3 固件升级回环 ==")
    let v3Transport = V3FirmwareTransport()
    let v3Client = Client(v3Transport, codec: codec, v3Codec: codec,
                          appconfCodec: appCodec)
    check("V3 固件握手选择 0xAA 分支",
          v3Client.fwVersion()?.hw == "CMESC_AK80_9_SW_V3.4"
            && v3Client.wireProtocol == .v3)
    let v3Image = (0..<3_500).map { UInt8(($0 * 13 + 7) & 0xFF) }

    // 未进 bootloader：真机对 IAP 原始包完全不回应。实现必须**有界失败**，
    // 而不是像官方工具那样无限重发同一块。
    switch IAPRawUpload(maxAttemptsPerBlock: 2).upload(image: v3Image, host: v3Client, progress: nil) {
    case .success:
        check("未进 bootloader 时上传必须失败", false, "竟然成功了")
    case .failure(let failure):
        check("未进 bootloader 时上传有界失败于第 0 块",
              failure == .blockNotAcknowledged(block: 0, attempts: 2), "\(failure)")
    }
    check("设备确实收到了包但按真机行为不回应",
          v3Transport.packetsIgnoredBeforeBootloader > 0,
          "\(v3Transport.packetsIgnoredBeforeBootloader)")

    // 进 bootloader 后走完整上传。
    check("V3 进 bootloader 收到 0x42 ACK", v3Client.enterFirmwareBootloader())
    let blockCount = (v3Image.count + RotorV3IAP.blockSize - 1) / RotorV3IAP.blockSize
    switch IAPRawUpload().upload(image: v3Image, host: v3Client, progress: nil) {
    case .success(let receipt):
        check("V3 R-LINK 上传全部块被 ACK",
              receipt.imageSize == v3Image.count && receipt.writtenChunks == blockCount,
              "written=\(receipt.writtenChunks) expected=\(blockCount)")
    case .failure(let failure):
        check("V3 R-LINK 上传", false, "\(failure)")
    }
    let padding = blockCount * RotorV3IAP.blockSize - v3Image.count
    check("设备重组出的镜像与原镜像一致（末块 0xFF 补齐）",
          v3Transport.receivedImage == v3Image + [UInt8](repeating: 0xFF, count: padding),
          "device=\(v3Transport.receivedImage.count) expected=\(v3Image.count + padding)")
    check("实现采纳了设备下发的会话令牌（无令牌被拒包）",
          v3Transport.rejectedTokenPackets == 0, "\(v3Transport.rejectedTokenPackets)")
    // 第一次上传的控制包发生在进 bootloader 之前，被设备忽略且不计数。
    check("数据流前恰好一个控制包", v3Transport.controlPacketCount == 1,
          "\(v3Transport.controlPacketCount)")
    check("V3 跳回 Servo 命令已发送", v3Client.jumpToServoMode())
} else {
    check("加载 XML \(xmlPath)", false, "解析失败")
}

print(failures == 0 ? "\n全部通过 ✅" : "\n\(failures) 项失败 ❌")
exit(failures == 0 ? 0 : 1)
