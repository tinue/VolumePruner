import Foundation
import OSLog

actor VolumeCleaner {
    static let shared = VolumeCleaner()
    nonisolated private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "VolumeCleaner")

    // Exact names of Mac metadata/junk files that are safe to remove on FAT/exFAT/NTFS volumes.
    private let exactNames: Set<String> = [
        ".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd",
        "Thumbs.db", "desktop.ini"
    ]

    // True for any filename that is a known junk artifact — either an exact match or
    // an AppleDouble resource fork (the "._" prefix that macOS creates on non-HFS volumes).
    private nonisolated func isJunk(_ name: String) -> Bool {
        exactNames.contains(name) || name.hasPrefix("._")
    }

    // Removes all junk files from the volume and returns a summary of what was done.
    func clean(volume: VolumeInfo) async -> CleanResult {
        var filesRemoved = 0
        var bytesReclaimed: Int64 = 0
        var errors: [String] = []
        var hadPermissionError = false
        let fm = FileManager.default

        log.info("Starting clean on '\(volume.name, privacy: .public)' (fs=\(volume.fsTypeName, privacy: .public))")
        disableSpotlight(on: volume.id.path)
        // Brief pause so mdutil has time to release its index lock before we enumerate.
        try? await Task.sleep(for: .milliseconds(500))

        guard let enumerator = fm.enumerator(
            at: volume.id,
            includingPropertiesForKeys: [URLResourceKey.fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            log.error("Cannot enumerate '\(volume.name, privacy: .public)'")
            return CleanResult(filesRemoved: 0, bytesReclaimed: 0, errors: ["Cannot enumerate volume"], hadPermissionError: false)
        }

        // Collect before deleting so we don't mutate the directory mid-enumeration.
        var toRemove: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            if isJunk(name) {
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
                if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileWriteNoPermissionError {
                    hadPermissionError = true
                }
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

    // nonisolated so concurrent calls for different volumes don't serialize
    // through the actor. Blocking I/O runs on a DispatchQueue thread so the
    // cooperative pool is never stalled by a slow volume.
    nonisolated func hasJunk(volume: VolumeInfo) async -> Bool {
        let log = self.log
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                let start = ContinuousClock.now
                guard let enumerator = FileManager.default.enumerator(
                    at: volume.id,
                    includingPropertiesForKeys: nil,
                    options: [.skipsPackageDescendants]
                ) else {
                    log.error("hasJunk: enumerator failed for '\(volume.name, privacy: .public)'")
                    continuation.resume(returning: false)
                    return
                }
                var scanned = 0
                while let url = enumerator.nextObject() as? URL {
                    scanned += 1
                    let name = url.lastPathComponent
                    if isJunk(name) {
                        let elapsed = start.duration(to: .now)
                        log.debug("hasJunk '\(volume.name, privacy: .public)': dirty — found '\(name, privacy: .public)' after \(scanned) entries in \(elapsed, privacy: .public)")
                        continuation.resume(returning: true)
                        return
                    }
                }
                let elapsed = start.duration(to: .now)
                log.debug("hasJunk '\(volume.name, privacy: .public)': clean — scanned \(scanned) entries in \(elapsed, privacy: .public)")
                continuation.resume(returning: false)
            }
        }
    }

    // Turns off Spotlight indexing on the volume before cleaning so the indexer
    // doesn't race with our deletion of .Spotlight-V100.
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
