import AppKit
import Observation
import OSLog

private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "AppState")

@Observable
@MainActor
final class AppState {
    private(set) var mountedVolumes: [VolumeInfo] = []
    private(set) var cleanHistory: [CleanEvent] = []
    private(set) var volumeStatuses: [URL: VolumeStatus] = [:]
    private(set) var needsFullDiskAccess = false

    var maxVolumeSizeGB: Int = 2000 {
        didSet { UserDefaults.standard.set(maxVolumeSizeGB, forKey: "maxVolumeSizeGB") }
    }

    var watchedPaths: Set<URL> = [] {
        didSet { saveWatchedPaths() }
    }

    private var watchers: [URL: VolumeWatcher] = [:]
    private var mountToken: Any?
    private var unmountToken: Any?

    init() {
        loadPreferences()
        setupNotifications()
        refreshMountedVolumes()
        requestRemovablePermissionIfNeeded()
        Task { await checkFullDiskAccess() }
    }

    // Trigger the one-time TCC removable-volume permission dialog at launch
    // rather than on the first menu open, so the user understands the context.
    private func requestRemovablePermissionIfNeeded() {
        guard let removable = mountedVolumes.first(where: { $0.isRemovable }) else { return }
        _ = try? FileManager.default.contentsOfDirectory(
            at: removable.id, includingPropertiesForKeys: nil, options: [])
    }

    // ~/Library/Safari is TCC-protected. If we can list it we have FDA;
    // if we get a permission error we don't. Any other error (e.g. ENOENT)
    // means the directory doesn't exist, which we treat as FDA present so
    // we don't show a false warning.
    func checkFullDiskAccess() async {
        let safari = URL.homeDirectory.appendingPathComponent("Library/Safari")
        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: safari, includingPropertiesForKeys: nil, options: [])
            needsFullDiskAccess = false
        } catch {
            let code = (error as NSError).code
            needsFullDiskAccess = (code == NSFileReadNoPermissionError || code == 1) // 1 = EPERM
        }
    }

    // MARK: - Public actions

    func refreshStatuses() async {
        for volume in mountedVolumes {
            let dirty = await VolumeCleaner.shared.hasJunk(volume: volume)
            volumeStatuses[volume.id] = dirty ? .dirty : .clean
        }
    }

    func clean(volume: VolumeInfo, ejectAfter: Bool = false) async {
        volumeStatuses[volume.id] = .unknown
        let result = await VolumeCleaner.shared.clean(volume: volume, recursive: volume.isRemovable)
        if !result.errors.isEmpty {
            log.error("Clean of '\(volume.name, privacy: .public)' had \(result.errors.count) error(s): \(result.errors.joined(separator: "; "), privacy: .public)")
        }
        if result.hadPermissionError {
            needsFullDiskAccess = true
        }
        addCleanEvent(CleanEvent(
            date: Date(),
            volumeName: volume.name,
            filesRemoved: result.filesRemoved,
            bytesReclaimed: result.bytesReclaimed
        ))
        if ejectAfter {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.id)
            refreshMountedVolumes()
        }
    }

    func toggleWatch(volume: VolumeInfo) {
        if watchers[volume.id] != nil {
            stopWatching(volume)
            watchedPaths.remove(volume.id)
        } else {
            watchedPaths.insert(volume.id)
            startWatching(volume)
        }
    }

    func isWatching(_ volume: VolumeInfo) -> Bool {
        watchers[volume.id] != nil
    }

    func removeWatchedPath(_ url: URL) {
        if let volume = mountedVolumes.first(where: { $0.id == url }) {
            stopWatching(volume)
        }
        watchedPaths.remove(url)
    }

    // MARK: - Private

    private func startWatching(_ volume: VolumeInfo) {
        let url = volume.id
        watchers[url] = VolumeWatcher(url: url) { [weak self] in
            await self?.clean(volume: volume)
        }
    }

    private func stopWatching(_ volume: VolumeInfo) {
        watchers[volume.id]?.stop()
        watchers.removeValue(forKey: volume.id)
    }

    private func setupNotifications() {
        let nc = NSWorkspace.shared.notificationCenter

        mountToken = nc.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
                log.debug("didMountNotification — url: \(url?.path ?? "nil", privacy: .public)")
                guard let self,
                      let url,
                      let info = VolumeInfo(url: url),
                      SafetyGuard.isEligible(volume: info, maxGB: self.maxVolumeSizeGB)
                else { return }
                self.mountedVolumes.append(info)
                if self.watchedPaths.contains(url) {
                    self.startWatching(info)
                }
            }
        }

        unmountToken = nc.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
                else { return }
                self.watchers[url]?.stop()
                self.watchers.removeValue(forKey: url)
                self.mountedVolumes.removeAll { $0.id == url }
            }
        }
    }

    private func refreshMountedVolumes() {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey],
            options: []
        ) ?? []

        log.debug("mountedVolumeURLs returned \(urls.count) URL(s)")
        for url in urls { log.debug("  url: \(url.path, privacy: .public)") }

        mountedVolumes = urls
            .compactMap { VolumeInfo(url: $0) }
            .filter { SafetyGuard.isEligible(volume: $0, maxGB: maxVolumeSizeGB) }

        log.debug("After filtering: \(self.mountedVolumes.count) eligible volume(s)")

        for volume in mountedVolumes where watchedPaths.contains(volume.id) && watchers[volume.id] == nil {
            startWatching(volume)
        }
    }

    private func addCleanEvent(_ event: CleanEvent) {
        cleanHistory.insert(event, at: 0)
        if cleanHistory.count > 50 { cleanHistory.removeLast() }
    }

    private func loadPreferences() {
        if let gb = UserDefaults.standard.object(forKey: "maxVolumeSizeGB") as? Int {
            maxVolumeSizeGB = gb
        }
        if let data = UserDefaults.standard.data(forKey: "watchedPaths"),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            watchedPaths = Set(paths.compactMap { URL(string: $0) })
        }
    }

    private func saveWatchedPaths() {
        let paths = watchedPaths.map(\.absoluteString)
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: "watchedPaths")
        }
    }
}
