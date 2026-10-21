import AVFoundation
import Foundation

/// The on-device voice: no key, no network, always available.
public final class AppleSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceIdentifier: @Sendable () -> String?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    public init(voiceIdentifier: @escaping @Sendable () -> String?) {
        self.voiceIdentifier = voiceIdentifier
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String) async throws {
        let utterance = AVSpeechUtterance(string: text)
        if let identifier = voiceIdentifier(), let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                synthesizer.speak(utterance)
            }
        } onCancel: {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    public func stop() async {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(.success(()))
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(.failure(CancellationError()))
    }
}
