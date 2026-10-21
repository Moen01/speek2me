import Foundation

/// Speaks one event at a time. A newer event from the same session replaces an unspoken older
/// one: when three turns end before you hear the first, only the latest matters.
public actor AnnouncementQueue {
    private let process: @Sendable (SessionEvent) async -> Void
    private var queue: [SessionEvent] = []
    private var worker: Task<Void, Never>?
    private var generation = 0
    public private(set) var lastSpoken: SessionEvent?

    public init(process: @escaping @Sendable (SessionEvent) async -> Void) {
        self.process = process
    }

    public var pending: [SessionEvent] { queue }

    public func enqueue(_ event: SessionEvent) {
        queue.removeAll { $0.sessionID == event.sessionID }
        queue.append(event)
        startWorkerIfNeeded()
    }

    /// Cancels what is being spoken and forgets everything waiting.
    public func stop() {
        queue.removeAll()
        worker?.cancel()
        worker = nil
        generation += 1
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        generation += 1
        let current = generation
        worker = Task { await self.drain(generation: current) }
    }

    private func drain(generation: Int) async {
        while !Task.isCancelled, !queue.isEmpty {
            let event = queue.removeFirst()
            await process(event)
            if !Task.isCancelled { lastSpoken = event }
        }
        // A stop() may have replaced this worker already; only clear our own slot.
        if self.generation == generation { worker = nil }
    }
}
