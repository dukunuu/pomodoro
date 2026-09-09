import Foundation

/// Atomic read/write plus change watching, mirroring the guarantees the
/// Quickshell `FileView` gave the QML service. The Python bridges and an
/// external editor also write these files, so every write replaces the file
/// wholesale and every file is re-read when it changes underneath us.
enum AtomicFile {
    static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    @discardableResult
    static func write(_ text: String, to url: URL) -> Bool {
        DataPaths.ensureDirectory()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}

/// Watches a single path for writes made by the Python bridges or an external
/// editor. Rewatches after atomic replaces, which delete the
/// original inode and therefore kill a naive vnode source.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var retryTimer: Timer?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        retryTimer?.invalidate()
        source?.cancel()
    }

    private func start() {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleRetry()
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.onChange()
            if flags.contains(.delete) || flags.contains(.rename) {
                self.restart()
            }
        }
        source.setCancelHandler { [descriptor = self.descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    private func restart() {
        source?.cancel()
        source = nil
        descriptor = -1
        // The replacement file may not exist for a moment during an atomic swap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.start()
        }
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.start()
        }
    }
}
