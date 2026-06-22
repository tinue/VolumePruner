import Foundation
import OSLog

private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "VolumeInfo")

struct VolumeInfo: Identifiable, Hashable, Sendable {
    let id: URL
    let name: String
    let fsTypeName: String
    let totalBytes: Int64
    let isRemovable: Bool
    let isEjectable: Bool

    init?(url: URL) {
        var stats = statfs()
        guard statfs(url.path, &stats) == 0 else {
            log.warning("statfs failed for \(url.path, privacy: .public)")
            return nil
        }

        self.id = url
        self.fsTypeName = withUnsafeBytes(of: stats.f_fstypename) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }.lowercased()
        self.totalBytes = Int64(stats.f_blocks) * Int64(stats.f_bsize)

        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        let values = try? url.resourceValues(forKeys: keys)
        self.name = values?.volumeName ?? url.lastPathComponent
        self.isRemovable = values?.volumeIsRemovable ?? false
        self.isEjectable = values?.volumeIsEjectable ?? false

        let n = self.name, fs = self.fsTypeName, sz = self.totalBytes, rm = self.isRemovable
        log.debug("Found volume: name=\(n, privacy: .public) fs=\(fs, privacy: .public) size=\(sz) removable=\(rm) path=\(url.path, privacy: .public)")
    }
}
