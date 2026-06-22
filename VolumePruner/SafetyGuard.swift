import Foundation
import OSLog

private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "SafetyGuard")

enum SafetyGuard {
    // Only these local filesystem types are cleaned. Network shares are excluded
    // because modern Windows/Linux handle Mac metadata natively, and we have no
    // way to safely enumerate a slow or unreachable remote volume.
    static let allowedFilesystems: Set<String> = ["msdos", "exfat", "ntfs"]

    // Checked separately from the allowlist so the log message says "network share"
    // rather than the generic "not in allowlist" — useful when debugging why a
    // mapped drive isn't appearing in the menu.
    static let networkFilesystems: Set<String> = ["smbfs", "cifs"]

    // Returns true only for volumes that are safe and meaningful to clean.
    static func isEligible(volume: VolumeInfo, maxGB: Int = 2000) -> Bool {
        if networkFilesystems.contains(volume.fsTypeName) {
            log.debug("REJECT \(volume.name, privacy: .public) — fs=\(volume.fsTypeName, privacy: .public) network share (not supported)")
            return false
        }
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
