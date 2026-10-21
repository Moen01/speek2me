import AVFoundation
import Foundation

/// Plays one piece of audio data (an MP3 from ElevenLabs, or an AIFF earcon) and waits for it to end.
public final class AudioPlayback: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Error>?

    public override init() {
        super.init()
    }

    public func play(_ data: Data) async throws {
        stop()
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
                self.player = player
                self.continuation = continuation
                lock.unlock()
                if !player.play() {
                    finish(.failure(SpeakerError.playbackFailed("could not start")))
                }
            }
        } onCancel: {
            stop()
        }
    }

    public func stop() {
        lock.lock()
        let player = self.player
        let continuation = self.continuation
        self.player = nil
        self.continuation = nil
        lock.unlock()
        player?.stop()
        continuation?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.player = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(flag ? .success(()) : .failure(SpeakerError.playbackFailed("stopped early")))
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish(.failure(SpeakerError.playbackFailed(error?.localizedDescription ?? "decode error")))
    }
}
