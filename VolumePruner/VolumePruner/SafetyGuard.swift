import Foundation
import OSLog

private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "SafetyGuard")

enum SafetyGuard {
    static let allowedFilesystems: Set<String> = ["msdos", "exfat", "smbfs", "cifs", "ntfs"]

    static func isEligible(volume: VolumeInfo, maxGB: Int = 2000) -> Bool {
        guard allowedFilesystems.contains(volume.fsTypeName) else {
            log.debug("REJECT \(volume.name, privacy: .public) — fs=\(volume.fsTypeName, privacy: .public) not in allowlist")
            return false
        }
        guard volume.id.path != "/" else {
            log.debug("REJECT \(volume.name, privacy: .public) — is root volume")
            return false
        }
        guard !volume.id.path.hasPrefix("/System/Volumes/") else {
            log.debug("REJECT \(volume.name, privacy: .public) — under /System/Volumes/")
            return false
        }
        let maxBytes = Int64(maxGB) * 1_000_000_000
        guard volume.totalBytes < maxBytes else {
            log.debug("REJECT \(volume.name, privacy: .public) — size \(volume.totalBytes) >= limit \(maxBytes)")
            return false
        }
        log.debug("ACCEPT \(volume.name, privacy: .public) — fs=\(volume.fsTypeName, privacy: .public) path=\(volume.id.path, privacy: .public)")
        return true
    }
}
