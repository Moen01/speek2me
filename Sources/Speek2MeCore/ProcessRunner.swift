import Foundation

public enum ProcessError: Error, Equatable {
    /// The process failed: non-zero exit with nothing on stdout, or it could not be launched.
    case failed(String)
}

/// Runs one command to completion with stdin data, collecting stdout. Cancelling the calling
/// task terminates the process.
public enum ProcessRunner {
    public static func run(
        _ executable: URL,
        arguments: [String],
        stdin input: Data,
        environment: [String: String],
        workingDirectory: URL? = nil
    ) async throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }

        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let collector = OutputCollector()
                let group = DispatchGroup()
                for (pipe, isStdout) in [(stdoutPipe, true), (stderrPipe, false)] {
                    group.enter()
                    DispatchQueue.global().async {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        collector.store(data, stdout: isStdout)
                        group.leave()
                    }
                }
                process.terminationHandler = { process in
                    DispatchQueue.global().async {
                        // A child can keep the pipes open after the process exits; don't wait on it forever.
                        _ = group.wait(timeout: .now() + 1)
                        let (out, err) = collector.values
                        if process.terminationReason == .uncaughtSignal {
                            continuation.resume(throwing: CancellationError())
                        } else if process.terminationStatus != 0, out.isEmpty {
                            let message = String(decoding: err.prefix(300), as: UTF8.self)
                            continuation.resume(throwing: ProcessError.failed(
                                message.isEmpty ? "exit status \(process.terminationStatus)" : message))
                        } else {
                            continuation.resume(returning: out)
                        }
                    }
                }
                do {
                    // Cancelled before launch: do not start a process nobody will wait for.
                    if Task.isCancelled { throw CancellationError() }
                    try process.run()
                    // Throws instead of crashing when the process exits before reading (SIGPIPE is ignored at launch).
                    try? stdinPipe.fileHandleForWriting.write(contentsOf: input)
                    try? stdinPipe.fileHandleForWriting.close()
                } catch {
                    process.terminationHandler = nil
                    // Release the readers waiting on the pipes, or two threads stay blocked per failed launch.
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    continuation.resume(throwing: error is CancellationError ? error : ProcessError.failed(error.localizedDescription))
                }
            }
        } onCancel: {
            guard process.isRunning else { return }
            process.terminate()
            // SIGTERM can be ignored; the deadline must still end.
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    /// An app opened from Finder gets only /usr/bin:/bin:/usr/sbin:/sbin. Put the tool's own
    /// folder first (an npm or pip install needs its interpreter next to it), then the usual places.
    public static func environment(
        for executable: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let preferred = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin"]
        let existing = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        var environment = base
        environment["PATH"] = (preferred + existing.filter { !preferred.contains($0) }).joined(separator: ":")
        return environment
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func store(_ data: Data, stdout: Bool) {
        lock.lock(); defer { lock.unlock() }
        if stdout { out = data } else { err = data }
    }

    var values: (Data, Data) {
        lock.lock(); defer { lock.unlock() }
        return (out, err)
    }
}
