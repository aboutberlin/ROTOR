import Foundation
import RotorKit

/// 升级后重连的核对结果。
enum FirmwareRecoveryOutcome {
    case verified(hardware: String)
    case mismatch(expected: String, actual: String)
    case waiting(completed: Int, limit: Int)
    case exhausted
}

enum FirmwareUpgradeError: LocalizedError {
    case connectionLost
    case backup
    case bootloader
    case upload(FirmwareUploadFailure)
    case finalize

    var errorDescription: String? {
        switch self {
        case .connectionLost: return L10n.t(L10n.Status.connectionLost)
        case .backup: return L10n.t(L10n.Status.backupFailedNoErase)
        case .bootloader: return L10n.t(L10n.Status.bootloaderEntryFailed)
        case .upload(let failure): return L10n.t(L10n.Status.uploadFailed, "\(failure)")
        case .finalize: return L10n.t(L10n.Status.uploadDoneJumpFailed)
        }
    }
}
