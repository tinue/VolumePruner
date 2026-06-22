import AppKit
import Observation
import OSLog

private let log = Logger(subsystem: "ch.erzberger.VolumePruner", category: "AppState")

// Central state object for the app. @Observable drives SwiftUI updates;
// @MainActor ensures all mutations happen on the main thread.
@Observable
@MainActor
final class AppState {
    private(set) var mountedVolumes: [VolumeInfo] = []
    private(set) var cleanHistory: [CleanEvent] = []
    // Keyed by volume URL — updated by background scan tasks and after each clean.
    private(set) var volumeStatuses: [URL: VolumeStatus] = [:]
    private(set) var needsFullDiskAccess = false

    var maxVolumeSizeGB: Int = 2000 {
        didSet { UserDefaults.standard.set(maxVolumeSizeGB, forKey: "maxVolumeSizeGB") }
    }

    var scanIntervalSeconds: Int = 10 {
        didSet { UserDefaults.standard.set(scanIntervalSeconds, forKey: "scanIntervalSeconds") }
    }

    // Keyed by VolumeInfo.watchKey (UUID-based), value is the display name.
    // Persisted so the user sees a meaningful label for unmounted volumes in Settings.
    var watchedVolumes: [String: String] = [:] {
        didSet { saveWatchedVolumes() }
    }

    private var watchers: [URL: VolumeWatcher] = [:]
    // One in-flight Task per volume so we don't stack up redundant status checks.
    private var statusTasks: [URL: Task<Void, Never>] = [:]
    private var mountToken: Any?
    private var unmountToken: Any?

    init() {
        loadPreferences()
        setupNotifications()
        refreshMountedVolumes()
        requestRemovablePermissionIfNeeded()
        Task { await checkFullDiskAccess() }
        Task { await runPeriodicScans() }
    }

    private func runPeriodicScans() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(scanIntervalSeconds))
            refreshStatuses()
        }
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
            needsFullDiskAccess = (code == NSFileReadNoPermissionError || code == 1)
        }
    }

    // MARK: - Public actions

    // Schedules a status check for every mounted volume that doesn't already
    // have one running. Returns immediately — each check runs independently.
    func refreshStatuses() {
        log.debug("refreshStatuses: scheduling checks for \(self.mountedVolumes.count) volume(s)")
        for volume in mountedVolumes {
            scheduleStatusCheck(for: volume)
        }
    }

    private func scheduleStatusCheck(for volume: VolumeInfo) {
        guard statusTasks[volume.id] == nil else { return }
        log.debug("scheduleStatusCheck: starting for '\(volume.name, privacy: .public)'")
        statusTasks[volume.id] = Task {
            let dirty = await VolumeCleaner.shared.hasJunk(volume: volume)
            volumeStatuses[volume.id] = dirty ? .dirty : .clean
            statusTasks.removeValue(forKey: volume.id)
        }
    }

    func clean(volume: VolumeInfo, ejectAfter: Bool = false) async {
        volumeStatuses[volume.id] = .unknown
        let result = await VolumeCleaner.shared.clean(volume: volume)
        if !result.errors.isEmpty {
            log.error("Clean of '\(volume.name, privacy: .public)' had \(result.errors.count) error(s): \(result.errors.joined(separator: "; "), privacy: .public)")
        }
        if result.hadPermissionError {
            needsFullDiskAccess = true
        }
        volumeStatuses[volume.id] = result.errors.isEmpty ? .clean : .dirty
        addCleanEvent(CleanEvent(
            date: Date(),
            volumeName: volume.name,
            filesRemoved: result.filesRemoved,
            bytesReclaimed: result.bytesReclaimed
        ))
        if ejectAfter {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.id)
            // No need to call refreshMountedVolumes() here — didUnmountNotification
            // fires synchronously and surgically removes the volume from our state.
        }
    }

    func toggleWatch(volume: VolumeInfo) {
        if watchers[volume.id] != nil {
            stopWatching(volume)
            watchedVolumes.removeValue(forKey: volume.watchKey)
        } else {
            watchedVolumes[volume.watchKey] = volume.name
            startWatching(volume)
        }
    }

    func isWatching(_ volume: VolumeInfo) -> Bool {
        watchers[volume.id] != nil
    }

    func removeWatchedVolume(key: String) {
        if let volume = mountedVolumes.first(where: { $0.watchKey == key }) {
            stopWatching(volume)
        }
        watchedVolumes.removeValue(forKey: key)
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
            // Extract the URL before entering assumeIsolated — Notification is not Sendable
            // in Swift 6, so it cannot be captured by the @Sendable closure.
            let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated {
                log.debug("didMountNotification — url: \(url?.path ?? "nil", privacy: .public)")
                guard let self,
                      let url,
                      let info = VolumeInfo(url: url),
                      SafetyGuard.isEligible(volume: info, maxGB: self.maxVolumeSizeGB)
                else { return }
                self.mountedVolumes.append(info)
                self.scheduleStatusCheck(for: info)
                if self.watchedVolumes[info.watchKey] != nil {
                    self.startWatching(info)
                }
            }
        }

        unmountToken = nc.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated {
                guard let self, let url else { return }
                self.statusTasks[url]?.cancel()
                self.statusTasks.removeValue(forKey: url)
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

        // Single pass: resume any persisted watch and kick off a status check.
        for volume in mountedVolumes {
            if watchedVolumes[volume.watchKey] != nil && watchers[volume.id] == nil {
                startWatching(volume)
            }
            scheduleStatusCheck(for: volume)
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
        if let secs = UserDefaults.standard.object(forKey: "scanIntervalSeconds") as? Int {
            scanIntervalSeconds = secs
        }
        if let data = UserDefaults.standard.data(forKey: "watchedVolumes"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            watchedVolumes = dict
        }
    }

    private func saveWatchedVolumes() {
        if let data = try? JSONEncoder().encode(watchedVolumes) {
            UserDefaults.standard.set(data, forKey: "watchedVolumes")
        }
    }
}
