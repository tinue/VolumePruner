import Foundation

actor VolumeCleaner {
    static let shared = VolumeCleaner()

    private let exactNames: Set<String> = [
        ".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd",
        "Thumbs.db", "desktop.ini"
    ]

    func clean(volume: VolumeInfo, recursive: Bool) async -> CleanResult {
        var filesRemoved = 0
        var bytesReclaimed: Int64 = 0
        var errors: [String] = []
        let fm = FileManager.default

        if recursive {
            guard let enumerator = fm.enumerator(
                at: volume.id,
                includingPropertiesForKeys: [URLResourceKey.fileSizeKey, URLResourceKey.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else {
                return CleanResult(filesRemoved: 0, bytesReclaimed: 0, errors: ["Cannot enumerate volume"])
            }

            var toRemove: [URL] = []
            while let url = enumerator.nextObject() as? URL {
                let name = url.lastPathComponent
                if exactNames.contains(name) || name.hasPrefix("._") {
                    toRemove.append(url)
                    enumerator.skipDescendants()
                }
            }

            for url in toRemove {
                let size = fileSize(at: url)
                do {
                    try fm.removeItem(at: url)
                    filesRemoved += 1
                    bytesReclaimed += size
                } catch {
                    errors.append(url.lastPathComponent + ": " + error.localizedDescription)
                }
            }
        } else {
            let contents = (try? fm.contentsOfDirectory(
                at: volume.id,
                includingPropertiesForKeys: [URLResourceKey.fileSizeKey],
                options: []
            )) ?? []

            for url in contents {
                let name = url.lastPathComponent
                guard exactNames.contains(name) || name.hasPrefix("._") else { continue }

                let size = fileSize(at: url)
                do {
                    try fm.removeItem(at: url)
                    filesRemoved += 1
                    bytesReclaimed += size
                } catch {
                    errors.append(url.lastPathComponent + ": " + error.localizedDescription)
                }
            }
        }

        return CleanResult(filesRemoved: filesRemoved, bytesReclaimed: bytesReclaimed, errors: errors)
    }

    private nonisolated func fileSize(at url: URL) -> Int64 {
        guard let vals = try? url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]),
              let size = vals.fileSize else { return 0 }
        return Int64(size)
    }
}
