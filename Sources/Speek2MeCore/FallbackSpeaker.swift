import Foundation

/// Tries the primary voice and, on any failure except cancellation, says the same text with the
/// fallback voice, reporting why. No primary means the fallback speaks directly.
public struct FallbackSpeaker: Speaker {
    private let primary: (any Speaker)?
    private let fallback: any Speaker
    private let onFallback: @Sendable (String) -> Void

    public init(primary: (any Speaker)?, fallback: any Speaker, onFallback: @escaping @Sendable (String) -> Void) {
        self.primary = primary
        self.fallback = fallback
        self.onFallback = onFallback
    }

    public func speak(_ text: String) async throws {
        if let primary {
            do {
                try await primary.speak(text)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                onFallback((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
        try await fallback.speak(text)
    }

    public func stop() async {
        await primary?.stop()
        await fallback.stop()
    }
}
