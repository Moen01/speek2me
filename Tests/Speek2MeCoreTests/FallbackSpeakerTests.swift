import Foundation
import Testing
@testable import Speek2MeCore

final class FakeSpeaker: Speaker, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var spoken: [String] = []
    private(set) var stops = 0
    var error: SpeakerError?

    init(error: SpeakerError? = nil) { self.error = error }

    func speak(_ text: String) async throws {
        try lock.withLock {
            if let error { throw error }
            spoken.append(text)
        }
    }

    func stop() async {
        lock.withLock { stops += 1 }
    }
}

struct FallbackSpeakerTests {
    @Test func primaryFailureFallsThroughWithSameText() async throws {
        let primary = FakeSpeaker(error: .invalidAPIKey("bad"))
        let fallback = FakeSpeaker()
        let reasons = Reasons()
        let speaker = FallbackSpeaker(primary: primary, fallback: fallback) { reasons.add($0) }
        try await speaker.speak("hello")
        #expect(primary.spoken.isEmpty)
        #expect(fallback.spoken == ["hello"])
        #expect(reasons.values.count == 1)
        #expect(reasons.values.first?.contains("bad") == true)
    }

    @Test func missingPrimaryGoesStraightToFallback() async throws {
        let fallback = FakeSpeaker()
        let reasons = Reasons()
        let speaker = FallbackSpeaker(primary: nil, fallback: fallback) { reasons.add($0) }
        try await speaker.speak("hi")
        #expect(fallback.spoken == ["hi"])
        #expect(reasons.values.isEmpty)
    }

    @Test func workingPrimaryIsUsedAndStopReachesBoth() async throws {
        let primary = FakeSpeaker()
        let fallback = FakeSpeaker()
        let speaker = FallbackSpeaker(primary: primary, fallback: fallback) { _ in }
        try await speaker.speak("hi")
        await speaker.stop()
        #expect(primary.spoken == ["hi"])
        #expect(fallback.spoken.isEmpty)
        #expect(primary.stops == 1 && fallback.stops == 1)
    }

    @Test func badAudioDataIsReported() async {
        await #expect(throws: SpeakerError.badAudio) {
            try await AudioPlayback().play(Data("not audio".utf8))
        }
    }

    private final class Reasons: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var values: [String] = []
        func add(_ value: String) { lock.lock(); values.append(value); lock.unlock() }
    }
}
