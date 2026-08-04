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

    var canTestV3IAPRoundTrip: Bool {
        connection?.connected == true && session.supports(.iapFirmwareUpload)
            && connection?.firmwareMode == .servo
            && !firmwareBusy && firmwareRiskAcknowledged
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

    /// 只验证 IAP → APP 返回路径，不发送擦除或固件数据。
    /// 用于升级前确认适配器、线路状态和两轮跳转序列均可用。
    func testV3IAPRoundTrip() {
        guard canTestV3IAPRoundTrip else { return }
        firmwareBusy = true
        firmwareProgress = 0
        firmwareOperationStatus = L10n.t(L10n.Status.enteringIap)
        telemetry?.stopPolling()

        session.io.async {
            self.control?.stopControlOnIO(sendStop: true)
            guard let client = self.session.client else {
                DispatchQueue.main.async {
                    self.firmwareBusy = false
                    self.firmwareOperationStatus = L10n.t(L10n.Status.iapLostConnection)
                }
                return
            }

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
                _ = client.prepareForBootloaderTimeout()
                client.close()
                self.session.client = nil
                DispatchQueue.main.async {
                    self.connection?.markLinkLost()
                    self.firmwareBusy = false
                    self.firmwareProgress = 0
                    self.firmwareOperationStatus = L10n.t(L10n.Status.iapFailed)
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
