import Foundation

public enum InboxWatcherError: Error, Equatable {
    case cannotOpen(path: String, errno: Int32)
}

/// Calls `onChange` whenever a file is added to or removed from the inbox directory.
public final class InboxWatcher: @unchecked Sendable {
    private let directory: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?

    public init(directory: URL, queue: DispatchQueue = .global(qos: .userInitiated), onChange: @escaping @Sendable () -> Void) {
        self.directory = directory
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { throw InboxWatcherError.cannotOpen(path: directory.path, errno: errno) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setEventHandler { [onChange] in onChange() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        source?.cancel()
        source = nil
    }
}
