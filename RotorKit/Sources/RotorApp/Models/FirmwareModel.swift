import Foundation
import Combine
import RotorKit

/// 固件目录、镜像选择、备份与升级。
final class FirmwareModel: ObservableObject {
    @Published var firmwareCacheValid: [String: Bool] = [:]
    @Published var selectedFirmware: FirmwareImageSelection?
    @Published var firmwareOperationStatus = L10n.t(L10n.Status.selectFirmware)
    @Published var firmwareProgress = 0.0
    @Published var firmwareBusy = false
    @Published var firmwareRiskAcknowledged = false
    /// 自编译镜像的第二道确认，与 `firmwareRiskAcknowledged` 分开，
    /// 避免“确认过供电稳定”被顺带当成“确认过镜像来源”。
    @Published var customFirmwareAcknowledged = false
    @Published var lastFirmwareBackupURL: URL?

    private let session: DeviceSession
    /// 由组合根注入。
    weak var connection: ConnectionModel?
    weak var telemetry: TelemetryModel?
    weak var control: ControlModel?
    weak var config: ConfigModel?

    init(session: DeviceSession) {
        self.session = session
        refreshFirmwareCache()
    }

    // MARK: - 可用性

    var firmwareCompatibilityText: String {
        guard connection?.connected == true else { return L10n.t(L10n.Status.connectFirstFirmware) }
        guard let selection = selectedFirmware else { return L10n.t(L10n.Status.firmwareNotSelected) }
        switch compatibility(of: selection) {
        case .success:
            let branch = connection?.wireProtocol.title ?? ""
            return L10n.t(L10n.Status.firmwareExactMatch, branch, selection.record.role.rawValue)
        case .failure(let error):
            return error.localizedDescription
        }
    }

    var canStartFirmwareUpgrade: Bool {
        guard connection?.connected == true, !firmwareBusy, firmwareRiskAcknowledged,
              let selection = selectedFirmware else { return false }
        // 自编译镜像不在官方白名单里，走结构性校验 + 额外一道显式确认。
        if selection.isCustom { return customFirmwareAcknowledged }
        if case .success = compatibility(of: selection) { return true }
        return false
    }

    /// 「恢复到应用」的可用条件。**刻意比别的操作宽松**：
    ///
    /// 需要救砖的时候，设备多半已经不在"正常连上、握手过、模式认出来"的状态了。
    /// 把救砖按钮锁在那些前提后面，等于**它唯一有用的时刻恰好是它不可点的时刻**。
    /// 所以这里只要求"串口开着且当前没在忙"——够发那两轮 A1 就行。
    /// 也不要求勾选风险确认：这个操作不擦除、不写固件，只发跳转序列。
    var canRecoverV3Application: Bool {
        // ⛔ **不要**写成 `session.client != nil`。我第一版就是那么写的，而 client
        // 只有握手成功才存在——于是"设备不应答"这个唯一需要救砖的场景里，
        // 救砖按钮恰好是灰的。真机上被这条卡过一次。
        // 只要选了口、当前不忙就该可点：那两轮 A1 挂在 transport 上，不需要 client。
        !(connection?.selectedPort.isEmpty ?? true) && !firmwareBusy
    }

    /// 固件目录按协议分支索引，所以这里读协议是取索引键，不是按世代分支行为。
    private func compatibility(
        of selection: FirmwareImageSelection
    ) -> Result<Void, FirmwareCatalogError> {
        FirmwareCatalog.compatibility(
            of: selection.record,
            protocolBranch: connection?.wireProtocol ?? .vesc,
            hardwareName: connection?.deviceHardwareName ?? "",
            mode: connection?.firmwareMode ?? .unknown)
    }

    // MARK: - 目录与镜像选择

    func refreshFirmwareCache() {
        firmwareCacheValid = Dictionary(uniqueKeysWithValues:
            FirmwareCatalog.records.map { ($0.id, FirmwareCatalog.cachedAndValid($0)) })
    }

    func downloadOfficialFirmware(recordID: String) {
        guard !firmwareBusy, let record = FirmwareCatalog.record(id: recordID) else { return }
        firmwareBusy = true
        firmwareProgress = 0
        firmwareOperationStatus = L10n.t(L10n.Status.downloadingFirmware, record.title, record.version)
        session.io.async {
            do {
                let selection = try FirmwareCatalog.install(record)
                DispatchQueue.main.async {
                    self.selectedFirmware = selection
                    self.firmwareBusy = false
                    self.firmwareProgress = 1
                    self.refreshFirmwareCache()
                    self.firmwareOperationStatus = L10n.t(L10n.Status.firmwareChecksumOk)
                }
            } catch {
                DispatchQueue.main.async {
                    self.firmwareBusy = false
                    self.firmwareOperationStatus = error.localizedDescription
                }
            }
        }
    }

    /// 自编译 / 魔改镜像。官方上位机只能从内置下拉里选，本工具刻意开放这条路，
    /// 但要求镜像通过 Cortex-M 向量表结构校验，并额外勾一次确认。
    func selectCustomFirmware(_ url: URL) {
        guard !firmwareBusy else { return }
        firmwareBusy = true
        customFirmwareAcknowledged = false
        firmwareOperationStatus = L10n.t(L10n.Status.checkingCustomImage)
        session.io.async {
            do {
                let selection = try FirmwareCatalog.inspectCustomImage(url)
                DispatchQueue.main.async {
                    self.selectedFirmware = selection
                    self.firmwareBusy = false
                    self.firmwareOperationStatus =
                        L10n.t(L10n.Status.customImageValid, selection.vectorTable?.summary ?? "")
                }
            } catch {
                DispatchQueue.main.async {
                    self.selectedFirmware = nil
                    self.firmwareBusy = false
                    self.firmwareOperationStatus = error.localizedDescription
                }
            }
        }
    }

    func selectLocalFirmware(_ url: URL) {
        guard !firmwareBusy else { return }
        firmwareBusy = true
        firmwareOperationStatus = L10n.t(L10n.Status.verifyingLocalImage)
        session.io.async {
            do {
                let selection = try FirmwareCatalog.inspectLocalImage(url)
                DispatchQueue.main.async {
                    self.selectedFirmware = selection
                    self.firmwareBusy = false
                    self.firmwareOperationStatus = L10n.t(L10n.Status.localImageMatch)
                }
            } catch {
                DispatchQueue.main.async {
                    self.selectedFirmware = nil
                    self.firmwareBusy = false
                    self.firmwareOperationStatus = error.localizedDescription
                }
            }
        }
    }

    // MARK: - 备份

    func backupFirmwareInfoAndParameters() {
        guard connection?.connected == true, !firmwareBusy else { return }
        firmwareBusy = true
        firmwareOperationStatus = L10n.t(L10n.Status.backingUpFirmware)
        session.io.async {
            do {
                let url = try self.createFirmwareBackupOnIO()
                DispatchQueue.main.async {
                    self.lastFirmwareBackupURL = url
                    self.firmwareBusy = false
                    self.firmwareOperationStatus = L10n.t(L10n.Status.backupComplete, url.path)
                }
            } catch {
                DispatchQueue.main.async {
                    self.firmwareBusy = false
                    self.firmwareOperationStatus = L10n.t(L10n.Status.backupFailed, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 升级

    func startFirmwareUpgrade() {
        guard canStartFirmwareUpgrade, let selection = selectedFirmware,
              let connection else { return }
        firmwareBusy = true
        firmwareProgress = 0
        firmwareOperationStatus = L10n.t(L10n.Status.finalCheckBackup)
        telemetry?.stopPolling()

        let expectedProtocol = connection.wireProtocol
        let expectedHardware = connection.deviceHardwareName
        let expectedMode = connection.firmwareMode
        session.io.async {
            do {
                self.control?.stopControlOnIO(sendStop: true)
                let image = try Data(contentsOf: selection.url)
                try FirmwareCatalog.validate(image, record: selection.record)
                if case .failure(let reason) = FirmwareCatalog.compatibility(
                    of: selection.record, protocolBranch: expectedProtocol,
                    hardwareName: expectedHardware, mode: expectedMode) {
                    throw reason
                }
                let backupURL = try self.createFirmwareBackupOnIO()
                DispatchQueue.main.async {
                    self.lastFirmwareBackupURL = backupURL
                    self.firmwareOperationStatus = L10n.t(L10n.Status.backupDonePrepareUpload)
                }

                guard let client = self.session.client else {
                    throw FirmwareUpgradeError.connectionLost
                }

                if expectedProtocol == .v3 {
                    guard client.enterFirmwareBootloader(),
                          client.activateFirmwareBootloaderLink() else {
                        throw FirmwareUpgradeError.bootloader
                    }
                    // 真机抓包显示官方在重开串口后几乎立刻开始发控制包。
                    // 此前的 5 秒等待来自“先擦除再写”的旧理论，该理论已被推翻。
                    Thread.sleep(forTimeInterval: 1.0)
                }

                // V3 走 IAP 原始帧（128 字节/块），chunkSize 对该分支无意义。
                let result = client.uploadNewApp(image: Array(image)) { progress in
                    DispatchQueue.main.async {
                        self.firmwareProgress = progress
                        self.firmwareOperationStatus = L10n.t(L10n.Status.uploadingFirmware, String(Int(progress * 100)))
                    }
                }
                switch result {
                case .failure(let failure): throw FirmwareUpgradeError.upload(failure)
                case .success: break
                }

                let finalCommandOK: Bool
                if expectedProtocol == .v3 {
                    // 镜像已在 IAP 通道中写完，直接执行官方应用返回序列，
                    // 由 Bootloader 校验新镜像。
                    finalCommandOK = client.recoverV3ServoApplication(
                        enterBootloaderFirst: false
                    ) { attempt in
                        DispatchQueue.main.async {
                            self.firmwareOperationStatus =
                                L10n.t(L10n.Status.firmwareStartingServo, String(attempt))
                        }
                    }
                } else {
                    finalCommandOK = client.jumpToBootloader()
                }
                guard finalCommandOK else { throw FirmwareUpgradeError.finalize }
                // V3 的两轮 A1 已在上一步完成 close/reopen 和 0x41 校验；
                // 此处只释放正常应用态串口，再由组合根统一重连核对目标版本。
                if expectedProtocol != .v3 { usleep(3_000_000) }
                client.close()
                self.session.client = nil

                DispatchQueue.main.async {
                    let attempts = connection.beginFirmwareRecovery(
                        expectedHardware: selection.record.protocolBranch == .v3 ? "V3.4" : "V2.1",
                        isIAPBranch: expectedProtocol == .v3)
                    self.firmwareOperationStatus =
                        L10n.t(L10n.Status.reconnectVerifyVersion, String(attempts))
                }
            } catch {
                DispatchQueue.main.async {
                    self.firmwareBusy = false
                    self.firmwareRiskAcknowledged = false
                    self.firmwareOperationStatus = L10n.t(L10n.Status.upgradeStopped, error.localizedDescription)
                    if connection.connected, connection.firmwareMode == .servo {
                        self.telemetry?.startPolling()
                    }
                }
            }
        }
    }

    /// 把设备从 IAP/bootloader 状态踢回应用。**不擦除、不写固件**，只发官方那两轮 A1。
    ///
    /// 这个方法原来叫 `testV3IAPRoundTrip`，挂在一个「测试 IAP 回环（不擦除）」按钮上。
    /// 那个按钮已删除，因为它在工程上站不住：测试通过你还是要真刷一次（真刷会再进一次
    /// IAP），测试失败设备却停在回不来的状态——**一个预检如果失败会把你推到比没检查
    /// 更坏的位置，它就不是安全措施。** 同一段代码留下来做**恢复**是对的，做**预检**是错的。
    func recoverV3Application() {
        guard canRecoverV3Application else { return }
        firmwareBusy = true
        firmwareProgress = 0
        firmwareOperationStatus = L10n.t(L10n.Status.enteringIap)
        telemetry?.stopPolling()

        let port = connection?.selectedPort ?? ""
        let preferredBaud = connection?.baud ?? 921600

        session.io.async {
            self.control?.stopControlOnIO(sendStop: true)

            // 没有活着的 client 也要能救——这正是需要救砖的那种局面。
            // 两轮 A1 挂在 transport 上，只要串口开得起来就能发。
            let client: Client
            let openedHere: Bool
            if let existing = self.session.client {
                client = existing
                openedHere = false
            } else {
                guard let t = SerialTransport(port: port, baud: preferredBaud) else {
                    DispatchQueue.main.async {
                        self.firmwareBusy = false
                        self.firmwareOperationStatus = L10n.t(L10n.Status.iapCannotOpenPort)
                    }
                    return
                }
                client = Client(t)
                openedHere = true
            }
            defer { if openedHere { client.close() } }

            let recovered = client.recoverV3ServoApplication { round in
                DispatchQueue.main.async {
                    self.firmwareProgress = Double(round) / 2.0
                    self.firmwareOperationStatus =
                        L10n.t(L10n.Status.iapJumpSequence, String(round))
                }
            }

            if recovered {
                DispatchQueue.main.async {
                    self.firmwareBusy = false
                    self.firmwareProgress = 1
                    self.firmwareOperationStatus = L10n.t(L10n.Status.iapSuccess)
                    self.telemetry?.startPolling()
                }
            } else {
                // ⛔ 这里原来调 `prepareForBootloaderTimeout()` 然后 close + 断开。
                // 那个调用把线路设成 **1200 7N1 + RTS/DTR 拉住** —— 正是**进 bootloader
                // 的门**。也就是说：恢复失败之后，代码反而把设备**朝 bootloader 又推了
                // 一步**，然后断线走人，用户什么都做不了。
                //
                // 2026-08-06 真机上就是这么卡住一台 AK80-9 的：应用还在跑（电机按力矩
                // 转动、CAN 命令收得到），但 UART 不回话，而进 bootloader 的命令是发给
                // 应用的 ⇒ 界面上再没有任何出路。
                //
                // 现在失败就是失败：**保持连接不动**，把下一步告诉用户。
                DispatchQueue.main.async {
                    self.firmwareBusy = false
                    self.firmwareProgress = 0
                    self.firmwareOperationStatus = L10n.t(L10n.Status.iapFailedNextSteps)
                }
            }
        }
    }

    /// 重连后由组合根调用，核对实际读到的硬件串是否就是升级目标。
    func reportRecoveryOutcome(_ outcome: FirmwareRecoveryOutcome) {
        switch outcome {
        case .verified(let hardware):
            firmwareOperationStatus = L10n.t(L10n.Status.upgradeVerified, hardware)
            firmwareBusy = false
            firmwareProgress = 1
            firmwareRiskAcknowledged = false
        case .mismatch(let expected, let actual):
            firmwareOperationStatus = L10n.t(L10n.Status.versionMismatch, expected, actual)
            firmwareBusy = false
            firmwareProgress = 1
            firmwareRiskAcknowledged = false
        case .waiting(let completed, let limit):
            firmwareOperationStatus = L10n.t(L10n.Status.firmwareWaitStartup, String(completed), String(limit))
        case .exhausted:
            firmwareBusy = false
            firmwareRiskAcknowledged = false
            firmwareOperationStatus = L10n.t(L10n.Status.bootloaderTimeoutManualRecovery)
        }
    }

    private func createFirmwareBackupOnIO() throws -> URL {
        guard let client = session.client else { throw FirmwareUpgradeError.connectionLost }
        let motor = client.getMcconf()
        let app = client.getAppconf()
        guard motor != nil || app != nil else { throw FirmwareUpgradeError.backup }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let root = FirmwareCatalog.rootURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        if let (signature, values) = motor, let codec = client.configurationCodec {
            let bytes = codec.pack(values, signature: signature)
            try Data(bytes).write(to: root.appendingPathComponent("mcconf.bin"), options: .atomic)
        }
        if let (signature, values) = app, let codec = client.appconfCodec {
            let bytes = codec.pack(values, signature: signature)
            try Data(bytes).write(to: root.appendingPathComponent("appconf.bin"), options: .atomic)
        }
        let identity = connection?.backupIdentity ?? ConnectionIdentitySnapshot()
        let metadata: [String: Any] = [
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "hardware": identity.hardwareName,
            "firmware": identity.firmwareText,
            "wire_protocol": identity.protocolTitle,
            "motor_mode": identity.modeTitle,
            "port": identity.port,
            "baud": identity.baud,
            "raw_flash_readback": false,
            "raw_flash_note": L10n.t(L10n.Status.rawFlashNote)
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata,
                                                       options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: root.appendingPathComponent("firmware-info.json"),
                               options: .atomic)
        return root
    }
}
