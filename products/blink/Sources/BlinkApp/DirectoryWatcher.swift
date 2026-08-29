import Foundation

/// Watches a directory for writes and fires a debounced callback on the main
/// actor. Watching the *directory* (not files) is deliberate: Blink's writers
/// are all atomic temp+rename, which replaces file inodes — a per-file watch
/// would go stale after the first save. Same pattern as the config watcher.
@MainActor
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?
    private let interval: Duration
    private let onChange: () -> Void

    init?(
        directory: URL,
        debounce interval: Duration = .milliseconds(300),
        onChange: @escaping () -> Void
    ) {
        self.interval = interval
        self.onChange = onChange

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleFire() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// Directory events burst (temp file create + rename per atomic write);
    /// coalesce them so one save triggers one callback.
    private func scheduleFire() {
        debounce?.cancel()
        debounce = Task { [weak self, interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }

    deinit {
        source?.cancel()
    }
}
