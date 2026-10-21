import AVFoundation
import Foundation

/// Plays one piece of audio data (an MP3 from ElevenLabs, or an AIFF earcon) and waits for it to end.
public final class AudioPlayback: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    /// The player in use and who is waiting for it. Callbacks from any other player are ignored.
    private var current: (player: AVAudioPlayer, continuation: CheckedContinuation<Void, Error>)?

    public override init() {
        super.init()
    }

    public func play(_ data: Data) async throws {
        try Task.checkCancellation()
        preempt()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw SpeakerError.badAudio
        }
        player.delegate = self
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                current = (player, continuation)
                lock.unlock()
                if !player.play() {
                    finish(player, .failure(SpeakerError.playbackFailed("could not start")))
                }
            }
        } onCancel: {
            preempt()
        }
    }

    public func stop() {
        preempt()
    }

    /// Takes the current continuation out, stops its player and resumes it as cancelled.
    private func preempt() {
        lock.lock()
        let previous = current
        current = nil
        lock.unlock()
        previous?.player.stop()
        previous?.continuation.resume(throwing: CancellationError())
    }

    private func finish(_ player: AVAudioPlayer, _ result: Result<Void, Error>) {
        lock.lock()
        guard let current, current.player === player else {
            lock.unlock()
            return
        }
        self.current = nil
        lock.unlock()
        current.continuation.resume(with: result)
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(player, flag ? .success(()) : .failure(SpeakerError.playbackFailed("stopped early")))
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish(player, .failure(SpeakerError.playbackFailed(error?.localizedDescription ?? "decode error")))
    }
}
