import Foundation

// Shared byte-count formatter — one place to change if the display style ever needs updating.
func formatBytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}

// Tracks whether a volume has known junk files, or hasn't been checked yet.
enum VolumeStatus: Sendable {
    case unknown, clean, dirty
}

// Returned by VolumeCleaner after a clean pass — counts what was removed and what failed.
struct CleanResult: Sendable {
    let filesRemoved: Int
    let bytesReclaimed: Int64
    let errors: [String]
    // True when removal failed with a permission error, so the UI can prompt for Full Disk Access.
    let hadPermissionError: Bool

    var formattedBytes: String { formatBytes(bytesReclaimed) }
}

// One entry in the recent-activity history shown in Settings.
struct CleanEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let volumeName: String
    let filesRemoved: Int
    let bytesReclaimed: Int64

    var formattedBytes: String { formatBytes(bytesReclaimed) }
}
