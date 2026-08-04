import Foundation
import Combine
import RotorKit

/// 串口选择、握手、断开，以及握手确认下来的设备身份。
///
/// 连接建立/断开会牵动其它模型（清曲线、重读配置、停控制），但本模型不去
/// 直接改它们的字段——那正是拆分前 `connect()` 变成一坨的原因。这里只发出
/// 事件，由组合根决定谁该响应。
final class ConnectionModel: ObservableObject {
    @Published var ports: [String] = []
    @Published var selectedPort: String = ""
    @Published var baud: Int = 921600
    @Published var simMode = false   // 默认真机；切“演示”用内置假电机预览
    @Published var connected = false
    @Published var status = L10n.t(L10n.Status.disconnected)
    @Published var fwText = ""
    @Published var phase: ConnPhase = .idle
    @Published var firmwareMode: MotorFirmwareMode = .unknown
    @Published var wireProtocol: RotorWireProtocol = .vesc
    @Published var modeSwitching = false
    @Published var deviceHardwareName = ""

    let bauds = [921600, 460800, 250000, 230400, 115200]

    /// 连接成功。参数是本次握手确认的固件模式。
    var onConnected: ((MotorFirmwareMode) -> Void)?
    /// 主动断开或链路丢失。
    var onDisconnected: (() -> Void)?
    /// 升级后重连的核对结果。
    var onRecoveryOutcome: ((FirmwareRecoveryOutcome) -> Void)?
    /// 需要把控制停干净时调用（在 `io` 队列上执行）。
    var stopControlOnIO: (() -> Void)?

    private let session: DeviceSession
    private var connectionAttempt: ConnectionAttempt?
    private var expectedHardwareAfterUpgrade: String?
    /// Bootloader 在没有继续升级时约 30 秒后才回到应用。升级结束后按官方工具
    /// 的实际行为关闭并重开串口，直到握手再次得到回复。
    private var firmwareReconnectAttemptsRemaining = 0
    private let firmwareReconnectAttemptLimit = 12

    init(session: DeviceSession) {
        self.session = session
        refreshPorts()
    }

    /// 备份元数据要写进去的身份信息。
    var backupIdentity: ConnectionIdentitySnapshot {
        ConnectionIdentitySnapshot(
            hardwareName: deviceHardwareName, firmwareText: fwText,
            protocolTitle: wireProtocol.title, modeTitle: firmwareMode.title,
            port: selectedPort, baud: baud)
    }

    func refreshPorts() {
        ports = SerialPorts.list()
        if selectedPort.isEmpty { selectedPort = ports.first ?? "" }
    }

    /// 升级完成后进入“等设备自己起来”的重连循环，返回本轮允许的尝试次数。
    func beginFirmwareRecovery(expectedHardware: String, isIAPBranch: Bool) -> Int {
        connected = false
        phase = .idle
        firmwareMode = .unknown
        expectedHardwareAfterUpgrade = expectedHardware
        firmwareReconnectAttemptsRemaining = isIAPBranch ? firmwareReconnectAttemptLimit : 1
        onDisconnected?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.connect() }
        return firmwareReconnectAttemptsRemaining
    }

    /// 链路已在别处关闭（例如 IAP 往返失败），把界面状态同步过来。
    func markLinkLost() {
        connected = false
        phase = .idle
        firmwareMode = .unknown
        onDisconnected?()
    }

    /// 设备不再回应（多半是断电或拔线）。
    ///
    /// **必须真的把串口关掉。** 只改界面状态是不够的：`client` 仍持有以
    /// `TIOCEXCL` 独占打开的端口，换上新电机后依然打不开，症状就是
    /// "插了新的，等了老半天才认出来"。
    func markDeviceStoppedResponding() {
        session.io.async {
            self.session.client?.close()
            self.session.client = nil
            DispatchQueue.main.async {
                self.connected = false
                self.phase = .noResponse
                self.status = L10n.t(L10n.Status.deviceStoppedResponding)
                self.fwText = ""
                self.firmwareMode = .unknown
                self.wireProtocol = .vesc
                self.deviceHardwareName = ""
                self.onDisconnected?()
            }
        }
    }

    func connect() {
        guard !connected, phase != .connecting else { return }
        let attempt = ConnectionAttempt()
        connectionAttempt = attempt
        let useSimulator = simMode
        let port = selectedPort
        let preferredBaud = baud
        // 固件恢复阶段只探测升级前已确认的波特率。普通连接仍自动扫描。
        let candidates = expectedHardwareAfterUpgrade == nil
            ? [preferredBaud] + bauds.filter { $0 != preferredBaud }
            : [preferredBaud]

        status = L10n.t(L10n.Status.connecting); phase = .connecting
        Log.conn("connect: port=\(port) baudCandidates=\(candidates)\(useSimulator ? " [simulator]" : "")")
        session.io.async { [weak self, attempt] in
            guard let self else { return }
            var transport: Transport?
            var fw: (major: Int, minor: Int, hw: String)?
            var foundClient: Client?
            var usedBaud = preferredBaud

            if useSimulator {
                let sim = MotorSimulator(codec: self.session.mcconfCodec,
                                         appconfCodec: self.session.appconfCodec)
                sim.lively = true                       // 让预览曲线动起来
                let t = LoopbackTransport(sim)
                let c = Client(t, codec: self.session.mcconfCodec,
                               v3Codec: self.session.v3McconfCodec,
                               appconfCodec: self.session.appconfCodec)
                fw = c.fwVersion(shouldCancel: { attempt.isCancelled })
                if fw != nil { transport = t; foundClient = c }
            } else {
                // 自动扫波特率：先试选中的，再试其余；谁回合法 FW_VERSION 用谁。
                for b in candidates {
                    if attempt.isCancelled { break }
                    DispatchQueue.main.async { self.status = L10n.t(L10n.Status.handshakingBaud, String(b)) }
                    guard let s = SerialTransport(port: port, baud: b) else { continue }
                    if attempt.isCancelled { s.close(); break }
                    let c = Client(s, codec: self.session.mcconfCodec,
                                   v3Codec: self.session.v3McconfCodec,
                                   appconfCodec: self.session.appconfCodec)
                    if let f = c.fwVersion(shouldCancel: { attempt.isCancelled }) {
                        Log.conn("handshake OK @\(b): FW \(f.major).\(f.minor) HW=\(f.hw)")
                        fw = f; transport = s; usedBaud = b; foundClient = c; break
                    }
                    Log.conn("handshake: no response @\(b)")
                    if self.expectedHardwareAfterUpgrade != nil {
                        _ = c.prepareForBootloaderTimeout()
                    }
                    s.close()   // ★ 握手失败必须关串口，否则端口被锁死，再次连接打不开
                }
            }

            if attempt.isCancelled {
                transport?.close()
                DispatchQueue.main.async {
                    guard self.connectionAttempt === attempt else { return }
                    self.connectionAttempt = nil
                    self.phase = .idle
                    self.status = L10n.t(L10n.Status.connectionCancelled)
                }
                return
            }

            self.session.client = foundClient
            DispatchQueue.main.async {
                guard self.connectionAttempt === attempt else {
                    self.session.io.async { transport?.close() }
                    return
                }
                self.connectionAttempt = nil
                if let fw, transport != nil {
                    self.finishSuccessfulHandshake(fw: fw, client: foundClient,
                                                   baud: usedBaud, useSimulator: useSimulator)
                } else {
                    self.session.client = nil
                    self.finishFailedHandshake(useSimulator: useSimulator)
                }
            }
        }
    }

    private func finishSuccessfulHandshake(fw: (major: Int, minor: Int, hw: String),
                                           client: Client?, baud usedBaud: Int,
                                           useSimulator: Bool) {
        connected = true
        phase = .connected
        baud = usedBaud
        firmwareMode = useSimulator ? .servo : MotorFirmwareMode.detect(hw: fw.hw)
        wireProtocol = client?.wireProtocol ?? .vesc
        deviceHardwareName = fw.hw
        Log.conn("profile=\(client?.profile.id ?? "(none)")"
            + " telemetry=\(client?.profile.telemetryLayout.rawValue ?? "?")"
            + " schema=\(client?.profile.configSchema.rawValue ?? "?")")
        let protocolTitle = client?.wireProtocol.title ?? "UART"
        fwText = "FW \(fw.major).\(fw.minor) · HW \(fw.hw) · \(protocolTitle)"
        status = useSimulator
            ? L10n.t(L10n.Status.connectedSimulator)
            : L10n.t(L10n.Status.connectedDetails, String(usedBaud), firmwareMode.title, protocolTitle)

        if let expected = expectedHardwareAfterUpgrade {
            onRecoveryOutcome?(fw.hw.uppercased().contains(expected.uppercased())
                ? .verified(hardware: fw.hw)
                : .mismatch(expected: expected, actual: fw.hw))
            expectedHardwareAfterUpgrade = nil
            firmwareReconnectAttemptsRemaining = 0
        }
        onConnected?(firmwareMode)
    }

    private func finishFailedHandshake(useSimulator: Bool) {
        guard expectedHardwareAfterUpgrade != nil else {
            phase = .noResponse
            status = useSimulator ? L10n.t(L10n.Status.simulatorNoResponse)
                                  : L10n.t(L10n.Status.noResponseHelp)
            Log.conn("handshake failed: no response at any candidate baud")
            return
        }
        guard firmwareReconnectAttemptsRemaining > 0 else {
            phase = .noResponse
            status = L10n.t(L10n.Status.noResponseHelp)
            onRecoveryOutcome?(.exhausted)
            return
        }

        let completed = firmwareReconnectAttemptLimit - firmwareReconnectAttemptsRemaining + 1
        firmwareReconnectAttemptsRemaining -= 1
        if firmwareReconnectAttemptsRemaining > 0 {
            phase = .idle
            status = L10n.t(L10n.Status.bootloaderWaiting)
            onRecoveryOutcome?(.waiting(completed: completed, limit: firmwareReconnectAttemptLimit))
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard !self.connected, self.phase == .idle,
                      self.expectedHardwareAfterUpgrade != nil else { return }
                self.connect()
            }
        } else {
            phase = .noResponse
            status = L10n.t(L10n.Status.firmwareRecoveryFailed)
            onRecoveryOutcome?(.exhausted)
        }
    }

    func cancelConnection() {
        guard phase == .connecting else { return }
        connectionAttempt?.cancel()
        status = L10n.t(L10n.Status.stoppingConnection)
    }

    func disconnect() {
        if phase == .connecting {
            cancelConnection()
            return
        }
        session.io.async {
            self.stopControlOnIO?()
            self.session.client?.close()
            self.session.client = nil
            DispatchQueue.main.async {
                self.connected = false
                self.phase = .idle
                self.status = L10n.t(L10n.Status.disconnected)
                self.fwText = ""
                self.firmwareMode = .unknown
                self.wireProtocol = .vesc
                self.deviceHardwareName = ""
                self.onDisconnected?()
            }
        }
    }

    // MARK: - Servo / MIT 固件模式

    func switchFirmwareMode(to target: MotorFirmwareMode) {
        guard connected, !modeSwitching, target != firmwareMode,
              target == .servo || target == .mit else { return }
        modeSwitching = true
        status = L10n.t(L10n.Status.modeSwitching)
        onDisconnected?()

        session.io.async {
            self.stopControlOnIO?()
            // 与官方上位机完全一致：
            // 1) 当前固件进入 Bootloader；
            // 2) 等待后，把目标模式命令每秒发送一次、共 5 次；
            // 3) 再等设备重启并重新握手确认实际模式。
            let bootloaderOK = self.session.client?.jumpToBootloader() ?? false
            var targetSendOK = false
            if bootloaderOK {
                for attempt in 1...5 {
                    usleep(1_000_000)
                    let sent = target == .servo
                        ? (self.session.client?.jumpToServoMode() ?? false)
                        : (self.session.client?.jumpToMitMode() ?? false)
                    targetSendOK = targetSendOK || sent
                    DispatchQueue.main.async {
                        self.status = L10n.t(L10n.Status.writingMode, target.title, String(attempt))
                    }
                }
            }
            usleep(1_000_000)
            self.session.client?.close()
            self.session.client = nil

            DispatchQueue.main.async {
                self.connected = false
                self.phase = .idle
                self.firmwareMode = .unknown
                self.modeSwitching = false
                self.onDisconnected?()
                if bootloaderOK && targetSendOK {
                    self.status = L10n.t(L10n.Status.modeSwitchSent)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        guard !self.connected, self.phase == .idle else { return }
                        self.connect()
                    }
                } else {
                    self.status = L10n.t(L10n.Status.modeSwitchFailed)
                }
            }
        }
    }
}

/// 写进备份元数据的一次性身份快照。
struct ConnectionIdentitySnapshot {
    var hardwareName = ""
    var firmwareText = ""
    var protocolTitle = ""
    var modeTitle = ""
    var port = ""
    var baud = 0
}

enum ConnPhase { case idle, connecting, connected, noResponse }

enum MotorFirmwareMode: String {
    case unknown, servo, mit, bootloader

    static func detect(hw: String) -> MotorFirmwareMode {
        let value = hw.uppercased()
        if value.contains("BOOT") { return .bootloader }
        if value.contains("CMESC") { return .servo }
        if value.contains("MIT") { return .mit }
        return .unknown
    }

    var title: String {
        switch self {
        case .servo: return "Servo"
        case .mit: return "MIT"
        case .bootloader: return "Bootloader"
        case .unknown: return L10n.t(L10n.Status.unknownMode)
        }
    }
}

private final class ConnectionAttempt {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
