import AVFoundation
import Foundation

/// Plays one piece of audio data (an MP3 from a cloud voice, or an AIFF earcon) and waits for it to end.
///
/// Completion is detected by polling `isPlaying` rather than through the player's delegate: the
/// delegate needs a pumped main run loop, which a test host does not always have, and a callback
/// that never comes would hang the announcement queue for good.
public final class AudioPlayback: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AVAudioPlayer?

    public init() {}

    public func play(_ data: Data) async throws {
        try Task.checkCancellation()
        preempt()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw SpeakerError.badAudio
        }
        lock.withLock { current = player }
        guard player.play() else {
            clear(player)
            throw SpeakerError.playbackFailed("could not start")
        }
        try await withTaskCancellationHandler {
            while isCurrent(player), player.isPlaying {
                try await Task.sleep(for: .milliseconds(40))
            }
        } onCancel: {
            // Stops the current player, which is this one unless something newer replaced it already.
            stop()
        }
        // Stopped or replaced by a newer announcement: the caller is told it was cancelled.
        guard isCurrent(player) else { throw CancellationError() }
        clear(player)
    }

    public func stop() {
        preempt()
    }

    private func isCurrent(_ player: AVAudioPlayer) -> Bool {
        lock.withLock { current === player }
    }

    private func clear(_ player: AVAudioPlayer) {
        lock.withLock { if current === player { current = nil } }
    }

    private func preempt() {
        let previous = lock.withLock { () -> AVAudioPlayer? in
            let player = current
            current = nil
            return player
        }
        previous?.stop()
    }
}
