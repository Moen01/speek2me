import AVFoundation
import Foundation

/// The on-device voice: no key, no network, always available.
public final class AppleSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceIdentifier: @Sendable () -> String?
    private let lock = NSLock()
    /// The utterance being spoken and who is waiting for it. Delegate callbacks for any other
    /// utterance are ignored, so a replaced utterance can never resume the wrong continuation.
    private var current: (utterance: AVSpeechUtterance, continuation: CheckedContinuation<Void, Error>)?

    public init(voiceIdentifier: @escaping @Sendable () -> String?) {
        self.voiceIdentifier = voiceIdentifier
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String) async throws {
        try Task.checkCancellation()
        // A new announcement replaces one still being spoken; its caller is told it was cancelled.
        preempt()
        let utterance = AVSpeechUtterance(string: text)
        if let identifier = voiceIdentifier(), let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                current = (utterance, continuation)
                lock.unlock()
                synthesizer.speak(utterance)
            }
        } onCancel: {
            preempt()
        }
    }

    public func stop() async {
        preempt()
    }

    /// Takes the current continuation out, resumes it as cancelled and silences the synthesizer.
    private func preempt() {
        lock.lock()
        let previous = current
        current = nil
        lock.unlock()
        synthesizer.stopSpeaking(at: .immediate)
        previous?.continuation.resume(throwing: CancellationError())
    }

    private func finish(_ utterance: AVSpeechUtterance, _ result: Result<Void, Error>) {
        lock.lock()
        guard let current, current.utterance === utterance else {
            lock.unlock()
            return
        }
        self.current = nil
        lock.unlock()
        current.continuation.resume(with: result)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(utterance, .success(()))
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(utterance, .failure(CancellationError()))
    }
}
