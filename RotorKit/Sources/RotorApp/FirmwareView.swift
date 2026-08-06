import AppKit
import SwiftUI
import RotorKit

/// 固件页按“一步解锁一步”的顺序组织：连接 → 选镜像 → 备份 → 确认升级。
/// 未解锁的步骤整体置灰且不可交互，避免像官方上位机那样在上传过程中
/// 所有按钮仍可点击、顺序全靠用户自己猜。
struct FirmwareView: View {
    @EnvironmentObject var connection: ConnectionModel
    @EnvironmentObject var firmware: FirmwareModel
    @State private var pickedRecordID: String = FirmwareCatalog.records.first?.id ?? ""

    // 自制镜像目录的内容。**不缓存成 static**——用户会在应用运行期间往目录里丢文件
    // （刷完一版改一版是常态），缓存住就得重启才看得见。
    @State private var selfCompiled: [SelfCompiledImage] = []
    @State private var pickedSelfCompiledID: String = ""

    private enum StepState {
        case locked, active, done
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                step1Connect
                step2SelectImage
                step3Backup
                step4Upgrade
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .onAppear { firmware.refreshFirmwareCache() }
    }

    // MARK: - 步骤状态

    private var step1State: StepState { connection.connected ? .done : .active }

    private var step2State: StepState {
        guard connection.connected else { return .locked }
        return firmware.selectedFirmware == nil ? .active : .done
    }

    private var step3State: StepState {
        guard firmware.selectedFirmware != nil else { return .locked }
        return firmware.lastFirmwareBackupURL == nil ? .active : .done
    }

    private var step4State: StepState {
        firmware.lastFirmwareBackupURL == nil ? .locked : .active
    }

    // MARK: - 步骤 1

    private var step1Connect: some View {
        StepCard(index: 1, title: L10n.t(L10n.Firmware.step1Title), state: step1State,
                 hint: L10n.t(L10n.Firmware.step1Hint)) {
            if connection.connected {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Label(connection.deviceHardwareName, systemImage: "cpu")
                        .font(.headline.monospaced())
                    Text(connection.fwText).font(.callout.monospaced())
                    Spacer()
                    Text(connection.firmwareMode.title)
                    Text(connection.wireProtocol.title)
                }
            } else {
                Text(L10n.Firmware.notConnectedYet).foregroundStyle(.secondary)
            }

            Divider()
            recoveryRow
        }
    }

    /// 救砖入口。**刻意放在第 1 步、常驻可见、不受后面步骤的门限制。**
    ///
    /// 需要它的时候，设备多半已经不在"正常连上"的状态了——把它锁在
    /// "选好镜像 / 备份完 / 勾了风险"后面，等于它唯一有用的时刻恰好不可点。
    private var recoveryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    firmware.recoverV3Application()
                } label: {
                    Label(L10n.t(L10n.Firmware.recoverToApp), systemImage: "lifepreserver")
                }
                .disabled(!firmware.canRecoverV3Application)
                .help(L10n.t(L10n.Firmware.recoverToAppHelp))
                Spacer()
            }
            Text(L10n.t(L10n.Firmware.recoverToAppHint))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 步骤 2

    private var pickedRecord: OfficialFirmwareRecord? {
        FirmwareCatalog.record(id: pickedRecordID)
    }

    private var step2SelectImage: some View {
        StepCard(index: 2, title: L10n.t(L10n.Firmware.step2Title), state: step2State,
                 hint: L10n.t(L10n.Firmware.step2Hint)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Picker(L10n.t(L10n.Firmware.officialCatalog), selection: $pickedRecordID) {
                        ForEach(FirmwareCatalog.records) { record in
                            Text("\(record.title) · \(record.version) · \(record.role.rawValue)")
                                .tag(record.id)
                        }
                    }
                    .frame(maxWidth: 420)

                    if firmware.firmwareCacheValid[pickedRecordID] == true {
                        Label(L10n.t(L10n.Firmware.verifyOK), systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                    Button(firmware.firmwareCacheValid[pickedRecordID] == true ? L10n.t(L10n.Firmware.select) : L10n.t(L10n.Firmware.downloadAndVerify)) {
                        firmware.downloadOfficialFirmware(recordID: pickedRecordID)
                    }
                    .disabled(firmware.firmwareBusy || pickedRecord?.flashSupported != true)
                    Spacer()
                }

                if let record = pickedRecord {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.note).font(.caption).foregroundStyle(.secondary)
                        Text("\(record.byteCount.formatted()) B · SHA-256 \(record.sha256.prefix(16))…")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        if !record.flashSupported {
                            Label(L10n.t(L10n.Firmware.archiveOnly), systemImage: "lock.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                Divider()

                // ── 自制镜像：固定目录 + 下拉 ──
                //
                // 这里刻意**不是**只给一个文件选择器。自制镜像会反复刷（改一版刷一版），
                // 而它们躺在仓库深处；每次现找现点是纯摩擦，更糟的是**选错文件不会
                // 立刻报错**——结构校验看得出"不是合法镜像"，看不出"是另一台电机的镜像"。
                // 固定目录 + 下拉把"选哪个文件"从每次的判断变成一次性的整理。
                // 下拉里**必须显示 SHA 前缀**：同名文件改了内容是最容易刷错的一种情况，
                // 文件名看不出区别，SHA 看得出。
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(L10n.t(L10n.Firmware.selfCompiledCatalog))
                            .font(.callout.weight(.medium))

                        if selfCompiled.isEmpty {
                            Text(L10n.t(L10n.Firmware.selfCompiledEmpty))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("", selection: $pickedSelfCompiledID) {
                                Text(L10n.t(L10n.Firmware.selfCompiledNone)).tag("")
                                ForEach(selfCompiled) { image in
                                    Text(image.label).tag(image.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 460)

                            Button(L10n.t(L10n.Firmware.select)) {
                                if let image = selfCompiled.first(where: { $0.id == pickedSelfCompiledID }) {
                                    firmware.selectCustomFirmware(image.url)
                                }
                            }
                            .disabled(firmware.firmwareBusy || pickedSelfCompiledID.isEmpty)
                        }

                        Spacer()

                        Button {
                            // 目录不存在时 scan 会就地建出来——用户点开应当看到一个空目录，
                            // 而不是一个报错。
                            selfCompiled = FirmwareCatalog.scanSelfCompiled()
                            NSWorkspace.shared.open(FirmwareCatalog.selfCompiledURL)
                        } label: {
                            Label(L10n.t(L10n.Firmware.revealSelfCompiled), systemImage: "folder.badge.gearshape")
                        }
                        .disabled(firmware.firmwareBusy)

                        Button {
                            selfCompiled = FirmwareCatalog.scanSelfCompiled()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help(L10n.t(L10n.Firmware.rescanSelfCompiled))
                        .disabled(firmware.firmwareBusy)
                    }

                    Text(FirmwareCatalog.selfCompiledURL.path)
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .onAppear { selfCompiled = FirmwareCatalog.scanSelfCompiled() }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        chooseFirmware(custom: false)
                    } label: {
                        Label(L10n.t(L10n.Firmware.localOfficialFile), systemImage: "folder")
                    }
                    .disabled(firmware.firmwareBusy)
                    .help(L10n.Firmware.localOfficialFileHelp)

                    Button {
                        chooseFirmware(custom: true)
                    } label: {
                        Label(L10n.t(L10n.Firmware.customCompiledImage), systemImage: "hammer")
                    }
                    .disabled(firmware.firmwareBusy)
                    .help("""
                    用于刷写你自己编译或修改的固件。
                    不做 SHA-256 白名单，改为结构性校验：镜像必须能落进 Servo 槽
                    （≤ 393,208 B），且开头的 Cortex-M 向量表合法——
                    初始 SP 在 SRAM(0x2000_0000+)、复位向量在 Flash(0x0800_0000+) 且带 Thumb 位。
                    这能拦住“选错文件”，但拦不住“固件本身有 bug”。
                    """)
                    Spacer()
                }

                selectedImageSummary
            }
        }
    }

    @ViewBuilder
    private var selectedImageSummary: some View {
        if let selection = firmware.selectedFirmware {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(L10n.Firmware.pendingImage).font(.caption).foregroundStyle(.secondary)
                    Text(selection.record.title).font(.callout.weight(.medium))
                    if selection.isCustom {
                        Text(L10n.Firmware.customCompiled)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    Label(firmware.firmwareCompatibilityText,
                          systemImage: firmware.canStartFirmwareUpgrade
                            ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(compatibilityColor)
                }
                Text(selection.url.path).font(.caption2.monospaced())
                    .textSelection(.enabled).foregroundStyle(.secondary)
                if let table = selection.vectorTable {
                    Text(L10n.t(L10n.Firmware.vectorTableSummary, table.summary))
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if selection.isCustom {
                    Toggle(L10n.t(L10n.Firmware.customFirmwareAcknowledgment),
                           isOn: $firmware.customFirmwareAcknowledged)
                        .font(.caption)
                        .disabled(firmware.firmwareBusy)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 步骤 3

    private var step3Backup: some View {
        StepCard(index: 3, title: L10n.t(L10n.Firmware.step3Title), state: step3State,
                 hint: L10n.t(L10n.Firmware.step3Hint)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        firmware.backupFirmwareInfoAndParameters()
                    } label: {
                        Label(L10n.t(L10n.Firmware.exportFirmwareAndBackup), systemImage: "archivebox")
                    }
                    .disabled(!connection.connected || firmware.firmwareBusy)

                    if let url = firmware.lastFirmwareBackupURL {
                        Button(L10n.t(L10n.Firmware.showInFinder)) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        Label(L10n.t(L10n.Firmware.backupComplete), systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                }
                Label(L10n.t(L10n.Firmware.backupNote),
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 步骤 4

    private var step4Upgrade: some View {
        StepCard(index: 4, title: L10n.t(L10n.Firmware.step4Title), state: step4State,
                 hint: L10n.t(L10n.Firmware.step4Hint)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.t(L10n.Firmware.powerOffWarning),
                       isOn: $firmware.firmwareRiskAcknowledged)
                    .disabled(firmware.firmwareBusy)

                // ⛔ 这里曾经有一个「测试 IAP 回环（不擦除）」按钮。**已删除，别加回来。**
                //
                // 它的本意是"真刷之前先验一遍上传通道"，但工程上站不住：
                //   · 测试通过 → 你还是要真刷一次，而真刷会再进一次 IAP ⇒ 没省掉任何风险
                //   · 测试失败 → 设备停在 IAP/bootloader 状态回不来 ⇒ 比不点它更糟
                // **一个预检如果失败会把你推到比没检查更坏的位置，它就不是安全措施。**
                //
                // 2026-08-06 真机上把一台 AK80-9 送进了这个状态：应用还在跑（电机按力矩
                // 转动、CAN 命令收得到），但 CAN 状态线程与 UART 命令线程都不回话，
                // 而进 bootloader 的命令是发给应用的 ⇒ 没有软件出路，只剩 SWD。
                //
                // 进 bootloader 的标志写在 RTC->BKP1R（VBAT 域），**扛得住普通复位**，
                // 所以软复位 0x5E 也救不回来。
                //
                // 取代它的是下面那个常驻的「恢复到应用」按钮——救砖入口不能被步骤门锁住。
                HStack(spacing: 10) {
                    Button {
                        firmware.startFirmwareUpgrade()
                    } label: {
                        Label(L10n.t(L10n.Firmware.startUpgrade), systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!firmware.canStartFirmwareUpgrade)
                    Spacer()
                }

                if firmware.firmwareBusy {
                    ProgressView(value: firmware.firmwareProgress)
                        .frame(maxWidth: .infinity)
                }
                Text(firmware.firmwareOperationStatus)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            }
        }
    }

    // MARK: - 辅助

    private var compatibilityColor: Color {
        guard let selection = firmware.selectedFirmware, connection.connected else { return .secondary }
        if selection.isCustom {
            return firmware.customFirmwareAcknowledged ? .green : .orange
        }
        if case .success = FirmwareCatalog.compatibility(
            of: selection.record,
            protocolBranch: connection.wireProtocol,
            hardwareName: connection.deviceHardwareName,
            mode: connection.firmwareMode) { return .green }
        return .orange
    }

    private var statusColor: Color {
        let status = firmware.firmwareOperationStatus
        if status.contains(L10n.t(L10n.Firmware.statusFailed)) || status.contains(L10n.t(L10n.Firmware.statusStopped)) || status.contains(L10n.t(L10n.Firmware.statusMismatch)) {
            return .red
        }
        if status.contains(L10n.t(L10n.Firmware.statusPassed)) || status.contains(L10n.t(L10n.Firmware.statusComplete)) { return .green }
        return .secondary
    }

    private func chooseFirmware(custom: Bool) {
        let panel = NSOpenPanel()
        panel.title = custom ? L10n.t(L10n.Firmware.selectCustomImageTitle) : L10n.t(L10n.Firmware.selectOfficialFileTitle)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if custom {
            firmware.selectCustomFirmware(url)
        } else {
            firmware.selectLocalFirmware(url)
        }
    }

    // MARK: - 分步卡片

    private struct StepCard<Content: View>: View {
        let index: Int
        let title: String
        let state: StepState
        let hint: String
        @ViewBuilder var content: () -> Content

        private var badgeColor: Color {
            switch state {
            case .locked: return .secondary
            case .active: return .accentColor
            case .done: return .green
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(badgeColor.opacity(state == .locked ? 0.18 : 1.0))
                            .frame(width: 24, height: 24)
                        if state == .done {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                        } else {
                            Text("\(index)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(state == .locked ? Color.secondary : .white)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.headline)
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state == .locked {
                        Image(systemName: "lock.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                content()
                    .disabled(state == .locked)
                    .opacity(state == .locked ? 0.4 : 1.0)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(state == .active ? Color.accentColor.opacity(0.5) : .clear,
                                  lineWidth: 1)
            )
        }
    }
}
