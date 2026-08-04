import CryptoKit
import Foundation
import RotorKit

enum FirmwareImageRole: String, Codable {
    case servo = "Servo"
    case mit = "MIT"
    case combined = "Boot + Servo + MIT"
}

struct OfficialFirmwareRecord: Identifiable, Hashable {
    enum Extraction: Hashable {
        case zipEntry(String)
        case qtResource(executableEntry: String, offset: Int, length: Int)
    }

    let id: String
    let title: String
    let version: String
    let role: FirmwareImageRole
    let protocolBranch: RotorWireProtocol
    let relativePath: String
    let byteCount: Int
    let sha256: String
    let archiveURL: URL
    let archiveFileName: String
    let archiveSHA256: String
    let extraction: Extraction
    let flashSupported: Bool
    let note: String

    var cachedURL: URL {
        FirmwareCatalog.rootURL.appendingPathComponent(relativePath)
    }
}

struct FirmwareImageSelection: Equatable {
    let url: URL
    let record: OfficialFirmwareRecord
    let sha256: String
    let byteCount: Int
    let sourceDescription: String
    /// 自编译/魔改镜像：不在官方 SHA 白名单内，改用结构性校验 + 用户显式确认。
    var isCustom: Bool = false
    /// 结构性校验读出的向量表，供 UI 展示（自编译镜像才有值）。
    var vectorTable: FirmwareVectorTable? = nil
}

/// Cortex-M 镜像开头的两个字：初始主栈指针与复位向量。
struct FirmwareVectorTable: Equatable {
    let initialStackPointer: UInt32
    let resetHandler: UInt32

    /// Servo 槽镜像应满足：SP 落在 SRAM，复位向量落在 Flash 且带 Thumb 位。
    var looksLikeCortexMImage: Bool {
        (0x2000_0000...0x2010_0000).contains(initialStackPointer)
            && (0x0800_0000...0x0820_0000).contains(resetHandler)
            && (resetHandler & 1) == 1
    }

    var summary: String {
        String(format: "SP 0x%08X · Reset 0x%08X", initialStackPointer, resetHandler)
    }
}

enum FirmwareCatalogError: LocalizedError {
    case downloadFailed(String)
    case archiveHash(expected: String, actual: String)
    case extractionFailed(String)
    case imageSize(expected: Int, actual: Int)
    case imageHash(expected: String, actual: String)
    case unknownImage(String)
    case incompatible(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason): return L10n.t(L10n.FirmwareCatalog.downloadFailedTemplate, reason)
        case .archiveHash(let expected, let actual):
            return L10n.t(L10n.FirmwareCatalog.archiveHashTemplate, expected, actual)
        case .extractionFailed(let reason): return L10n.t(L10n.FirmwareCatalog.extractionFailedTemplate, reason)
        case .imageSize(let expected, let actual):
            return L10n.t(L10n.FirmwareCatalog.imageSizeTemplate, String(expected), String(actual))
        case .imageHash(let expected, let actual):
            return L10n.t(L10n.FirmwareCatalog.imageHashTemplate, expected, actual)
        case .unknownImage(let hash): return L10n.t(L10n.FirmwareCatalog.unknownImageTemplate, hash)
        case .incompatible(let reason): return L10n.t(L10n.FirmwareCatalog.incompatibleTemplate, reason)
        }
    }
}

enum FirmwareCatalog {
    static let rootURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask).first!
        return base.appendingPathComponent("Rotor/OfficialFirmware", isDirectory: true)
    }()

    // 每个记录同时固定“官方归档 SHA-256”和“最终镜像 SHA-256”。官网若在相同 URL
    // 替换文件，应用会停止而不是盲目接受。V3 镜像是官方 Qt 资源中的原始数据段。
    static let records: [OfficialFirmwareRecord] = [
        OfficialFirmwareRecord(
            id: "ak80-9-v3.4-servo-260515",
            title: "AK80-9 V3.4",
            version: "V3.4 · 260515",
            role: .servo,
            protocolBranch: .v3,
            relativePath: "AK80-9/V3.4/260515/AK80_9_V3_260515_V3.bin",
            byteCount: 393_208,
            sha256: "5dbda5eac4743854b2b26f55f5ade37cfd95497e727048f46c96426cf0a8bbd1",
            archiveURL: URL(string: "https://www.cubemars.com/data/cms/202606/ak-series-v3-2-3-upper-computer-for-ak-3-0-motor.zip")!,
            archiveFileName: "ak-series-v3-2-3-upper-computer-for-ak-3-0-motor.zip",
            archiveSHA256: "38de313cd0e2eb1ab7b980431030c11c30147b3f25f9b2614c6b98b6393b9f84",
            extraction: .qtResource(executableEntry: "CubeMarsTool_V3.2.3.exe",
                                    offset: 6_598_911, length: 393_208),
            flashSupported: true,
            note: L10n.t(L10n.FirmwareCatalog.recordV3_4Note)
        ),
        OfficialFirmwareRecord(
            id: "ak80-9-v2.1-servo-20240118",
            title: "AK80-9 V2.1",
            version: "V2.1 · 20240118",
            role: .servo,
            protocolBranch: .vesc,
            relativePath: "AK80-9/V2.1/20240118/CMESC_SERVO_APP_AK80_9_100_20240118.bin",
            byteCount: 393_208,
            sha256: "b9a92f16e2850170af86ca22547a07dbbd83f6c244b4f9dbf08ac911912b39d6",
            archiveURL: URL(string: "https://www.cubemars.com/images/file/202601/AK80-9kv100%E5%9B%BA%E4%BB%B6.zip")!,
            archiveFileName: "AK80-9kv100-firmware-202601.zip",
            archiveSHA256: "b68706def02c16be0ba4b34e9c0b4d6850edc8bba122ec972ecfc52ab4c35001",
            extraction: .zipEntry("AK80-9 100kv 2.1/CMESC_SERVO_APP_AK80_9_100_20240118.bin"),
            flashSupported: true,
            note: L10n.t(L10n.FirmwareCatalog.recordV2_1ServoNote)
        ),
        OfficialFirmwareRecord(
            id: "ak80-9-v2.1-mit-20240118",
            title: "AK80-9 V2.1",
            version: "V2.1 · 20240118",
            role: .mit,
            protocolBranch: .vesc,
            relativePath: "AK80-9/V2.1/20240118/CMESC_MIT_APP_AK80_9_100_20240118.bin",
            byteCount: 47_888,
            sha256: "ce10bdbc8e410ac7f37644ca9623fec201ab07d054b07581dee0f71d14f007bc",
            archiveURL: URL(string: "https://www.cubemars.com/images/file/202601/AK80-9kv100%E5%9B%BA%E4%BB%B6.zip")!,
            archiveFileName: "AK80-9kv100-firmware-202601.zip",
            archiveSHA256: "b68706def02c16be0ba4b34e9c0b4d6850edc8bba122ec972ecfc52ab4c35001",
            extraction: .zipEntry("AK80-9 100kv 2.1/CMESC_MIT_APP_AK80_9_100_20240118.bin"),
            flashSupported: false,
            note: L10n.t(L10n.FirmwareCatalog.recordV2_1MITNote)
        ),
        OfficialFirmwareRecord(
            id: "ak80-9-v2.1-full-20240119",
            title: L10n.t(L10n.FirmwareCatalog.v21FullImageTitle),
            version: "HV2.1 · FV1.1 · 20240119",
            role: .combined,
            protocolBranch: .vesc,
            relativePath: "AK80-9/V2.1/20240118/AK80-9_100KV_HV2.1_FV1.1_BOOT+SERVOAPP+MITAPP_20240119.hex",
            byteCount: 2_525_323,
            sha256: "506c882d506b85a57cebd6420fcb88de6849163e8b94958272c1218969de97b5",
            archiveURL: URL(string: "https://www.cubemars.com/images/file/202601/AK80-9kv100%E5%9B%BA%E4%BB%B6.zip")!,
            archiveFileName: "AK80-9kv100-firmware-202601.zip",
            archiveSHA256: "b68706def02c16be0ba4b34e9c0b4d6850edc8bba122ec972ecfc52ab4c35001",
            extraction: .zipEntry("AK80-9 100kv 2.1/AK80-9_100KV_HV2.1_FV1.1_BOOT+SERVOAPP+MITAPP_20240119.hex"),
            flashSupported: false,
            note: L10n.t(L10n.FirmwareCatalog.recordV2_1FullNote)
        )
    ]

    static func record(id: String) -> OfficialFirmwareRecord? {
        records.first { $0.id == id }
    }

    static func cachedAndValid(_ record: OfficialFirmwareRecord) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: record.cachedURL.path),
              (attributes[.size] as? NSNumber)?.intValue == record.byteCount,
              let digest = try? sha256(of: record.cachedURL) else { return false }
        return digest == record.sha256
    }

    static func install(_ record: OfficialFirmwareRecord) throws -> FirmwareImageSelection {
        try FileManager.default.createDirectory(at: rootURL,
                                                withIntermediateDirectories: true)
        if cachedAndValid(record) {
            return FirmwareImageSelection(url: record.cachedURL, record: record,
                                          sha256: record.sha256,
                                          byteCount: record.byteCount,
                                          sourceDescription: L10n.t(L10n.FirmwareCatalog.sourceCache))
        }

        let archiveURL = rootURL.appendingPathComponent(record.archiveFileName)
        if !FileManager.default.fileExists(atPath: archiveURL.path) {
            do {
                let data = try Data(contentsOf: record.archiveURL)
                try data.write(to: archiveURL, options: .atomic)
            } catch {
                throw FirmwareCatalogError.downloadFailed(error.localizedDescription)
            }
        }
        let archiveDigest = try sha256(of: archiveURL)
        guard archiveDigest == record.archiveSHA256 else {
            throw FirmwareCatalogError.archiveHash(expected: record.archiveSHA256,
                                                   actual: archiveDigest)
        }

        let imageData: Data
        switch record.extraction {
        case .zipEntry(let entry):
            imageData = try extractZipEntry(entry, from: archiveURL)
        case .qtResource(let executableEntry, let offset, let length):
            let executable = try extractZipEntry(executableEntry, from: archiveURL)
            guard offset >= 0, length > 0, offset + length <= executable.count else {
                throw FirmwareCatalogError.extractionFailed(L10n.t(L10n.FirmwareCatalog.qtResourceExtractionFailed))
            }
            imageData = executable.subdata(in: offset..<(offset + length))
        }

        try validate(imageData, record: record)
        try FileManager.default.createDirectory(
            at: record.cachedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try imageData.write(to: record.cachedURL, options: .atomic)
        return FirmwareImageSelection(url: record.cachedURL, record: record,
                                      sha256: record.sha256, byteCount: record.byteCount,
                                      sourceDescription: L10n.t(L10n.FirmwareCatalog.sourceDownload))
    }

    static func inspectLocalImage(_ url: URL) throws -> FirmwareImageSelection {
        let data = try Data(contentsOf: url)
        let digest = sha256(data)
        guard let record = records.first(where: {
            $0.sha256 == digest && $0.byteCount == data.count
        }) else {
            throw FirmwareCatalogError.unknownImage(digest)
        }
        try validate(data, record: record)
        return FirmwareImageSelection(url: url, record: record, sha256: digest,
                                      byteCount: data.count,
                                      sourceDescription: L10n.t(L10n.FirmwareCatalog.sourceLocal))
    }

    static func validate(_ data: Data, record: OfficialFirmwareRecord) throws {
        guard data.count == record.byteCount else {
            throw FirmwareCatalogError.imageSize(expected: record.byteCount,
                                                 actual: data.count)
        }
        let digest = sha256(data)
        guard digest == record.sha256 else {
            throw FirmwareCatalogError.imageHash(expected: record.sha256, actual: digest)
        }
    }

    static func compatibility(of record: OfficialFirmwareRecord,
                              protocolBranch: RotorWireProtocol,
                              hardwareName: String,
                              mode: MotorFirmwareMode) -> Result<Void, FirmwareCatalogError> {
        guard record.flashSupported else {
            return .failure(.incompatible(record.note))
        }
        guard protocolBranch == record.protocolBranch else {
            return .failure(.incompatible(L10n.t(L10n.FirmwareCatalog.protocolMismatchTemplate, protocolBranch.title, record.protocolBranch.title)))
        }
        let hardware = hardwareName.uppercased()
        guard hardware.contains("AK80_9") || hardware.contains("AK80-9") else {
            return .failure(.incompatible(L10n.t(L10n.FirmwareCatalog.hardwareNameNotAK80, hardwareName)))
        }
        switch record.protocolBranch {
        case .v3:
            guard hardware.contains("V3") else {
                return .failure(.incompatible(L10n.t(L10n.FirmwareCatalog.v3ImageOnlyForV3Hardware)))
            }
        case .vesc:
            guard !hardware.contains("_V3") else {
                return .failure(.incompatible(L10n.t(L10n.FirmwareCatalog.v2ImageCannotFlashToV3)))
            }
        }
        guard mode == .servo || mode == .bootloader else {
            return .failure(.incompatible(L10n.t(L10n.FirmwareCatalog.mustConnectServoBootloader, mode.title)))
        }
        return .success(())
    }

    static func sha256(of url: URL) throws -> String {
        sha256(try Data(contentsOf: url))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func extractZipEntry(_ entry: String, from archive: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, entry]
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        process.environment = environment

        let temporary = rootURL.appendingPathComponent(".extract-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw FirmwareCatalogError.extractionFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            throw FirmwareCatalogError.extractionFailed(L10n.t(L10n.FirmwareCatalog.unzipCannotReadEntry, entry))
        }
        try output.synchronize()
        return try Data(contentsOf: temporary)
    }
}

extension FirmwareCatalog {
    /// V3 Servo 应用槽：基址 0x08060000，容量 393,208 B（= VESC APP_MAX_SIZE）。
    static let servoSlotBase: UInt32 = 0x0806_0000
    static let servoSlotSize = 393_208

    /// 自编译 / 魔改镜像的检查。
    ///
    /// 官方上位机只允许从内置下拉里选，连自己的文件都不给刷；本工具刻意不这样做。
    /// 这里不做 SHA-256 白名单，而是做**结构性校验**：镜像必须是一个能落进 Servo
    /// 槽的合法 Cortex-M 应用。这样既拦得住“选错文件”，又不挡住自己编译的固件。
    static func inspectCustomImage(_ url: URL) throws -> FirmwareImageSelection {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        guard bytes.count >= 8, bytes.count <= servoSlotSize else {
            throw FirmwareCatalogError.imageSize(expected: servoSlotSize, actual: bytes.count)
        }
        func word(_ index: Int) -> UInt32 {
            UInt32(bytes[index])
                | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2]) << 16
                | UInt32(bytes[index + 3]) << 24
        }
        let table = FirmwareVectorTable(initialStackPointer: word(0), resetHandler: word(4))
        guard table.looksLikeCortexMImage else {
            throw FirmwareCatalogError.incompatible(
                L10n.t(L10n.FirmwareCatalog.notLegalCortexMTemplate, table.summary))
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return FirmwareImageSelection(
            url: url,
            record: customRecord(url: url, byteCount: bytes.count, sha256: digest),
            sha256: digest,
            byteCount: bytes.count,
            sourceDescription: L10n.t(L10n.FirmwareCatalog.customImageDescription),
            isCustom: true,
            vectorTable: table
        )
    }

    private static func customRecord(url: URL, byteCount: Int,
                                     sha256: String) -> OfficialFirmwareRecord {
        OfficialFirmwareRecord(
            id: "custom-\(sha256.prefix(12))",
            title: url.lastPathComponent,
            version: L10n.t(L10n.FirmwareCatalog.customImageVersion),
            role: .servo,
            protocolBranch: .v3,
            relativePath: url.path,
            byteCount: byteCount,
            sha256: sha256,
            archiveURL: url,
            archiveFileName: url.lastPathComponent,
            archiveSHA256: sha256,
            extraction: .zipEntry(url.lastPathComponent),
            flashSupported: true,
            note: L10n.t(L10n.FirmwareCatalog.customImageNote)
        )
    }
}
