import Foundation

/// Watches a single file and reports when its contents change.
///
/// A `DispatchSource` file system object is tied to a file descriptor, which
/// means it follows the *inode*, not the path. Most editors save with an atomic
/// replace (write a temporary file, then rename it over the original), so the
/// descriptor we hold ends up pointing at a file that no longer has a name. The
/// watcher treats `.rename`, `.delete` and `.revoke` as "the path now holds a
/// different file" and re-arms itself on the path, retrying for a short while
/// because the replacement can be a few milliseconds late.
final class FileWatcher {
    private enum Constants {
        /// Coalesces the burst of events a single save produces.
        static let debounce: DispatchTimeInterval = .milliseconds(120)
        /// Atomic replaces leave the path briefly empty; keep looking for it.
        static let rearmRetryDelay: DispatchTimeInterval = .milliseconds(100)
        static let maxRearmAttempts = 50
    }

    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.tonnom.Mark.FileWatcher")

    private var source: DispatchSourceFileSystemObject?
    private var pendingNotification: DispatchWorkItem?
    private var rearmAttempts = 0
    private var isRunning = false

    /// - Parameter onChange: Called on the main queue after the file settles.
    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit {
        // `stop()` hops onto the serial queue, which is not safe from deinit.
        source?.cancel()
        pendingNotification?.cancel()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.rearmAttempts = 0
            self.arm()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.pendingNotification?.cancel()
            self.pendingNotification = nil
            self.disarm()
        }
    }

    // MARK: - Watching

    private func arm() {
        guard isRunning else { return }
        disarm()

        // O_EVTONLY asks for change notifications without keeping the file
        // "open" in a way that would block an unmount.
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleRearm()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
            queue: queue
        )

        // The source is captured strongly so the handler always reports its
        // own events, never a successor's. `cancel()` releases the handler and
        // with it the cycle, and every path out of here cancels.
        source.setEventHandler { [weak self, source] in
            self?.handle(events: source.data)
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        self.rearmAttempts = 0
        source.resume()
    }

    private func disarm() {
        source?.cancel() // The cancel handler closes the descriptor.
        source = nil
    }

    private func handle(events: DispatchSource.FileSystemEvent) {
        guard isRunning else { return }

        if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
            // The path was replaced or moved: start over on the path itself.
            rearmAttempts = 0
            arm()
            scheduleNotification()
            return
        }

        if events.contains(.write) || events.contains(.extend) || events.contains(.attrib) {
            scheduleNotification()
        }
    }

    private func scheduleRearm() {
        guard isRunning, rearmAttempts < Constants.maxRearmAttempts else { return }
        rearmAttempts += 1
        queue.asyncAfter(deadline: .now() + Constants.rearmRetryDelay) { [weak self] in
            guard let self, self.isRunning, self.source == nil else { return }
            self.arm()
            if self.source != nil {
                self.scheduleNotification()
            }
        }
    }

    // MARK: - Notification

    private func scheduleNotification() {
        pendingNotification?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.pendingNotification = nil
            DispatchQueue.main.async { self.onChange() }
        }
        pendingNotification = work
        queue.asyncAfter(deadline: .now() + Constants.debounce, execute: work)
    }
}
