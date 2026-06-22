import Foundation

// Watches a mounted volume for filesystem changes using a kernel DispatchSource.
// Debounces rapid bursts of write events into a single callback after 2 seconds of quiet.
final class VolumeWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private let onFire: @Sendable () async -> Void

    init(url: URL, onFire: @escaping @Sendable () async -> Void) {
        self.onFire = onFire
        start(url: url)
    }

    private func start(url: URL) {
        // O_EVTONLY opens the path for event monitoring without preventing unmount.
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .link],
            queue: .main
        )
        s.setEventHandler { [weak self] in self?.schedule() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    private func schedule() {
        debounceTask?.cancel()
        let fire = onFire
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await fire()
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
    }

    deinit { debounceTask?.cancel(); source?.cancel() }
}
