import Foundation

struct CleanResult: Sendable {
    let filesRemoved: Int
    let bytesReclaimed: Int64
    let errors: [String]

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: bytesReclaimed, countStyle: .file)
    }
}

struct CleanEvent: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let volumeName: String
    let filesRemoved: Int
    let bytesReclaimed: Int64

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: bytesReclaimed, countStyle: .file)
    }
}
