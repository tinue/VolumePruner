import Foundation
import OSLog

actor VolumeCleaner {
    static let shared = VolumeCleaner()
    nonisolated private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "VolumeCleaner")

    private let exactNames: Set<String> = [
        ".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd",
        "Thumbs.db", "desktop.ini"
    ]

    func clean(volume: VolumeInfo) async -> CleanResult {
        var filesRemoved = 0
        var bytesReclaimed: Int64 = 0
        var errors: [String] = []
        var hadPermissionError = false
        let fm = FileManager.default

        log.info("Starting clean on '\(volume.name, privacy: .public)' (fs=\(volume.fsTypeName, privacy: .public))")
        disableSpotlight(on: volume.id.path)
        try? await Task.sleep(for: .milliseconds(500))

        guard let enumerator = fm.enumerator(
            at: volume.id,
            includingPropertiesForKeys: [URLResourceKey.fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            log.error("Cannot enumerate '\(volume.name, privacy: .public)'")
            return CleanResult(filesRemoved: 0, bytesReclaimed: 0, errors: ["Cannot enumerate volume"], hadPermissionError: false)
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
                let nsErr = error as NSError
                log.error("Failed '\(url.lastPathComponent, privacy: .public)': \(error.localizedDescription, privacy: .public) (domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code))")
                if nsErr.code == 513 { hadPermissionError = true }
                errors.append(url.lastPathComponent + ": " + error.localizedDescription)
            }
        }

        if errors.isEmpty {
            log.info("Clean complete: \(filesRemoved) file(s) removed, \(bytesReclaimed) bytes reclaimed")
        } else {
            log.warning("Clean finished with \(errors.count) failure(s): \(filesRemoved) removed, \(errors.joined(separator: "; "), privacy: .public)")
        }

        return CleanResult(filesRemoved: filesRemoved, bytesReclaimed: bytesReclaimed,
                           errors: errors, hadPermissionError: hadPermissionError)
    }

    // Recurse the full volume looking for any junk file. Stops at the first
    // match (early-exit), so it is fast when dirty and only slow when the
    // volume is genuinely clean.
    func hasJunk(volume: VolumeInfo) async -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: volume.id,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) else { return false }

        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            if exactNames.contains(name) || name.hasPrefix("._") {
                return true
            }
        }
        return false
    }

    private nonisolated func disableSpotlight(on path: String) {
        runMdutil(["-i", "off", path])
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
            log.error("mdutil failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated func fileSize(at url: URL) -> Int64 {
        guard let vals = try? url.resourceValues(forKeys: [URLResourceKey.fileSizeKey]),
              let size = vals.fileSize else { return 0 }
        return Int64(size)
    }
}
