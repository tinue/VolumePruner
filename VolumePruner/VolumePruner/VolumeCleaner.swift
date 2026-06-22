import Foundation
import OSLog

actor VolumeCleaner {
    static let shared = VolumeCleaner()
    nonisolated private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "VolumeCleaner")

    private let exactNames: Set<String> = [
        ".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd",
        "Thumbs.db", "desktop.ini"
    ]

    func clean(volume: VolumeInfo, recursive: Bool) async -> CleanResult {
        var filesRemoved = 0
        var bytesReclaimed: Int64 = 0
        var errors: [String] = []
        let fm = FileManager.default

        log.info("Starting clean on '\(volume.name, privacy: .public)' (fs=\(volume.fsTypeName, privacy: .public) recursive=\(recursive))")
        disableSpotlight(on: volume.id.path)

        if recursive {
            guard let enumerator = fm.enumerator(
                at: volume.id,
                includingPropertiesForKeys: [URLResourceKey.fileSizeKey, URLResourceKey.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else {
                log.error("Cannot enumerate '\(volume.name, privacy: .public)'")
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
                    log.debug("Removed \(url.lastPathComponent, privacy: .public)")
                    filesRemoved += 1
                    bytesReclaimed += size
                } catch {
                    logDeleteFailure(url: url, error: error)
                    errors.append(url.lastPathComponent + ": " + error.localizedDescription)
                }
            }
        } else {
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(
                    at: volume.id,
                    includingPropertiesForKeys: [URLResourceKey.fileSizeKey],
                    options: [])
            } catch {
                log.error("Cannot list root of '\(volume.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                return CleanResult(filesRemoved: 0, bytesReclaimed: 0, errors: [error.localizedDescription])
            }

            for url in contents {
                let name = url.lastPathComponent
                guard exactNames.contains(name) || name.hasPrefix("._") else { continue }

                let size = fileSize(at: url)
                do {
                    try fm.removeItem(at: url)
                    log.debug("Removed \(url.lastPathComponent, privacy: .public)")
                    filesRemoved += 1
                    bytesReclaimed += size
                } catch {
                    logDeleteFailure(url: url, error: error)
                    errors.append(url.lastPathComponent + ": " + error.localizedDescription)
                }
            }
        }

        if errors.isEmpty {
            log.info("Clean complete: \(filesRemoved) file(s) removed, \(bytesReclaimed) bytes reclaimed")
        } else {
            log.warning("Clean finished with \(errors.count) failure(s): \(filesRemoved) removed, \(errors.joined(separator: "; "), privacy: .public)")
        }

        return CleanResult(filesRemoved: filesRemoved, bytesReclaimed: bytesReclaimed, errors: errors)
    }

    func hasJunk(volume: VolumeInfo) async -> Bool {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: volume.id,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
        return contents.contains { url in
            let name = url.lastPathComponent
            return exactNames.contains(name) || name.hasPrefix("._")
        }
    }

    // Disable Spotlight and erase its index so mds releases .Spotlight-V100.
    // -i off turns indexing off for the volume; -E erases the existing index
    // store (which removes .Spotlight-V100). Neither requires root on
    // removable non-system volumes.
    private nonisolated func disableSpotlight(on path: String) {
        runMdutil(["-i", "off", path])  // turn indexing off so -E won't re-create
        runMdutil(["-E", path])          // erase the index (removes .Spotlight-V100)
    }

    private nonisolated func runMdutil(_ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdutil")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            log.debug("mdutil \(args.joined(separator: " "), privacy: .public) exited \(task.terminationStatus)")
        } catch {
            log.warning("mdutil failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated func logDeleteFailure(url: URL, error: any Error) {
        let posix = (error as? CocoaError)?.code.rawValue
            ?? (error as NSError).code
        let domain = (error as NSError).domain
        log.error("Failed to delete '\(url.lastPathComponent, privacy: .public)' — \(error.localizedDescription, privacy: .public) (domain=\(domain, privacy: .public) code=\(posix))")
    }

    private nonisolated func fileSize(at url: URL) -> Int64 {
        guard let vals = try? url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]),
              let size = vals.fileSize else { return 0 }
        return Int64(size)
    }
}
